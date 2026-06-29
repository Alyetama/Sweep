<div align="center">

<img src="docs/icon.png" width="120" height="120" alt="Sweep app icon" />

# Sweep

**A native macOS app uninstaller that removes every trace.**

Dragging an app to the Trash leaves its caches, preferences, containers, logs and
support files scattered across your Mac. Sweep finds them all, shows them to you
pre-selected, and asks before removing anything — and it cleans up leftovers from
apps you've *already* deleted.

[![Download](https://img.shields.io/badge/Download-for%20macOS-4C7CF5?style=for-the-badge&logo=apple)](https://github.com/Alyetama/Sweep/releases/latest/download/Sweep.dmg)
&nbsp;
[![Website](https://img.shields.io/badge/Website-alyetama.github.io%2FSweep-33D4BD?style=for-the-badge)](https://alyetama.github.io/Sweep/)

<br />

<img src="docs/mockup.png" width="820" alt="Sweep showing an app's associated files grouped by category, all pre-selected for removal" />

</div>

## Features

- **Complete uninstall** — pick an app and Sweep finds everything it scattered:
  Application Support, Caches, Preferences, Containers, Group Containers, Saved
  State, Logs, Cookies, Web Data, Login Items & helpers, and Crash Reports.
- **Finds what drag-to-trash misses** — handles vendor-nested, version-suffixed
  folders (e.g. `Application Support/JetBrains/DataSpell2024.2`), with
  boundary-aware matching so `Notion` never sweeps up `NotionCalendar`.
- **Leftovers scanner** — finds orphaned files left behind by apps you've already
  removed, grouped by app and expandable to the file level.
- **Safe by design** — everything is moved to the **Trash** (recoverable), never
  hard-deleted. Search and sort by size, name or last-used.
- **Native & lightweight** — pure SwiftUI, no dependencies, no telemetry.

## Install

1. Download **[Sweep.dmg](https://github.com/Alyetama/Sweep/releases/latest/download/Sweep.dmg)**.
2. Open it and drag **Sweep** into your **Applications** folder.

### Opening it the first time

Sweep is open-source and ad-hoc signed — there's no paid Apple Developer ID — so
macOS Gatekeeper blocks it the first time. You only need to do this **once**:

**Option A — Terminal (quickest)**

```sh
xattr -dr com.apple.quarantine /Applications/Sweep.app
```

Then open Sweep normally from Launchpad or Applications.

**Option B — System Settings**

1. Double-click **Sweep**, then click **Done** on the warning.
2. Open **System Settings → Privacy & Security**.
3. Scroll down and click **Open Anyway** next to *“Sweep was blocked…”*, then **Open**.

> For protected folders (Mail, Messages, Safari…), grant Sweep **Full Disk
> Access** in System Settings → Privacy & Security so it can find and remove those
> files too.

## Build from source

```sh
git clone https://github.com/Alyetama/Sweep.git
cd Sweep
./run.sh          # build (release) + launch
```

Requires the Swift 6 toolchain (Xcode 16+). Built with Swift Package Manager and
ad-hoc code-signed — no Xcode project required.

```
Sources/Sweep/
  App.swift            # @main scene
  Models.swift         # InstalledApp, RelatedFile, FileCategory, LeftoverGroup…
  Scanner.swift        # app discovery, related-file matching, leftovers scan
  Remover.swift        # move-to-Trash + admin-escalation fallback
  AppModel.swift       # @MainActor view model / background-scan glue
  Theme.swift          # brand colors, category glyphs, formatters
  Views/               # ContentView, Sidebar, Uninstaller, AppDetail, Leftovers
```

## License

[MIT](LICENSE) © Alyetama
