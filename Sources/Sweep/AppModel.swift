import SwiftUI
import AppKit

/// All UI state + the glue between the views and the background scanners.
@MainActor
final class AppModel: ObservableObject {

    enum Section: Hashable { case uninstaller, leftovers, largeFiles }
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

    // MARK: Large files
    @Published var largeFiles: [LargeFile] = []
    @Published var isScanningLargeFiles = false
    @Published var didScanLargeFiles = false
    @Published var threshold: SizeThreshold = .mb100
    @Published var largeFileSort: LargeFileSort = .size

    // MARK: Removal flow
    @Published var pendingConfirm: PendingRemoval?
    @Published var result: RemovalResult?
    @Published var adminPrompt: AdminPrompt?
    @Published var failureReport: FailureReport?

    /// Failures that elevating can't fix, held back until after the administrator
    /// pass so the user gets one combined report instead of two dialogs.
    private var deferredFailures: [Remover.Failure] = []

    /// Identifies the newest large-files scan, so a slower earlier one can't
    /// overwrite its results.
    private var largeScanToken = 0

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

    var sortedLargeFiles: [LargeFile] {
        switch largeFileSort {
        case .size:   return largeFiles.sorted { $0.sizeBytes > $1.sizeBytes }
        // Unknown dates sort last rather than masquerading as the oldest files.
        case .oldest: return largeFiles.sorted { ($0.modified ?? .distantFuture) < ($1.modified ?? .distantFuture) }
        }
    }
    var largeFilesTotalSize: Int64 { largeFiles.reduce(0) { $0 + $1.sizeBytes } }
    /// The scan caps its results, so say "largest N" rather than implying N is all there is.
    var largeFilesTruncated: Bool { largeFiles.count >= Scanner.largeFileLimit }
    var selectedLargeFiles: [LargeFile] { largeFiles.filter(\.isSelected) }
    var selectedLargeFilesSize: Int64 { selectedLargeFiles.reduce(0) { $0 + $1.sizeBytes } }

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

    // Look rows up by identity, never by value: `==` on these structs also
    // compares `isSelected`, so a value-based search silently misses (and the
    // click does nothing) whenever the model changed between render and tap.
    func toggleFile(_ file: RelatedFile) {
        guard let i = relatedFiles.firstIndex(where: { $0.id == file.id }) else { return }
        // The app bundle (first/.binary row) is the point of uninstalling, so
        // keep it locked on.
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
            message += "\n\n\(app.name) is currently open. Quit it first for a clean removal."
        }
        pendingConfirm = PendingRemoval(
            title: "Uninstall \(app.name)?",
            message: message,
            bytes: files.reduce(0) { $0 + $1.sizeBytes },
            urls: files.map(\.url),
            sizes: Dictionary(files.map { ($0.url, $0.sizeBytes) }, uniquingKeysWith: { a, _ in a }),
            appID: app.id,
            successTitle: "\(app.name) was uninstalled"
        )
    }

    func performPendingRemoval() {
        guard let pending = pendingConfirm else { return }
        pendingConfirm = nil
        let sizes = pending.sizes, urls = pending.urls

        Task.detached(priority: .userInitiated) {
            let outcome = Remover.moveToTrash(urls, sizes: sizes)
            await MainActor.run {
                self.finish(outcome, sizes: sizes, title: pending.successTitle,
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
        guard let gi = leftovers.firstIndex(where: { $0.id == group.id }),
              let fi = leftovers[gi].files.firstIndex(where: { $0.id == file.id }) else { return }
        leftovers[gi].files[fi].isSelected.toggle()
    }

    func toggleLeftoverGroup(_ group: LeftoverGroup) {
        guard let gi = leftovers.firstIndex(where: { $0.id == group.id }) else { return }
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
            }
        }
    }

    // MARK: - Large files

    func scanLargeFiles() {
        isScanningLargeFiles = true
        let minBytes = threshold.rawValue
        // Changing the threshold restarts the scan, so tag each run and ignore
        // any that finishes after a newer one started.
        largeScanToken &+= 1
        let token = largeScanToken
        Task.detached(priority: .userInitiated) {
            let files = Scanner.largeFiles(minBytes: minBytes)
            await MainActor.run {
                guard self.largeScanToken == token else { return }
                self.largeFiles = files
                self.isScanningLargeFiles = false
                self.didScanLargeFiles = true
            }
        }
    }

    func toggleLargeFile(_ file: LargeFile) {
        guard let i = largeFiles.firstIndex(where: { $0.id == file.id }) else { return }
        largeFiles[i].isSelected.toggle()
    }

    func setAllLargeFiles(selected: Bool) {
        for i in largeFiles.indices { largeFiles[i].isSelected = selected }
    }

    /// Large files are the user's own documents, so removal always goes through
    /// the confirmation sheet and nothing is ticked by default.
    func requestLargeFileRemoval() {
        let files = selectedLargeFiles
        guard !files.isEmpty else { return }
        pendingConfirm = PendingRemoval(
            title: files.count == 1
                ? "Move \"\(files[0].name)\" to the Trash?"
                : "Move \(files.count) files to the Trash?",
            message: "\(files.count) item\(files.count == 1 ? "" : "s") will be moved to the Trash.",
            bytes: files.reduce(0) { $0 + $1.sizeBytes },
            urls: files.map(\.url),
            sizes: Dictionary(files.map { ($0.url, $0.sizeBytes) }, uniquingKeysWith: { a, _ in a }),
            appID: nil,
            successTitle: "Large files removed")
    }

    // MARK: - Shared completion / admin escalation

    private func finish(_ outcome: Remover.Outcome, sizes: [URL: Int64],
                        title: String, removedAppID: InstalledApp.ID?) {
        // Anything now off disk (moved to the Trash, or already gone before we
        // got there) leaves the lists, so the UI never keeps showing a file that
        // isn't there any more.
        prune(outcome.resolved)

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
                               failedCount: outcome.failures.count)

        let elevatable = outcome.elevatable
        if !elevatable.isEmpty {
            // Offer the administrator pass first, and hold the rest back so the
            // user sees a single combined report at the end.
            deferredFailures = outcome.failures.filter { !$0.canElevate }
            adminPrompt = AdminPrompt(urls: elevatable,
                                      bytes: elevatable.reduce(0) { $0 + (sizes[$1] ?? 0) },
                                      sizes: sizes)
        } else {
            report(outcome.failures)
        }
    }

    /// Drops URLs that are no longer on disk from every visible list.
    private func prune(_ gone: Set<URL>) {
        guard !gone.isEmpty else { return }
        relatedFiles.removeAll { gone.contains($0.url) }
        largeFiles.removeAll { gone.contains($0.url) }
        leftovers = leftovers.compactMap { group in
            var group = group
            group.files.removeAll { gone.contains($0.url) }
            return group.files.isEmpty ? nil : group
        }
    }

    /// Shows exactly why each remaining item is still on disk.
    private func report(_ failures: [Remover.Failure]) {
        let all = deferredFailures + failures
        deferredFailures = []
        guard !all.isEmpty else { return }
        failureReport = FailureReport(failures: all)
    }

    func performAdminRemoval() {
        guard let prompt = adminPrompt else { return }
        adminPrompt = nil
        let urls = prompt.urls, sizes = prompt.sizes
        Task.detached(priority: .userInitiated) {
            // removeWithAdmin re-checks the disk, so a cancelled password prompt
            // or a still-blocked path comes back as a failure rather than a
            // silent success.
            let outcome = Remover.removeWithAdmin(urls, sizes: sizes)
            await MainActor.run {
                self.prune(outcome.resolved)
                if !outcome.trashed.isEmpty {
                    self.result = RemovalResult(title: "Removed with administrator rights",
                                                freedBytes: outcome.freedBytes,
                                                removedCount: outcome.trashed.count,
                                                failedCount: outcome.failures.count)
                }
                self.report(outcome.failures)
            }
        }
    }

    /// User declined the administrator prompt. Report those items as skipped,
    /// together with anything else that failed.
    func skipAdminRemoval() {
        guard let prompt = adminPrompt else { return }
        adminPrompt = nil
        report(prompt.urls.map {
            Remover.Failure(url: $0,
                            reason: "Skipped, this item needs an administrator password.",
                            canElevate: false)
        })
    }
}

// MARK: - Small flow value types

/// A removal waiting on the user's confirmation. Used by both the uninstaller
/// and the large-files scan, so it carries plain URLs rather than app-specific
/// values; `appID` is set only when an app bundle is going away.
struct PendingRemoval: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let bytes: Int64
    let urls: [URL]
    let sizes: [URL: Int64]
    let appID: InstalledApp.ID?
    let successTitle: String
}

struct AdminPrompt: Identifiable {
    let id = UUID()
    let urls: [URL]
    let bytes: Int64
    let sizes: [URL: Int64]
}

/// Per-item explanation of everything that stayed on disk.
struct FailureReport: Identifiable {
    let id = UUID()
    let failures: [Remover.Failure]

    var needsFullDiskAccess: Bool {
        failures.contains { $0.reason.contains("Full Disk Access") }
    }
}
