# Clip Importer

A tiny macOS menu-bar app that imports videos and photos from Sony camera SD cards — a modern, free replacement for the old Sony PlayMemories Home.

Insert the card and the window opens by itself, showing your clips and photos ready to import.

🇮🇹 **[Leggimi in italiano](LEGGIMI.md)** (the app's interface is in Italian).

## Features

- **Sony XAVC S / HS / S-I** clips (`PRIVATE/M4ROOT`) with instant thumbnails, duration, resolution and frame rate from Sony's XML metadata; **AVCHD** (`.MTS`); MP4/MOV in `DCIM`; or any folder you pick.
- **Photos**: JPEG, HEIF (`.HIF`) and RAW (`.ARW` and other brands). RAW + JPEG pairs are shown as one item and imported together.
- **Show everything, videos only or photos only.**
- **Hover-scrub** through a clip, **Space** for Quick Look, double-click to play.
- **Lightroom-style flags**: `P` pick, `X` reject, `U` unflag, `←` `→` to move. Rejected items are never imported; if there are picks, the button imports only the picks.
- **Copy or move**: "Move" copies each file, re-reads it from the destination and compares SHA-256 hashes, and only then deletes it from the card — together with its XML, thumbnail, proxy and its entry in Sony's `MEDIAPRO.XML` index, so the camera stays happy.
- Organize by shoot day, import day, a custom folder, or flat. Optionally copy Sony XML sidecars and proxies (in a `Proxy` folder that DaVinci Resolve links automatically).
- Remembers what was already imported; skips identical files; safe copies through temporary files.
- Finder-style shortcuts: `⌘C` (then `⌘V` / `⌥⌘V` in Finder), `⌘⌫` delete, `⌘I` import, `⌥⌘I` import & delete from card, `⌘R` refresh, `⌘O` open folder.
- Lives in the menu bar, can start at login, opens automatically when a card is inserted.

Requires macOS 13 Ventura or later (Apple silicon or Intel).

## Download

Grab `ClipImporter.zip` from the [latest release](../../releases/latest), unzip it and drag **Clip Importer** to Applications.

The app is not signed by Apple, so the first time macOS will block it: open **System Settings › Privacy & Security** and click **Open Anyway**, or run:

```sh
xattr -dr com.apple.quarantine "/Applications/Clip Importer.app"
```

## Build from source

No Xcode project needed — just the Command Line Tools:

```sh
git clone https://github.com/Sgnoogle/clip-importer.git
cd clip-importer
bash build.sh       # builds, installs to /Applications and launches
bash pacchetto.sh   # builds a universal (arm64 + x86_64) zip in ~/Downloads
```

The code is plain SwiftUI/AppKit in `Sources/`:

| File | What it does |
|---|---|
| `AppDelegate.swift` | Menu bar item, main menu, window, keyboard shortcuts, Quick Look |
| `AppState.swift` | App state: sources, selection, flags, import, delete |
| `CardScanner.swift` | Detects camera cards, lists clips/photos, reads Sony XML and EXIF |
| `Importer.swift` | Copy with progress, verification, deletion, Sony index update |
| `Views.swift` | The SwiftUI interface |
| `Models.swift`, `FolderWatcher.swift` | Data types, formatting, FSEvents folder watching |

## License

[MIT](LICENSE) — do whatever you want with it.

Not affiliated with or endorsed by Sony. "Sony", "XAVC" and "PlayMemories" are trademarks of their respective owners.
