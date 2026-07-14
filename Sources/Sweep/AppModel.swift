import SwiftUI
import AppKit

/// All UI state + the glue between the views and the background scanners.
@MainActor
final class AppModel: ObservableObject {

    enum Section: Hashable { case uninstaller, leftovers }
    @Published var section: Section = .uninstaller

    // MARK: Uninstaller — app list
    @Published var apps: [InstalledApp] = []
    @Published var isLoadingApps = false
    @Published var search = ""
    @Published var sort: AppSort = .size

    // MARK: Uninstaller — selected app + its files
    @Published var selectedAppID: InstalledApp.ID?
    @Published var relatedFiles: [RelatedFile] = []
    @Published var isScanningFiles = false

    // MARK: Leftovers
    @Published var leftovers: [LeftoverGroup] = []
    @Published var isScanningLeftovers = false
    @Published var didScanLeftovers = false

    // MARK: Removal flow
    @Published var pendingConfirm: PendingRemoval?
    @Published var result: RemovalResult?
    @Published var adminPrompt: AdminPrompt?

    // MARK: - Derived

    var selectedApp: InstalledApp? { apps.first { $0.id == selectedAppID } }

    var filteredApps: [InstalledApp] {
        var list = apps
        if !search.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(search)
                || ($0.bundleID?.localizedCaseInsensitiveContains(search) ?? false) }
        }
        switch sort {
        case .name:
            list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .size:
            list.sort { $0.sizeBytes > $1.sizeBytes }
        case .lastUsed:
            list.sort { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
        }
        return list
    }

    var selectedFilesSize: Int64 {
        relatedFiles.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes }
    }
    var selectedFilesCount: Int { relatedFiles.filter(\.isSelected).count }
    var relatedFilesTotalSize: Int64 { relatedFiles.reduce(0) { $0 + $1.sizeBytes } }

    var totalReclaimable: Int64 { apps.reduce(0) { $0 + max(0, $1.sizeBytes) } }
    var leftoversTotalSize: Int64 { leftovers.reduce(0) { $0 + $1.totalSize } }

    // MARK: - Loading apps

    func loadAppsIfNeeded() {
        guard apps.isEmpty, !isLoadingApps else { return }
        reloadApps()
    }

    /// Bumped on each reload so a stale (e.g. ⌘R-spammed) background pass can tell
    /// it's been superseded and bail instead of writing over newer results.
    private var loadGeneration = 0

    func reloadApps() {
        isLoadingApps = true
        loadGeneration &+= 1
        let generation = loadGeneration
        Task.detached(priority: .userInitiated) {
            let list = Scanner.installedApps()
            await MainActor.run {
                guard generation == self.loadGeneration else { return }
                self.apps = list
                self.isLoadingApps = false
                // Drop a selection whose app is no longer installed.
                if let sel = self.selectedAppID, !list.contains(where: { $0.id == sel }) {
                    self.deselectApp()
                }
            }
            // Second pass: fill in bundle sizes so the list paints instantly and
            // the (slower) sizes stream in.
            for app in list {
                let size = diskSize(of: app.path)
                await MainActor.run {
                    guard generation == self.loadGeneration else { return }
                    if let i = self.apps.firstIndex(where: { $0.id == app.id }) {
                        self.apps[i].sizeBytes = size
                    }
                }
            }
        }
    }

    // MARK: - Selecting an app → scan its files

    func select(_ app: InstalledApp) {
        selectedAppID = app.id
        relatedFiles = []
        isScanningFiles = true

        let id = app.id, bundleID = app.bundleID, name = app.name, path = app.path
        let knownSize = app.sizeBytes
        Task.detached(priority: .userInitiated) {
            var scanned = Scanner.relatedFiles(bundleID: bundleID, appName: name)
            let appSize = knownSize >= 0 ? knownSize : diskSize(of: path)
            scanned.insert(RelatedFile(url: path, category: .binary,
                                       sizeBytes: appSize, isSelected: true), at: 0)
            let files = scanned
            await MainActor.run {
                guard self.selectedAppID == id else { return } // ignore stale scans
                self.relatedFiles = files
                self.isScanningFiles = false
            }
        }
    }

    func deselectApp() {
        selectedAppID = nil
        relatedFiles = []
    }

    // MARK: File selection toggles

    func toggleFile(_ file: RelatedFile) {
        guard let i = relatedFiles.firstIndex(of: file) else { return }
        // The app bundle (first/.binary row) is the point of uninstalling — keep
        // it locked on.
        guard relatedFiles[i].category != .binary else { return }
        relatedFiles[i].isSelected.toggle()
    }

    func setAllFiles(selected: Bool) {
        for i in relatedFiles.indices where relatedFiles[i].category != .binary {
            relatedFiles[i].isSelected = selected
        }
    }

    func toggleCategory(_ category: FileCategory) {
        let indices = relatedFiles.indices.filter { relatedFiles[$0].category == category }
        let allOn = indices.allSatisfy { relatedFiles[$0].isSelected }
        for i in indices where relatedFiles[i].category != .binary {
            relatedFiles[i].isSelected = !allOn
        }
    }

    // MARK: - Confirm + perform uninstall

    func requestUninstall() {
        guard let app = selectedApp else { return }
        let files = relatedFiles.filter(\.isSelected)
        var message = "\(files.count) item\(files.count == 1 ? "" : "s") will be moved to the Trash."
        if let bid = app.bundleID,
           !NSRunningApplication.runningApplications(withBundleIdentifier: bid).isEmpty {
            message += "\n\n\(app.name) is currently open — quit it first for a clean removal."
        }
        pendingConfirm = PendingRemoval(
            title: "Uninstall \(app.name)?",
            message: message,
            bytes: files.reduce(0) { $0 + $1.sizeBytes },
            files: files,
            appID: app.id,
            appName: app.name
        )
    }

    func performPendingRemoval() {
        guard let pending = pendingConfirm else { return }
        pendingConfirm = nil
        let sizes = Dictionary(pending.files.map { ($0.url, $0.sizeBytes) }, uniquingKeysWith: { a, _ in a })
        let urls = pending.files.map(\.url)

        Task.detached(priority: .userInitiated) {
            let outcome = Remover.moveToTrash(urls, sizes: sizes)
            await MainActor.run {
                self.finish(outcome, sizes: sizes, title: "\(pending.appName) was uninstalled",
                            removedAppID: pending.appID)
            }
        }
    }

    // MARK: - Leftovers

    func scanLeftovers() {
        isScanningLeftovers = true
        Task.detached(priority: .userInitiated) {
            let installed = Scanner.allBundleIDs()
            let groups = Scanner.leftovers(installed: installed)
            await MainActor.run {
                self.leftovers = groups
                self.isScanningLeftovers = false
                self.didScanLeftovers = true
            }
        }
    }

    func toggleLeftoverFile(group: LeftoverGroup, file: RelatedFile) {
        guard let gi = leftovers.firstIndex(of: group),
              let fi = leftovers[gi].files.firstIndex(of: file) else { return }
        leftovers[gi].files[fi].isSelected.toggle()
    }

    func toggleLeftoverGroup(_ group: LeftoverGroup) {
        guard let gi = leftovers.firstIndex(of: group) else { return }
        let turnOn = !leftovers[gi].isFullySelected
        for fi in leftovers[gi].files.indices { leftovers[gi].files[fi].isSelected = turnOn }
    }

    func removeSelectedLeftovers() {
        let files = leftovers.flatMap { $0.files.filter(\.isSelected) }
        guard !files.isEmpty else { return }
        let sizes = Dictionary(files.map { ($0.url, $0.sizeBytes) }, uniquingKeysWith: { a, _ in a })
        let urls = files.map(\.url)
        Task.detached(priority: .userInitiated) {
            let outcome = Remover.moveToTrash(urls, sizes: sizes)
            await MainActor.run {
                self.finish(outcome, sizes: sizes, title: "Leftovers removed", removedAppID: nil)
                // Drop emptied groups / files from the list.
                let gone = Set(outcome.trashed)
                self.leftovers = self.leftovers.compactMap { g in
                    var g = g
                    g.files.removeAll { gone.contains($0.url) }
                    return g.files.isEmpty ? nil : g
                }
            }
        }
    }

    // MARK: - Shared completion / admin escalation

    private func finish(_ outcome: Remover.Outcome, sizes: [URL: Int64],
                        title: String, removedAppID: InstalledApp.ID?) {
        if let id = removedAppID {
            // Drop the app from the list only once its bundle is actually gone
            // (a bundle that needed admin rights to remove may still be present).
            let stillInstalled = apps.first { $0.id == id }
                .map { FileManager.default.fileExists(atPath: $0.path.path) } ?? false
            if !stillInstalled {
                apps.removeAll { $0.id == id }
                if selectedAppID == id { deselectApp() }
            }
        }

        result = RemovalResult(title: title, freedBytes: outcome.freedBytes,
                               removedCount: outcome.trashed.count,
                               failedCount: outcome.otherFailures.count + outcome.needsAdmin.count)

        if !outcome.needsAdmin.isEmpty {
            adminPrompt = AdminPrompt(urls: outcome.needsAdmin,
                                      bytes: outcome.needsAdmin.reduce(0) { $0 + (sizes[$1] ?? 0) })
        }
    }

    func performAdminRemoval() {
        guard let prompt = adminPrompt else { return }
        adminPrompt = nil
        let urls = prompt.urls
        Task.detached(priority: .userInitiated) {
            let ok = Remover.removeWithAdmin(urls)
            await MainActor.run {
                if ok {
                    let freed = prompt.bytes
                    self.result = RemovalResult(title: "Admin items removed",
                                                freedBytes: freed, removedCount: urls.count,
                                                failedCount: 0)
                }
            }
        }
    }
}

// MARK: - Small flow value types

struct PendingRemoval: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let bytes: Int64
    let files: [RelatedFile]
    let appID: InstalledApp.ID
    let appName: String
}

struct AdminPrompt: Identifiable {
    let id = UUID()
    let urls: [URL]
    let bytes: Int64
}
