import AppKit

/// Removes files. Everything is moved to the Trash (recoverable) rather than
/// hard-deleted; files we can't touch as the user (mostly `/Library` items
/// owned by root) are collected so the UI can offer a single admin-authorised
/// pass for them.
enum Remover {

    struct Outcome {
        var trashed: [URL] = []
        var freedBytes: Int64 = 0
        /// Items that failed because they need elevated privileges.
        var needsAdmin: [URL] = []
        /// Items that failed for some other reason (already gone, etc.).
        var otherFailures: [URL] = []
    }

    /// Moves each URL to the Trash. `sizes` lets us report freed space without
    /// re-stat-ing items after they've moved.
    static func moveToTrash(_ urls: [URL], sizes: [URL: Int64] = [:]) -> Outcome {
        var outcome = Outcome()
        let fm = FileManager.default
        for url in urls {
            guard fm.fileExists(atPath: url.path) else { continue }
            do {
                try fm.trashItem(at: url, resultingItemURL: nil)
                outcome.trashed.append(url)
                outcome.freedBytes += sizes[url] ?? 0
            } catch let error as NSError {
                if isPermissionError(error) {
                    outcome.needsAdmin.append(url)
                } else {
                    outcome.otherFailures.append(url)
                }
            }
        }
        return outcome
    }

    /// Deletes the given URLs with `rm -rf` under one administrator prompt. Used
    /// only as an explicit, user-initiated fallback for root-owned items that
    /// `trashItem` can't move. Returns true if the script ran without error.
    @discardableResult
    static func removeWithAdmin(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return true }
        // Build a single-quoted, escaped argument list for /bin/rm.
        let args = urls.map { "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            .joined(separator: " ")
        let shell = "/bin/rm -rf \(args)"
        let source = "do shell script \"\(shell.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"

        var errorInfo: NSDictionary?
        let script = NSAppleScript(source: source)
        script?.executeAndReturnError(&errorInfo)
        return errorInfo == nil
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
        // Underlying POSIX EPERM/EACCES.
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain,
           underlying.code == 1 || underlying.code == 13 {
            return true
        }
        return false
    }
}
