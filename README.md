# DiscStats

A small, native macOS app that scans a folder and shows you where your disk
space is going. Each rectangle in the treemap is a file or folder, sized in
proportion to the space it takes up. Double‑click a folder to drill in,
breadcrumb back up, and move what you don't need straight to the Trash.

Built with SwiftUI for macOS 13 (Ventura) and later.

> Made by [Yuri Ihnatov](https://ihnatov.nl).

---

## Features

- **Squarified treemap** — the classic disk‑usage visualization, rendered
  in a single SwiftUI `Canvas` for speed (no per‑rectangle SwiftUI views).
- **Drill in, drill out** — double‑click a folder to descend, click any
  breadcrumb to jump back, ⌘[ or ⌘↑ to go up.
- **Curated color palette by file type** — videos purple, images teal,
  audio orange, code green, archives brown, PDFs red, etc.
- **Hover and select details** — side panel shows the path, percentage of
  the current folder, and the top 8 children. Status bar at the bottom
  echoes whatever the cursor is over.
- **Move to Trash** — recoverable delete via `FileManager.trashItem`, with
  a confirmation dialog. The treemap recomputes parent sizes in place.
- **Reveal in Finder** for any item.
- **Inode‑level dedup** — APFS firmlinks (e.g. `/Users` and
  `/System/Volumes/Data/Users` point to the same inodes) and hard links
  are counted only once, so totals match Finder's *Get Info*.
- **Cancellable, progress‑reporting scanner** running on a background
  queue. The UI stays responsive on million‑file scans.
- **Keyboard shortcuts:**

  | Shortcut | Action |
  |---|---|
  | ⌘O | Choose folder |
  | ⌘R | Rescan |
  | ⌘[ | Go up one folder |
  | ⌘↑ | Go up one folder |
  | ⌘⌫ | Move selection to Trash |
  | Esc | Clear selection |

---

## Build & run

You need **Xcode 15+** (the project targets macOS 13).

```bash
git clone https://github.com/Ihnatov-yuri/Macos-Disk-Analitycs.git
cd Macos-Disk-Analitycs
open DiscStats.xcodeproj
```

Hit ⌘R in Xcode, or build from the command line:

```bash
xcodebuild -project DiscStats.xcodeproj \
           -scheme DiscStats \
           -configuration Debug build
```

The app is ad‑hoc signed (`CODE_SIGN_IDENTITY = "-"`), so it runs locally
without an Apple Developer account.

---

## A note on macOS permissions

The first time you scan into protected locations (Documents, Desktop,
Downloads, iCloud Drive…) macOS will prompt for permission — click
*Allow*. For deep system scans, grant the app **Full Disk Access** under
*System Settings → Privacy & Security → Full Disk Access*.

The app is unsandboxed by design so it can scan anywhere you allow it.

---

## Project layout

```
DiscStats/
├── DiscStatsApp.swift   – @main, WindowGroup, About window scene,
│                          replaces the standard “About DiscStats” menu
├── ContentView.swift    – Toolbar, breadcrumb, treemap panel, side
│                          panel, status bar, keyboard shortcuts
├── TreemapView.swift    – Canvas‑based squarified treemap + color palette
├── Scanner.swift        – Background recursive scanner, inode dedup,
│                          progress reporting, cancellation
├── FileNode.swift       – Tree node model (URL, size, children, parent,
│                          cached itemCount)
└── AboutView.swift      – About panel UI
```

The squarified treemap algorithm in `TreemapLayout` follows Bruls,
Huijsing & van Wijk (2000) — sort children by size descending, lay out
rows greedily so each rectangle stays as square as possible, then recurse
on the remaining area.

---

## License

See [LICENSE](LICENSE).
