# Clip Importer: project memory

This file is the memory of the project for Claude (and for anyone who wants to contribute).
It records what was built, **why** each choice was made, how to build and release, and what is still open.
Read it fully before changing anything.

## Who and how

- The maintainer (GitHub **Sgnoogle**) can't write code; every line was written by Claude in conversation,
  starting 2026-11-05. **Talk to the maintainer in Italian**, in plain words, no jargon.
- The maintainer cares a lot about **Mac-quality UX**: "what would Apple do?". Discoverability matters
  (they asked "how would a user know that P/X/U exist?"), controls must not be confused with each other
  (flag vs selection), sizes must not be tiny.
- **No em dashes (—) in English texts** (README, release notes, UI strings). Use periods, colons, commas,
  parentheses. Russian тире inside Russian translations is grammar and stays.
- Before publishing anything public (screenshots, README), check for personal data. Screenshot thumbnails are
  real footage from the maintainer's card: clip `C0002` shows shipping labels with QR/barcodes and is excluded.
- Commit identity in this repo: `Sgnoogle <161589246+Sgnoogle@users.noreply.github.com>` (never the personal
  email). Commits end with the `Co-Authored-By: Claude …` line. Commit messages are in Italian.
- Ask before destructive or public actions (deleting repos, force pushes, new releases are fine once asked).

## What it is

A free, open-source replacement for Sony **PlayMemories Home**: insert a Sony SD card, the window opens,
pick clips/photos, import them into dated folders. Two native apps sharing one translation file:

| | Mac | Windows |
|---|---|---|
| Code | `Sources/*.swift` (SwiftUI + AppKit, no Xcode project) | `windows/ClipImporter/*.cs` (WPF, .NET 8) |
| Lives in | menu bar (status item) | notification area (tray) |
| Build | `bash build.sh` (builds, installs to /Applications, relaunches) | GitHub Actions only (see below) |
| Package | `bash pacchetto.sh` → `~/Downloads/ClipImporter.zip` (universal arm64+x86_64) | workflow → `ClipImporter-Windows-x64.zip`, `-arm64.zip` |
| Min OS | macOS 13 | Windows 10 1809 / 11 |

Tested with a **Sony α5100** card (XAVC S in `PRIVATE/M4ROOT`, JPEG in `DCIM/100MSDCF`). The card mounts as "no name".

## Repository layout

```
Sources/            Mac app
  AppDelegate.swift   status item menu, main menu, window, key handling (local monitors), Quick Look
  AppState.swift      sources, selection, flags, filter/sort, import/move/delete, alerts, banner
  CardScanner.swift   card detection, XAVC/AVCHD/DCIM scan, Sony XML parse, photos + RAW pairing, EXIF
  Importer.swift      copy (temp .part files), SHA-256 verify, delete originals, SonyIndex (MEDIAPRO.XML),
                      ImportedStore, FlagStore, LoginItem (LaunchAgent), freeSpace
  Views.swift         SwiftUI UI: header, grid, ClipCell, FlagRibbonButton, ImportBar, ThumbnailLoader
  Models.swift        Clip, Source, enums (SortKey, FolderMode, MediaFilter, Flag, DeleteMode), Fmt formatters
  Lang.swift          language detection, L(), pluralCategory()
  FolderWatcher.swift FSEvents watcher (folders AND cards)
Resources/          Info.plist, AppIcon.icns, strings.json (shared translations)
windows/            Windows app (ClipImporter.sln, ClipImporter/, strings.windows.json, README-Windows.txt, tools/)
.github/workflows/windows.yml   Windows build + self-test + publish
docs/               icon.png, screenshot.png, social-preview.png (README images)
tools/screenshots/  offscreen renderer for docs/ images (usage in the file header)
install.sh          one-line Mac installer (curl | bash), downloads latest release, strips quarantine
LEGGIMI.md          Italian readme (not linked from README by maintainer's choice; README is English)
```

## Build, test, release

**Mac**
- `bash build.sh` after every change, so the installed app is updated (the maintainer uses it daily).
- Typecheck only: `xcrun swiftc -typecheck -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macos13.0" -sdk "$(xcrun --show-sdk-path --sdk macosx)" Sources/*.swift`
- Logic can be tested with a small harness compiled with all sources except `AppDelegate.swift` plus a `main.swift`
  (that's how scanner, verified move and MEDIAPRO cleanup were tested on a copy of the real card).
- UI can be "seen" without screen permissions with `tools/screenshots` (renders real views offscreen at 2x;
  `Lang.use(code, stringsFile:)` switches language). Use it to check layouts in long languages (de, ru).

**Windows**
- Local .NET install on the Mac was **blocked by the sandbox**; don't retry. Build and test happen on GitHub Actions
  (`windows-latest`) on every push touching `windows/`, the workflow or `Resources/strings.json`.
- The workflow: build, translation check (every `L()` key exists, placeholders match in all languages),
  `ClipImporter.exe --selftest <dir>` (47 checks on a fake Sony card: scan, RAW+JPEG, verified move, MEDIAPRO
  cleanup, cancel, skip identical, all languages), a window smoke test, then single-file self-contained publish
  for win-x64 and win-arm64.
- Watch runs with `gh run list` / `gh run watch <id>` / `gh run view <id> --log-failed`. Failed runs email the
  maintainer: warn them when iterating.

**Release**
1. Bump versions: `Resources/Info.plist` (CFBundleShortVersionString + CFBundleVersion) and
   `windows/ClipImporter/ClipImporter.csproj` `<Version>`.
2. `bash build.sh && bash pacchetto.sh`, commit, push main.
3. `git tag vX.Y && git push origin vX.Y`, then `gh release create vX.Y ~/Downloads/ClipImporter.zip ...`.
   The tag run attaches the two Windows zips to that release automatically (a few minutes later).
4. README download buttons use `releases/latest/download/<file>`: asset names must stay
   `ClipImporter.zip`, `ClipImporter-Windows-x64.zip`, `ClipImporter-Windows-arm64.zip`.
5. Verify the three links answer (curl) before telling the maintainer it's done.

Never `git add -A` blindly: subagent worktrees live in `.claude/` (now in `.gitignore`; once a gitlink got pushed).

## Localization (10 languages)

- en (keys), it, es, fr, de, pt (pt-BR), ru, ja, ko, zh (zh-Hans). Language = first system language among these, else English.
- Every UI string goes through `L("English text with {0}", args...)` (Swift and C#). Translations live in
  `Resources/strings.json` → `translations.<lang>.<english key>`. Windows-only wording (Explorer, Recycle Bin,
  Ctrl/Alt, F5…) in `windows/strings.windows.json` (overrides).
- Plurals: if an `Int` is among the args, the first one picks `key#one/#few/#many/#other` (CLDR rules in
  `pluralCategory`). Russian uses all three; CJK none. Phrases that receive a mixed count ("12 clips and 3 photos")
  use label style ("Imported: {0}") in languages where gender/number agreement would break.
- **Adding or changing a UI string = add it to all 9 translations** (and Russian variants if it has a count).
  Then check: all keys used in code exist, placeholders match. Translations were made by Claude, not native
  speakers: corrections from users are welcome.
- Sizes are formatted by `Fmt.bytes` with the interface language's decimal separator (not ByteCountFormatter).

## Decisions and why (chronological)

1. **Free-space bug** ("Zero KB free" on an external SSD): `volumeAvailableCapacityForImportantUsage` returns 0 on
   ExFAT/non-APFS volumes. Now the max of three APIs; if none is reliable, don't block.
2. **Photos**: JPEG/HEIF/RAW in DCIM. RAW+JPEG with the same name = one item ("RAW + JPEG" badge), both copied with
   the same base name (keeps Lightroom pairing). EXIF date/resolution. Portrait photos shown with `fit`.
3. **All / Videos / Photos** segmented control; hidden items are never imported. Sort moved into a Finder-like menu.
4. **Move (cut & paste)**: the maintainer always moves. Checkbox "Delete from the card after copying" under the
   button (remembered), button becomes ✂️ "Move…", ⌥ (Alt on Windows) toggles it like Finder, ⌥⌘I always moves.
   Safety: SHA-256 while copying, re-read destination with F_NOCACHE, delete only if identical; per-clip deletion
   (cancel = only verified ones deleted); never delete if source and destination are the same file; from folders
   on the Mac → Trash instead of permanent delete; write-protected card → clear message.
   Deletion also removes XML, THMBNL thumbnail, SUB proxy, RAW companion and the clip's `<Material>` block in
   `PRIVATE/M4ROOT/MEDIAPRO.XML` (text-level regex removal, rest of the file byte-identical) so the camera
   doesn't ask to repair its database. Photos: the camera may rebuild its image database (same as Finder delete).
5. **Finder-style shortcuts**: ⌘C puts files (+ RAW, + XML if enabled) on the pasteboard; **Finder ⌘V copies,
   ⌥⌘V moves** (verified working with files put there by another app). ⌘⌫/⌫ delete (card: confirmation,
   Return = Cancel if something was never imported), Space/⌘Y Quick Look, Esc, ←→, ⌥⌘R reveal. Plain keys are
   handled by a local key monitor that ignores text fields (menu key equivalents without modifiers would steal typing).
   Cards are watched by FSEvents too, so Finder moves update the grid.
6. **Flags like Lightroom**: P pick, X reject, U unflag (same key again toggles off). Rejected are never imported
   and shown greyscale + dimmed; if there are new picks and no selection, the button imports only the picks.
   "Delete rejected from card" (⌥⌘⌫). Stored in `~/Library/Application Support/Clip Importer/flags.json`
   keyed like the imported registry (name|size|date).
   UI evolution (maintainer feedback): circles on the image were confused with the selection circle → small flags in
   the caption row were "too small, Apple wouldn't do that" → **final: a bookmark ribbon hanging from the top-left
   edge of the thumbnail**; empty outline on hover, click = pick, ⌥-click = reject, right-click menu; filled
   green (flag.fill) / red (flag.slash.fill) when set. Selection stays the circle at top-right + accent border.
7. **Discoverability**: when something is selected, the line under the source name shows the useful keys
   ("P pick · X reject · U unflag · Space preview · ⌘⌫ delete").
8. **Click again on the only selected item deselects it** (maintainer's request; Finder doesn't, importers do).
   Click on one of many selected → only that one stays (Finder behaviour).
9. **"Imported" check is grey**, green is reserved for picks.
10. **GitHub presentation**: English README with screenshot (rendered from the real app, English UI), download
    buttons, FAQ written like real searches ("PlayMemories Home for Mac", "import XAVC S to Mac"), Sony names
    only to describe compatibility + trademark disclaimer, single verified link to Sony Imaging Edge, credits line.
    20 topics (GitHub max). Social preview image is in `docs/social-preview.png` but must be uploaded by hand
    (Settings › Social preview; no API).
11. **10 languages** and a **Windows port** were requested at the same time; one shared `strings.json`.
12. **Bartender compatibility** (2026-11-06): the status item had no `autosaveName`, so macOS called it "Item-0"
    and Bartender didn't recognise it. Now `autosaveName` and accessibility title/identifier are
    `com.sgnoogle.clipimporter.statusitem` / "Clip Importer". Don't change that name (menu bar managers key on it).
    Bartender isn't installed on the dev Mac: the maintainer verifies on theirs. Also removed a duplicate
    `CFBundleLocalizations` key in Info.plist (the second one, only "it", overrode the full list).

## Open items / ideas

- **Windows has not been tested on a real PC with a real card yet** (maintainer will test later). Unverified:
  card-insert detection (1.5 s polling), eject (Shell "Eject" verb), shell thumbnails and durations for clips
  without Sony XML, tray menu, write-protect detection, SmartScreen flow, HEVC preview (needs Microsoft HEVC
  extension), RAW thumbnails (needs Raw Image Extension). Grid is not virtualized (thousands of photos may be slow).
- Windows has no hover-scrub inside clips (Space opens a preview window instead).
- Apps are unsigned (Gatekeeper "Open Anyway" / SmartScreen "Run anyway"). Signing would need paid certificates.
- Translations not reviewed by native speakers.
- Mac: Russian summary line truncates at narrow widths (full text visible when the window is wider).
- Possible future: hover-scrub on Windows, grid virtualization, more camera models confirmed (ask users to open issues).
