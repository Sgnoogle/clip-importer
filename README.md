# Clip Importer

A tiny macOS menu-bar app that imports videos and photos from Sony camera SD cards — a modern, free replacement for the old Sony PlayMemories Home.

Insert the card and the window opens by itself, showing your clips and photos ready to import.

🇮🇹 **[Leggimi in italiano](LEGGIMI.md)** (the app's interface is in Italian).

## Features

- **Sony XAVC S / HS / S-I** clips (`PRIVATE/M4ROOT`) with instant thumbnails, duration, resolution and frame rate from Sony's XML metadata; **AVCHD** (`.MTS`); MP4/MOV in `DCIM`; or any folder you pick.
- **Photos**: JPEG, HEIF (`.HIF`) and RAW (`.ARW` and other brands). RAW + JPEG pairs are shown as one item and imported together.
- **Show everything, videos only or photos only.**
- Click to select, click again to deselect. **Hover-scrub** through a clip, **Space** for Quick Look, double-click to play.
- **Lightroom-style flags** as bookmark ribbons (hover a thumbnail and click the empty ribbon to pick, ⌥-click to reject, or use the keys): `P` pick, `X` reject, `U` unflag, `←` `→` to move. Rejected items are never imported; if there are picks, the button imports only the picks.
- **Copy or move**: "Move" copies each file, re-reads it from the destination and compares SHA-256 hashes, and only then deletes it from the card — together with its XML, thumbnail, proxy and its entry in Sony's `MEDIAPRO.XML` index, so the camera stays happy.
- Organize by shoot day, import day, a custom folder, or flat. Optionally copy Sony XML sidecars and proxies (in a `Proxy` folder that DaVinci Resolve links automatically).
- Remembers what was already imported; skips identical files; safe copies through temporary files.
- Finder-style shortcuts: `⌘C` (then `⌘V` / `⌥⌘V` in Finder), `⌘⌫` delete, `⌘I` import, `⌥⌘I` import & delete from card, `⌘R` refresh, `⌘O` open folder.
- Lives in the menu bar, can start at login, opens automatically when a card is inserted.

Requires macOS 13 Ventura or later (Apple silicon or Intel).

## Download & install

### ⬇️ [Download Clip Importer (ZIP)](https://github.com/Sgnoogle/clip-importer/releases/latest/download/ClipImporter.zip)

macOS 13 Ventura or later · Apple silicon and Intel · free and open source.

### Option A — the usual way

1. Click the link above, then double-click `ClipImporter.zip` in Downloads to unzip it.
2. Drag **Clip Importer** into your **Applications** folder.
3. Double-click it. **macOS will block it the first time** (see below) — that's expected.

**Why does macOS block it?** Apple only lets apps open without warnings if the developer pays for an Apple Developer account and has the app "notarized". Clip Importer is a free hobby project and isn't, so macOS says it *"cannot verify that it is free of malware"*. The full source code is right here for anyone to read. To allow it, once:

1. Open **System Settings › Privacy & Security**.
2. Scroll down: you'll see *"Clip Importer" was blocked…*. Click **Open Anyway** and confirm with your password or Touch ID.

(On macOS 14 and earlier you can also right-click the app › **Open** › **Open**.)

### Option B — one command, no warnings

Open **Terminal** (Applications › Utilities), paste this and press Return:

```sh
curl -fsSL https://raw.githubusercontent.com/Sgnoogle/clip-importer/main/install.sh | bash
```

It downloads the latest release, installs it in Applications and opens it. Run it again any time to update. ([See what the script does](install.sh).)

### Permissions it will ask for

| When | macOS asks | Answer |
|---|---|---|
| First card inserted | *"Clip Importer" would like to access files on a removable volume* | **Allow** — it needs to read the SD card |
| First import into a folder like Movies/Documents | Access to that folder | **Allow** |
| If you choose to start at login | A notice in Login Items | Nothing to do (it can be turned off in the app's settings) |

If you clicked "Don't Allow" by mistake: **System Settings › Privacy & Security › Files and Folders › Clip Importer** and turn on *Removable Volumes*.

## Build from source

No Xcode project needed — just the Command Line Tools:

```sh
git clone https://github.com/Sgnoogle/clip-importer.git
cd clip-importer
bash build.sh       # builds, installs to /Applications and launches
bash pacchetto.sh   # builds a universal (arm64 + x86_64) zip in ~/Downloads (the release asset)
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
