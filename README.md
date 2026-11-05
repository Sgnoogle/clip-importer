<div align="center">

<img src="docs/icon.png" width="128" alt="Clip Importer icon">

# Clip Importer

### Import videos & photos from your Sony camera on Mac and Windows. The free, open-source PlayMemories Home alternative.

Insert the SD card. The window opens by itself. Pick your clips, click Import. Done.

[![Download for Mac](https://img.shields.io/badge/Download-for%20Mac-0A84FF?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/Sgnoogle/clip-importer/releases/latest/download/ClipImporter.zip)
[![Download for Windows](https://img.shields.io/badge/Download-for%20Windows-0078D4?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/Sgnoogle/clip-importer/releases/latest/download/ClipImporter-Windows-x64.zip)

[![macOS 13+](https://img.shields.io/badge/macOS-13%20Ventura%2B-black?logo=apple)](#download--install)
[![Windows 10/11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?logo=windows)](#windows)
[![Apple silicon & Intel](https://img.shields.io/badge/Apple%20silicon%20%26%20Intel-universal-555)](#download--install)
[![Latest release](https://img.shields.io/github/v/release/Sgnoogle/clip-importer?label=release)](https://github.com/Sgnoogle/clip-importer/releases/latest)
[![MIT License](https://img.shields.io/github/license/Sgnoogle/clip-importer)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white)](Sources)

🌍 English · Italiano · Español · Français · Deutsch · Português · Русский · 日本語 · 한국어 · 简体中文

<br>

<img src="docs/screenshot.png" alt="Clip Importer showing clips and photos from a Sony SD card, with pick and reject flags" width="100%">

</div>

<br>

## Why

If you shoot with a Sony camera, you've probably looked for **PlayMemories Home for Mac** (or a lighter PlayMemories for Windows): a simple way to see what's on the card and copy it to your computer, organized by date. Clip Importer is exactly that, rebuilt from scratch as a tiny, fast, native app for macOS and Windows:

- no account, no catalog, no library to manage. Just your files, copied where you want them;
- it understands Sony's card structure (`PRIVATE/M4ROOT`, XAVC S / HS / S-I, AVCHD, `DCIM`), so you see real clips instead of a maze of folders, XML and thumbnail files;
- it lives quietly in the menu bar (Mac) or notification area (Windows) and pops up when you insert a card.

## Features

| | |
|---|---|
| 🎬 **Sony video** | XAVC S, XAVC HS, XAVC S-I (`.MP4` in `PRIVATE/M4ROOT/CLIP`) with instant thumbnails, duration, resolution and frame rate read from Sony's XML metadata. AVCHD (`.MTS`) too. |
| 📷 **Photos** | JPEG, HEIF (`.HIF`) and RAW (`.ARW`, plus other brands' RAW). **RAW + JPEG pairs appear as one item** and are imported together with matching names. |
| 🗂 **Show what you need** | All · Videos · Photos. Grouped by shooting day, sortable by name, duration or size. |
| 👀 **Preview** | Hover over a clip to scrub through it, press **Space** for Quick Look, double-click to play. |
| 🔖 **Flags, Lightroom-style** | Hover a thumbnail and click the bookmark to **pick** it (⌥-click to **reject**), or use `P` / `X` / `U` and `←` `→`. Rejected items are never imported; if you picked some, the button imports only the picks. |
| ✂️ **Copy or move** | "Move" copies each file, **re-reads it from the destination and compares SHA-256 hashes**, and only then deletes it from the card, together with its XML, thumbnail, proxy and its entry in Sony's `MEDIAPRO.XML` index, so the camera doesn't complain. |
| 📁 **Organize** | One folder per shooting day, today's date, a custom name, or everything together. Optionally add date and time to file names. |
| 🎞 **Editor-friendly** | Optionally copy Sony XML sidecars and **proxies** into a `Proxy` folder that DaVinci Resolve links automatically. Drag clips straight into Finder or your timeline. |
| 🛡 **Safe** | Copies go through temporary files (an unplugged card never leaves half files), identical files are skipped, already-imported clips are remembered and marked. |
| ⌨️ **Mac shortcuts** | `⌘C` then `⌘V`/`⌥⌘V` in Finder, `⌘⌫` delete, `⌘I` import, `⌥⌘I` import & delete from card, `⌘R` refresh, `⌘O` open folder, `⌘E` eject. |
| 🌍 **10 languages** | English, Italian, Spanish, French, German, Portuguese, Russian, Japanese, Korean and Simplified Chinese, picked automatically from your system language. Translations live in one file, [`Resources/strings.json`](Resources/strings.json): fixes and new languages are welcome. |
| 🪶 **Lightweight** | Native app (SwiftUI on Mac, WPF on Windows), no dependencies to install, no tracking, no network access. |

## Download & install

> On Windows? Jump to [Windows](#windows).

### ⬇️ [Download Clip Importer (ZIP)](https://github.com/Sgnoogle/clip-importer/releases/latest/download/ClipImporter.zip)

macOS 13 Ventura or later · Apple silicon and Intel · free and open source.

### Option A: the usual way

1. Click the link above, then double-click `ClipImporter.zip` in Downloads to unzip it.
2. Drag **Clip Importer** into your **Applications** folder.
3. Double-click it. **macOS will block it the first time** (see below). That's expected.

**Why does macOS block it?** Apple only lets apps open without warnings if the developer pays for an Apple Developer account and has the app "notarized". Clip Importer is a free hobby project and isn't, so macOS says it *"cannot verify that it is free of malware"*. The full source code is right here for anyone to read. To allow it, once:

1. Open **System Settings › Privacy & Security**.
2. Scroll down: you'll see *"Clip Importer" was blocked…*. Click **Open Anyway** and confirm with your password or Touch ID.

(On macOS 14 and earlier you can also right-click the app › **Open** › **Open**.)

### Option B: one command, no warnings

Open **Terminal** (Applications › Utilities), paste this and press Return:

```sh
curl -fsSL https://raw.githubusercontent.com/Sgnoogle/clip-importer/main/install.sh | bash
```

It downloads the latest release, installs it in Applications and opens it. Run it again any time to update. ([See what the script does](install.sh).)

### Permissions it will ask for

| When | macOS asks | Answer |
|---|---|---|
| First card inserted | *"Clip Importer" would like to access files on a removable volume* | **Allow** (it needs to read the SD card) |
| First import into a folder like Movies or Documents | Access to that folder | **Allow** |
| If "start at login" is on | A notice about Login Items | Nothing to do (turn it off in the app's settings if you like) |

Clicked "Don't Allow" by mistake? **System Settings › Privacy & Security › Files and Folders › Clip Importer** → turn on *Removable Volumes*.

## Windows

### ⬇️ [Download for Windows (x64)](https://github.com/Sgnoogle/clip-importer/releases/latest/download/ClipImporter-Windows-x64.zip) · [ARM64](https://github.com/Sgnoogle/clip-importer/releases/latest/download/ClipImporter-Windows-arm64.zip)

Windows 10 (1809 or later) or Windows 11. Most PCs need **x64**; pick ARM64 only for Snapdragon/Copilot+ laptops. Nothing to install: it's a single `ClipImporter.exe`.

1. Unzip the file and put the **Clip Importer** folder wherever you like (for example in `Documents`).
2. Double-click `ClipImporter.exe`.
3. **Windows SmartScreen will warn you the first time**, because the app isn't signed with a paid certificate. Click **More info**, then **Run anyway**.

The Windows version has the same features and the same 10 languages as the Mac one. It lives in the notification area (next to the clock), opens by itself when you insert a card and can start with Windows. Windows-style shortcuts: `Ctrl+C` (then paste in File Explorer), `Del` delete, `Ctrl+I` import, `Ctrl+Alt+I` import & delete from card, `F5` refresh, `Ctrl+O` open folder, `Ctrl+E` eject, `Space` preview, `P` / `X` / `U` flags. Hold `Alt` to turn Import into Move.

Optional, from the Microsoft Store: **HEVC Video Extensions** (to preview XAVC HS / H.265 clips) and **Raw Image Extension** (for RAW thumbnails).

Differences from the Mac version: no hover-scrubbing inside clips yet (Space opens the preview instead), and it's newer, so it has been tested on Windows build servers but less on real PCs with real cards. Feedback is very welcome in the [issues](https://github.com/Sgnoogle/clip-importer/issues).

## Compatibility

Clip Importer reads the standard folder structure Sony cameras write to the card, so it should work with any Sony camera that records **XAVC S / XAVC HS / XAVC S-I** or **AVCHD** video, and with JPEG / HEIF / RAW photos in `DCIM`. That includes Alpha mirrorless (a6000-series, a7 / a7S / a7R / a9 / a1), ZV-series vlog cameras, FX cinema line, RX compacts and Handycam camcorders.

Tested so far with a **Sony α5100**. If you try it with another model, please [open an issue](https://github.com/Sgnoogle/clip-importer/issues) and say whether it worked. It helps others.

Any folder works too ("Browse a folder…", `⌘O`), including cards from other brands with MP4/MOV in `DCIM`.

## FAQ

**Is there a PlayMemories Home for Mac that works on recent macOS?**
Clip Importer covers what most people used PlayMemories Home for: seeing what's on the card and importing videos and photos into dated folders. It runs natively on macOS 13 Ventura through the latest macOS, on Apple silicon and Intel.

**How do I import XAVC S videos from a Sony camera to a Mac?**
Insert the SD card (or connect the camera in mass-storage mode), and Clip Importer shows the clips from `PRIVATE/M4ROOT/CLIP` with thumbnails and duration. Click **Import**. The `.MP4` files land in `~/Movies/Sony/<date>` (you can change both).

**Why do my Sony videos appear inside a "PRIVATE" folder in Finder?**
That's how XAVC S cards are organized: each clip has an `.MP4`, an XML metadata file, a thumbnail and sometimes a proxy in separate folders. Clip Importer puts them back together as a single clip.

**Can it delete clips from the SD card after importing?**
Yes. Tick "Delete from card after copying", hold ⌥ on the Import button, or press `⌥⌘I`. Each file is verified byte-for-byte before it's deleted.

**What about Sony's official software?**
Sony's current desktop apps are part of [Imaging Edge](https://imagingedge.sony.net/en/ie-desktop.html), which is great for RAW development and tethered shooting. Clip Importer is a much smaller tool focused only on getting clips and photos off the card quickly.

**Does it upload anything or need an account?**
No. It never connects to the internet. Everything stays on your Mac.

## Build from source

**Mac.** No Xcode project needed, just the Command Line Tools (`xcode-select --install`):

```sh
git clone https://github.com/Sgnoogle/clip-importer.git
cd clip-importer
bash build.sh       # builds, installs to /Applications and launches
bash pacchetto.sh   # builds the universal (arm64 + x86_64) release zip in ~/Downloads
```

The code is plain SwiftUI/AppKit in [`Sources/`](Sources):

| File | What it does |
|---|---|
| `AppDelegate.swift` | Menu bar item, main menu, window, keyboard shortcuts, Quick Look |
| `AppState.swift` | App state: sources, selection, flags, import, delete |
| `CardScanner.swift` | Detects camera cards, lists clips/photos, reads Sony XML and EXIF |
| `Importer.swift` | Copy with progress, verification, deletion, Sony index update |
| `Views.swift` | The SwiftUI interface |
| `Models.swift`, `FolderWatcher.swift` | Data types, formatting, FSEvents folder watching |
| `Lang.swift` | Language detection and the `L()` translation function |

**Windows.** C# / WPF on .NET 8, in [`windows/`](windows):

```sh
dotnet build windows/ClipImporter/ClipImporter.csproj
ClipImporter.exe --selftest %TEMP%\ci-test   # builds a fake Sony card and checks scan, import, verified move
```

Every push is built and tested on GitHub's Windows servers ([workflow](.github/workflows/windows.yml)), and tagged releases get the Windows zips attached automatically. Both apps share the translations in [`Resources/strings.json`](Resources/strings.json); Windows-only wording lives in [`windows/strings.windows.json`](windows/strings.windows.json).

Issues and pull requests are welcome.

## Credits

I can't write a single line of code. This whole app was built by [Claude](https://claude.ai) (Anthropic), one conversation at a time.

*Sgnoogle*

## License

[MIT](LICENSE): free to use, modify and share, for any purpose.

---

<sub>Clip Importer is an independent project, not affiliated with, endorsed by or sponsored by Sony Group Corporation. Sony, Alpha, α, XAVC S, XAVC HS, AVCHD, Handycam, PlayMemories Home and Imaging Edge are trademarks of their respective owners and are used here only to describe compatibility.</sub>
