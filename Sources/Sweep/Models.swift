import AppKit

// MARK: - File categories

/// The kinds of files an app scatters across the system. Each maps to an SF
/// Symbol + color (see `Theme.swift`) so every category is visually distinct in
/// the file list, matching the grouped look of a dedicated uninstaller.
enum FileCategory: String, CaseIterable, Hashable {
    case binary          = "Application"
    case support         = "Application Support"
    case caches          = "Caches"
    case preferences     = "Preferences"
    case containers      = "Containers"
    case groupContainers = "Group Containers"
    case savedState      = "Saved Application State"
    case logs            = "Logs"
    case cookies         = "Cookies"
    case webData         = "Web Data"
    case launchItems     = "Login Items & Helpers"
    case crashReports    = "Crash Reports"
    case other           = "Other"

    /// Stable display order for grouped sections (the app bundle itself first).
    var order: Int { FileCategory.allCases.firstIndex(of: self) ?? 99 }
}

// MARK: - Installed application

/// An installed `.app` discovered under /Applications, ~/Applications, etc.
struct InstalledApp: Identifiable, Hashable {
    let id: String          // bundle id when available, else the bundle path
    let name: String        // display name (no ".app")
    let bundleID: String?
    let version: String?
    let path: URL           // the .app bundle
    let isSystem: Bool       // Apple / system app — shown but not removable
    var sizeBytes: Int64    // -1 until computed asynchronously
    var lastUsed: Date?     // Spotlight kMDItemLastUsedDate, if known

    var icon: NSImage { NSWorkspace.shared.icon(forFile: path.path) }

    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - A single file/folder associated with an app

struct RelatedFile: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let category: FileCategory
    let sizeBytes: Int64
    var isSelected: Bool

    /// `~`-abbreviated path for compact display.
    var displayPath: String { (url.path as NSString).abbreviatingWithTildeInPath }
}

// MARK: - Leftovers (orphaned files of already-removed apps)

/// A cluster of orphaned files that all belong to the same (uninstalled) app,
/// keyed by the bundle id we recovered from their names.
struct LeftoverGroup: Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let displayName: String
    var files: [RelatedFile]

    var totalSize: Int64 { files.reduce(0) { $0 + $1.sizeBytes } }
    var isFullySelected: Bool { files.allSatisfy(\.isSelected) }
    var selectedSize: Int64 { files.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes } }
}

// MARK: - Sorting

enum AppSort: String, CaseIterable, Identifiable {
    case size = "Size"
    case name = "Name"
    case lastUsed = "Last Used"
    var id: String { rawValue }
}

// MARK: - Removal outcome

/// Summary shown to the user after a removal pass.
struct RemovalResult: Identifiable {
    let id = UUID()
    let title: String            // e.g. "Slack was removed"
    let freedBytes: Int64
    let removedCount: Int
    let failedCount: Int
}
