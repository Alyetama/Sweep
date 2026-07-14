import AppKit

// All filesystem discovery lives here. Everything is `nonisolated`/static so it
// can run on a background queue and publish results back to the @MainActor model.

// MARK: - Well-known locations

enum Locations {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Directories scanned for *removable* (third-party) apps.
    static var appDirs: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            home.appendingPathComponent("Applications"),
        ]
    }

    /// Apple / system apps — listed so we can recognise them (and so their
    /// support files are never mistaken for "leftovers"), but not offered for
    /// removal.
    static var systemAppDirs: [URL] {
        [
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Library/CoreServices"),
        ]
    }

    static var userLibrary: URL { home.appendingPathComponent("Library") }
    static let systemLibrary = URL(fileURLWithPath: "/Library")
}

// MARK: - Disk size

/// Allocated size of a file or (recursively) a directory, in bytes.
func diskSize(of url: URL) -> Int64 {
    let fm = FileManager.default
    let keys: Set<URLResourceKey> = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
    guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }

    if values.isDirectory != true {
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }

    var total: Int64 = 0
    if let en = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys),
                              options: [], errorHandler: { _, _ in true }) {
        for case let child as URL in en {
            let v = try? child.resourceValues(forKeys: keys)
            total += Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
    }
    return total
}

// MARK: - Scanner

enum Scanner {

    // MARK: Installed apps

    /// Lists installed third-party apps (metadata only; `sizeBytes` is left at
    /// -1 for the caller to fill in asynchronously).
    static func installedApps() -> [InstalledApp] {
        var byID = Set<String>()
        var byPath = Set<String>()
        var result: [InstalledApp] = []

        func consider(_ url: URL) {
            guard byPath.insert(url.standardizedFileURL.path).inserted,
                  let app = makeApp(url: url, isSystem: false),
                  byID.insert(app.id).inserted else { return }
            result.append(app)
        }

        // Fast, predictable pass over the common app folders…
        for dir in Locations.appDirs {
            for url in appBundles(in: dir) { consider(url) }
        }
        // …then Spotlight, to catch third-party apps living in sub-folders
        // (Adobe, Setapp, JetBrains Toolbox, etc.) the shallow scan would miss.
        for url in spotlightAppBundles() where !isSystemPath(url.path) {
            consider(url)
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Every bundle id with an installed owner — used to decide whether a support
    /// file is truly orphaned. Over-inclusive on purpose: a *missed* app here
    /// gets its files mislabelled as leftovers (and offered for deletion), so we
    /// cast the widest net — folder scan + Spotlight, third-party + Apple apps.
    static func allBundleIDs() -> Set<String> {
        var ids = Set<String>()
        for dir in Locations.appDirs + Locations.systemAppDirs {
            for url in appBundles(in: dir) {
                if let bid = Bundle(url: url)?.bundleIdentifier { ids.insert(bid.lowercased()) }
            }
        }
        for url in spotlightAppBundles() {
            if let bid = Bundle(url: url)?.bundleIdentifier { ids.insert(bid.lowercased()) }
        }
        return ids
    }

    private static func appBundles(in dir: URL) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return entries.filter { $0.pathExtension == "app" }
    }

    /// Every app bundle Spotlight knows about, excluding helper apps nested
    /// inside other bundles/frameworks (paths containing ".app/").
    private static func spotlightAppBundles() -> [URL] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        p.arguments = ["kMDItemContentTypeTree == 'com.apple.application-bundle'"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n").map(String.init)
            .filter { $0.hasSuffix(".app") && !$0.contains(".app/") }
            .map { URL(fileURLWithPath: $0) }
    }

    private static func isSystemPath(_ path: String) -> Bool {
        path.hasPrefix("/System/") || path.hasPrefix("/Library/") || path.hasPrefix("/usr/")
    }

    private static func makeApp(url: URL, isSystem: Bool) -> InstalledApp? {
        guard url.pathExtension == "app", let bundle = Bundle(url: url) else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let bundleID = bundle.bundleIdentifier
        let version = (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String)
        return InstalledApp(
            id: bundleID ?? url.path, name: name, bundleID: bundleID, version: version,
            path: url, isSystem: isSystem, sizeBytes: -1, lastUsed: lastUsedDate(for: url))
    }

    /// Spotlight's last-used date for an app bundle (no special permission needed
    /// for items the user can read). Powers the "unused for N months" hint.
    private static func lastUsedDate(for url: URL) -> Date? {
        guard let item = MDItemCreate(nil, url.path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    // MARK: Files related to one app

    /// Finds every support file we can confidently attribute to `app`, ready to
    /// be presented (pre-selected) for removal. The `.app` bundle itself is added
    /// by the caller.
    static func relatedFiles(bundleID: String?, appName: String) -> [RelatedFile] {
        var urls: [(URL, FileCategory)] = []
        let bid = bundleID?.lowercased()

        for root in [Locations.userLibrary, Locations.systemLibrary] {
            // Folders keyed by either the bundle id or the app's display name. These
            // are scanned `deep` so vendor-nested layouts (e.g. the gigabytes a
            // JetBrains IDE leaves in Application Support/JetBrains/DataSpell2024.2)
            // are found, not just top-level folders.
            collectChildren(in: root.appendingPathComponent("Application Support"),
                            bundleID: bid, appName: appName, deep: true, into: &urls, as: .support)
            collectChildren(in: root.appendingPathComponent("Caches"),
                            bundleID: bid, appName: appName, deep: true, into: &urls, as: .caches)
            collectChildren(in: root.appendingPathComponent("Logs"),
                            bundleID: bid, appName: appName, deep: true, into: &urls, as: .logs)

            // Folders keyed strictly by the bundle id (never nested).
            collectChildren(in: root.appendingPathComponent("Containers"),
                            bundleID: bid, appName: nil, deep: false, into: &urls, as: .containers)
            collectChildren(in: root.appendingPathComponent("Application Scripts"),
                            bundleID: bid, appName: nil, deep: false, into: &urls, as: .containers)
            collectChildren(in: root.appendingPathComponent("HTTPStorages"),
                            bundleID: bid, appName: nil, deep: false, into: &urls, as: .webData)
            collectChildren(in: root.appendingPathComponent("WebKit"),
                            bundleID: bid, appName: nil, deep: false, into: &urls, as: .webData)

            // Folders whose names merely *contain* the bundle id (team-id or
            // "group." prefixed).
            collectContaining(bid, in: root.appendingPathComponent("Group Containers"),
                              into: &urls, as: .groupContainers)
            collectContaining(bid, in: root.appendingPathComponent("LaunchAgents"),
                              into: &urls, as: .launchItems)

            // Single files named after the bundle id.
            if let bid {
                addIfExists(root.appendingPathComponent("Preferences/\(bid).plist"), .preferences, &urls)
                addGlob(in: root.appendingPathComponent("Preferences"),
                        prefix: "\(bid).", suffix: ".plist", into: &urls, as: .preferences)
                addIfExists(root.appendingPathComponent("Saved Application State/\(bid).savedState"),
                            .savedState, &urls)
                addIfExists(root.appendingPathComponent("Cookies/\(bid).binarycookies"),
                            .cookies, &urls)
            }
        }

        // Privileged helpers / daemons (system locations).
        collectContaining(bid, in: URL(fileURLWithPath: "/Library/LaunchDaemons"),
                          into: &urls, as: .launchItems)
        collectContaining(bid, in: URL(fileURLWithPath: "/Library/PrivilegedHelperTools"),
                          into: &urls, as: .launchItems)

        // Crash logs: <AppName or BundleID>_*.ips
        addGlob(in: Locations.userLibrary.appendingPathComponent("Logs/DiagnosticReports"),
                prefix: "\(appName)-", suffix: nil, into: &urls, as: .crashReports)
        addGlob(in: Locations.userLibrary.appendingPathComponent("Logs/DiagnosticReports"),
                prefix: "\(appName)_", suffix: nil, into: &urls, as: .crashReports)

        return materialize(urls)
    }

    // MARK: Leftovers

    /// Scans Library folders for bundle-id-shaped items whose owning app is no
    /// longer installed, grouped by recovered bundle id.
    static func leftovers(installed: Set<String>) -> [LeftoverGroup] {
        var groups: [String: [RelatedFile]] = [:]

        func consider(_ url: URL, bundleIDCandidate raw: String, _ category: FileCategory) {
            let bid = raw.lowercased()
            guard isBundleIDShaped(bid), !isSystemID(bid), !isOwned(bid, by: installed) else { return }
            let file = RelatedFile(url: url, category: category,
                                   sizeBytes: diskSize(of: url), isSelected: true)
            groups[bid, default: []].append(file)
        }

        for root in [Locations.userLibrary, Locations.systemLibrary] {
            scanDir(root.appendingPathComponent("Caches"))        { consider($0, bundleIDCandidate: $1, .caches) }
            scanDir(root.appendingPathComponent("Containers"))    { consider($0, bundleIDCandidate: $1, .containers) }
            scanDir(root.appendingPathComponent("Application Scripts")) { consider($0, bundleIDCandidate: $1, .containers) }
            scanDir(root.appendingPathComponent("HTTPStorages"))  { consider($0, bundleIDCandidate: $1, .webData) }
            scanDir(root.appendingPathComponent("WebKit"))        { consider($0, bundleIDCandidate: $1, .webData) }
            scanDir(root.appendingPathComponent("Application Support")) { consider($0, bundleIDCandidate: $1, .support) }
            // *.plist → strip extension; *.savedState → strip extension.
            scanDir(root.appendingPathComponent("Preferences")) { url, name in
                guard name.hasSuffix(".plist") else { return }
                consider(url, bundleIDCandidate: String(name.dropLast(6)), .preferences)
            }
            scanDir(root.appendingPathComponent("Saved Application State")) { url, name in
                guard name.hasSuffix(".savedState") else { return }
                consider(url, bundleIDCandidate: String(name.dropLast(10)), .savedState)
            }
        }

        return groups.map { LeftoverGroup(bundleID: $0.key,
                                          displayName: prettyName(for: $0.key),
                                          files: $0.value.sorted { $0.sizeBytes > $1.sizeBytes }) }
            .sorted { $0.totalSize > $1.totalSize }
    }

    // MARK: - Matching helpers

    /// A child folder "belongs" to an app if its name matches the bundle id or the
    /// app's display name (see `bundleMatches` / `nameMatches`). When `deep` is set
    /// and a top-level child doesn't itself match, we look one level inside it so
    /// vendor-grouped folders (Vendor/AppName) are still attributed — but only the
    /// matching sub-folder is taken, never the whole vendor folder.
    private static func collectChildren(in dir: URL, bundleID bid: String?, appName name: String?,
                                        deep: Bool, into out: inout [(URL, FileCategory)],
                                        as category: FileCategory) {
        scanDir(dir) { url, child in
            if bundleMatches(child, bid) || nameMatches(child, name) {
                out.append((url, category)); return
            }
            guard deep,
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { return }
            scanDir(url) { sub, subName in
                if bundleMatches(subName, bid) || nameMatches(subName, name) {
                    out.append((sub, category))
                }
            }
        }
    }

    /// Folder name == bundle id, or starts with `bundleID.` (helper sub-domains).
    private static func bundleMatches(_ name: String, _ bid: String?) -> Bool {
        guard let bid, !bid.isEmpty else { return false }
        let n = name.lowercased()
        return n == bid || n.hasPrefix(bid + ".")
    }

    /// Folder name == app name, or `app name` followed by a non-letter boundary —
    /// so "DataSpell" matches "DataSpell2024.2" but "Notion" never matches
    /// "NotionCalendar". The prefix rule only applies to names ≥ 5 chars to keep
    /// short, generic names from over-matching.
    private static func nameMatches(_ name: String, _ appName: String?) -> Bool {
        guard let appName else { return false }
        let n = name.lowercased(), a = appName.lowercased()
        if n == a { return true }
        guard a.count >= 5, n.hasPrefix(a) else { return false }
        let next = n[n.index(n.startIndex, offsetBy: a.count)]
        return !next.isLetter
    }

    private static func collectContaining(_ bid: String?, in dir: URL,
                                          into out: inout [(URL, FileCategory)],
                                          as category: FileCategory) {
        guard let bid, !bid.isEmpty else { return }
        scanDir(dir) { url, child in
            if containsBounded(child.lowercased(), bid) { out.append((url, category)) }
        }
    }

    /// True if `bid` appears in `name` as a whole dot-delimited token run — i.e.
    /// bounded by the string edges or non-alphanumeric characters. Stops
    /// `com.foo.bar` from matching `com.foo.bar2` or `group.com.foo.bard`.
    private static func containsBounded(_ name: String, _ bid: String) -> Bool {
        var from = name.startIndex
        while let r = name.range(of: bid, range: from..<name.endIndex) {
            let beforeOK = r.lowerBound == name.startIndex
                || !name[name.index(before: r.lowerBound)].isBundleWordChar
            let afterOK = r.upperBound == name.endIndex
                || !name[r.upperBound].isBundleWordChar
            if beforeOK && afterOK { return true }
            from = name.index(after: r.lowerBound)
        }
        return false
    }

    private static func addGlob(in dir: URL, prefix: String, suffix: String?,
                                into out: inout [(URL, FileCategory)], as category: FileCategory) {
        scanDir(dir) { url, child in
            if child.hasPrefix(prefix), suffix == nil || child.hasSuffix(suffix!) {
                out.append((url, category))
            }
        }
    }

    private static func addIfExists(_ url: URL, _ category: FileCategory,
                                    _ out: inout [(URL, FileCategory)]) {
        if FileManager.default.fileExists(atPath: url.path) { out.append((url, category)) }
    }

    /// Enumerates the immediate children of `dir`, calling `body(url, name)`.
    private static func scanDir(_ dir: URL, _ body: (URL, String) -> Void) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: []) else { return }
        for url in entries { body(url, url.lastPathComponent) }
    }

    /// De-duplicates by URL and turns paths into sized, pre-selected `RelatedFile`s.
    private static func materialize(_ items: [(URL, FileCategory)]) -> [RelatedFile] {
        var seen = Set<URL>()
        var files: [RelatedFile] = []
        for (url, category) in items where seen.insert(url.standardizedFileURL).inserted {
            files.append(RelatedFile(url: url, category: category,
                                     sizeBytes: diskSize(of: url), isSelected: true))
        }
        return files
    }

    // MARK: Bundle-id classification

    /// Reverse-DNS shape: at least two dots, only sane characters. Keeps the
    /// leftovers scan from flagging plain vendor folders like "Google".
    private static func isBundleIDShaped(_ s: String) -> Bool {
        let parts = s.split(separator: ".")
        guard parts.count >= 3 else { return false }
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyz0123456789-_")
        return s.unicodeScalars.allSatisfy { allowed.contains($0) || $0 == "." }
    }

    /// Apple / OS-owned ids that are never user-app leftovers.
    private static func isSystemID(_ s: String) -> Bool {
        for p in ["com.apple.", "group.com.apple.", "apple.", "com.macromates.",
                  "systemgroup.", "iconservices", "metadata", "com.crashlytics"] where s.hasPrefix(p) {
            return true
        }
        return false
    }

    /// True if any installed app's id is the same as, an ancestor of, or a
    /// descendant of the candidate — so helpers/frameworks of installed apps
    /// (e.g. `com.google.Chrome.framework`) are not treated as orphaned.
    private static func isOwned(_ bid: String, by installed: Set<String>) -> Bool {
        if installed.contains(bid) { return true }
        for id in installed where bid.hasPrefix(id + ".") || id.hasPrefix(bid + ".") {
            return true
        }
        return false
    }

    /// Best-effort human name from a bundle id, e.g. "com.tinyspeck.slackmacgap"
    /// → "Slackmacgap". The last component is usually the most recognisable.
    private static func prettyName(for bid: String) -> String {
        let last = bid.split(separator: ".").last.map(String.init) ?? bid
        return last.prefix(1).uppercased() + last.dropFirst()
    }
}

private extension Character {
    /// A character that keeps a bundle-id token "word" going (letter or digit);
    /// dots, dashes and underscores are treated as token boundaries.
    var isBundleWordChar: Bool { isLetter || isNumber }
}
