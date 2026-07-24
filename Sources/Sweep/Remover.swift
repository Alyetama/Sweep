import AppKit

/// Removes files. Everything is moved to the Trash (recoverable) rather than
/// hard-deleted. Anything we can't move is reported back with a specific reason
/// so the UI can tell the user why an item is still on disk, instead of silently
/// leaving it in the list.
enum Remover {

    /// One item we couldn't remove, with a reason worth showing to a human.
    struct Failure: Identifiable, Hashable {
        var id: URL { url }
        let url: URL
        let reason: String
        /// True when retrying as administrator has a real chance of working.
        let canElevate: Bool

        var displayPath: String { (url.path as NSString).abbreviatingWithTildeInPath }
    }

    struct Outcome {
        var trashed: [URL] = []
        /// Items already gone before we got to them. Not an error, but they still
        /// have to disappear from the UI.
        var vanished: [URL] = []
        var freedBytes: Int64 = 0
        var failures: [Failure] = []

        /// Everything no longer on disk, used to prune the lists.
        var resolved: Set<URL> { Set(trashed).union(vanished) }
        var elevatable: [URL] { failures.filter(\.canElevate).map(\.url) }
    }

    // MARK: - Trash

    /// Moves each URL to the Trash. `sizes` lets us report freed space without
    /// re-stat-ing items after they've moved.
    static func moveToTrash(_ urls: [URL], sizes: [URL: Int64] = [:]) -> Outcome {
        var outcome = Outcome()
        let fm = FileManager.default
        for url in urls {
            guard fm.fileExists(atPath: url.path) else {
                outcome.vanished.append(url)
                continue
            }
            do {
                try fm.trashItem(at: url, resultingItemURL: nil)
                outcome.trashed.append(url)
                outcome.freedBytes += sizes[url] ?? 0
            } catch let error as NSError {
                outcome.failures.append(classify(error, url: url))
            }
        }
        return outcome
    }

    // MARK: - Administrator fallback

    /// Runs `rm -rf` on the given URLs under a single administrator prompt, then
    /// checks the disk to see what actually went away. Anything still present is
    /// returned as a failure with a reason, so a cancelled password prompt or a
    /// privacy-protected path can never be mistaken for success.
    static func removeWithAdmin(_ urls: [URL], sizes: [URL: Int64] = [:]) -> Outcome {
        var outcome = Outcome()
        guard !urls.isEmpty else { return outcome }

        let args = urls
            .map { "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            .joined(separator: " ")
        let shell = "/bin/rm -rf \(args)"
        // Escape backslashes before quotes: AppleScript string literals treat `\`
        // as an escape character, so a path containing one otherwise produces a
        // syntax error and the whole batch fails.
        let escaped = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"

        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        // -128 is "user cancelled" from the authentication dialog.
        let cancelled = (errorInfo?[NSAppleScript.errorNumber] as? Int) == -128

        let fm = FileManager.default
        for url in urls {
            if fm.fileExists(atPath: url.path) {
                outcome.failures.append(Failure(
                    url: url,
                    reason: cancelled
                        ? "Skipped, the administrator prompt was cancelled."
                        : "Still blocked by macOS. Give Sweep Full Disk Access in System Settings > Privacy & Security, then scan again.",
                    canElevate: false))
            } else {
                outcome.trashed.append(url)
                outcome.freedBytes += sizes[url] ?? 0
            }
        }
        return outcome
    }

    // MARK: - Error classification

    private static func classify(_ error: NSError, url: URL) -> Failure {
        if error.domain == NSCocoaErrorDomain, error.code == NSFileWriteVolumeReadOnlyError {
            return Failure(url: url, reason: "This volume is read-only.", canElevate: false)
        }
        if isBusyError(error) {
            return Failure(url: url,
                           reason: "The file is in use. Quit the app that owns it and try again.",
                           canElevate: false)
        }
        if isPermissionError(error) {
            // Inside the home folder, a permission error is almost always macOS
            // privacy protection rather than file ownership, so say so. Root can
            // usually still delete it, so elevating is still worth offering.
            if isInsideHome(url) {
                return Failure(
                    url: url,
                    reason: "macOS privacy protection blocks this folder. Full Disk Access, or an administrator password, will clear it.",
                    canElevate: true)
            }
            return Failure(url: url,
                           reason: "Owned by the system. Needs an administrator password.",
                           canElevate: true)
        }
        return Failure(url: url, reason: error.localizedDescription, canElevate: false)
    }

    private static func isInsideHome(_ url: URL) -> Bool {
        url.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path + "/")
    }

    private static func isPermissionError(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain {
            switch error.code {
            case NSFileWriteNoPermissionError, NSFileWriteVolumeReadOnlyError,
                 NSFileReadNoPermissionError:
                return true
            default: break
            }
        }
        return posixCode(of: error).map { $0 == 1 || $0 == 13 } ?? false
    }

    /// EBUSY / ETXTBSY, the file is open or currently running.
    private static func isBusyError(_ error: NSError) -> Bool {
        posixCode(of: error).map { $0 == 16 || $0 == 26 } ?? false
    }

    private static func posixCode(of error: NSError) -> Int? {
        if error.domain == NSPOSIXErrorDomain { return error.code }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain {
            return underlying.code
        }
        return nil
    }
}
