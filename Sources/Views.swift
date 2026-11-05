import SwiftUI
import AVFoundation
import ImageIO

// MARK: - Finestra principale

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            if let source = state.current {
                HeaderBar(source: source)
                Divider()
                Group {
                    if state.scanning {
                        ProgressView(source.isVolume ? L("Reading the card…") : L("Reading the folder…"))
                    } else if state.clips.isEmpty {
                        VStack(spacing: 14) {
                            MessageView(icon: "film", title: L("No photos or videos here"),
                                        subtitle: source.isVolume
                                            ? L("There's nothing to import on this card.")
                                            : L("There are no photos or videos in this folder. Anything you add will show up automatically."))
                            Button(L("Choose another folder…")) { state.chooseSourceFolder() }
                        }
                    } else if state.filteredClips.isEmpty {
                        VStack(spacing: 14) {
                            MessageView(icon: state.mediaFilter == .photos ? "photo" : "film",
                                        title: state.mediaFilter == .photos ? L("No photos here") : L("No videos here"),
                                        subtitle: state.mediaFilter == .photos ? L("There are only videos.") : L("There are only photos."))
                            Button(L("Show all")) { state.mediaFilter = .all }
                        }
                    } else if state.visibleClips.isEmpty {
                        MessageView(icon: "checkmark.circle", title: L("You've already imported everything"),
                                    subtitle: L("Uncheck “Hide imported” to see them again."))
                    } else {
                        ClipGrid()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                ImportBar()
            } else {
                WelcomeView()
            }
        }
        .frame(minWidth: 980, minHeight: 560)
        .overlay(alignment: .bottom) {
            if let text = state.banner {
                Label(text, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    .padding(.bottom, 92)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

struct WelcomeView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sdcard")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.tint)
            Text(L("Insert your camera's SD card"))
                .font(.title2.weight(.semibold))
            Text(L("Clip Importer opens by itself when you insert a card and shows you what to import. You can close this window: it keeps running in the menu bar."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Button(L("Browse a folder…")) { state.chooseSourceFolder() }
                .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MessageView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 44, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(subtitle).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Barra in alto

struct HeaderBar: View {
    @EnvironmentObject var state: AppState
    let source: Source

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: source.isVolume ? "sdcard.fill" : "folder.fill")
                .font(.system(size: 22))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Menu {
                    ForEach(state.orderedSources) { s in
                        Button { if s.id != source.id { state.open(s) } } label: {
                            Label(s.name, systemImage: s.id == source.id ? "checkmark"
                                  : (s.isVolume ? "sdcard" : "folder"))
                        }
                    }
                    Divider()
                    Button(L("Browse another folder… (⌘O)")) { state.chooseSourceFolder() }
                    Button(L("Refresh (⌘R)")) { state.refresh() }
                    Button(L("Show in Finder")) { state.revealCurrent() }
                    if !source.isVolume {
                        Divider()
                        Button(L("Remove “{0}” from the list", source.name)) { state.removeSource(source) }
                    }
                } label: {
                    Text(source.name).font(.headline)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(state.progress != nil)
                .help(source.id.path)
                Text(state.statusText).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button(L("Change folder…")) { state.chooseSourceFolder() }
                .controlSize(.small)
                .disabled(state.progress != nil)
                .help(L("Choose another folder to import from"))

            Button { state.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .help(source.isVolume ? L("Re-read the card (⌘R)")
                      : L("Re-read the folder (⌘R) · new clips show up automatically anyway"))
                .disabled(state.progress != nil || state.scanning)

            Spacer(minLength: 10)

            Picker(L("Show"), selection: $state.mediaFilter) {
                ForEach(MediaFilter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help(L("Show photos and videos, only videos or only photos"))

            Spacer(minLength: 10)

            Menu {
                Picker(L("Sort by"), selection: $state.sortKey) {
                    ForEach(SortKey.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Picker(L("Order"), selection: $state.ascending) {
                    Text(state.sortKey == .date ? L("Oldest first") : L("Ascending")).tag(true)
                    Text(state.sortKey == .date ? L("Newest first") : L("Descending")).tag(false)
                }
                .pickerStyle(.inline)
            } label: {
                Label(state.sortKey.label, systemImage: "arrow.up.arrow.down")
            }
            .fixedSize()
            .help(L("Sorting"))

            Toggle(L("Hide imported"), isOn: $state.hideImported)
                .toggleStyle(.checkbox)

            Menu(L("Select")) {
                Button(L("All (⌘A)")) { state.selectAll() }
                Button(L("Only new (⇧⌘A)")) { state.selectNew() }
                Button(L("None (⌥⌘A)")) { state.selectNone() }
                Divider()
                Button(L("Picked")) { state.selectFlagged(.pick) }
                Button(L("Rejected")) { state.selectFlagged(.reject) }
            }
            .fixedSize()

            HStack(spacing: 4) {
                Image(systemName: "square.grid.3x3").font(.system(size: 10))
                Slider(value: $state.thumbSize, in: 150...380).frame(width: 70)
                Image(systemName: "square.grid.2x2").font(.system(size: 13))
            }
            .foregroundStyle(.secondary)
            .help(L("Thumbnail size"))

            if source.isVolume {
                Button { state.eject() } label: { Image(systemName: "eject") }
                    .help(L("Eject the card"))
                    .disabled(state.progress != nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

// MARK: - Griglia

struct ClipGrid: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let size = CGFloat(state.thumbSize)
        let columns = [GridItem(.adaptive(minimum: size, maximum: size * 1.45), spacing: 14, alignment: .top)]
        ScrollViewReader { proxy in
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
                if state.sortKey == .date {
                    ForEach(state.sections) { section in
                        Section {
                            ForEach(section.clips) { clip in cell(clip) }
                        } header: {
                            DayHeader(section: section)
                        }
                    }
                } else {
                    ForEach(state.visibleClips) { clip in cell(clip) }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                // Clic sullo spazio vuoto: deseleziona
                Color.clear.contentShape(Rectangle()).onTapGesture { state.selectNone() }
            )
        }
        .onChange(of: state.scrollTarget) { id in
            guard let id else { return }
            withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(id) }
            state.scrollTarget = nil
        }
        }
    }

    /// Dal menu contestuale: agisce sulla selezione se la clip ne fa parte, altrimenti solo su lei.
    private func flagOne(_ clip: Clip, _ f: Flag?) {
        if !state.selection.contains(clip.id) { state.selection = [clip.id] }
        if f == nil || state.selectedClips.count > 1 || state.flag(clip) != f { state.flagSelection(f) }
    }

    @ViewBuilder
    private func cell(_ clip: Clip) -> some View {
        let imported = state.isImported(clip)
        ClipCell(clip: clip, selected: state.selection.contains(clip.id), imported: imported, flag: state.flag(clip))
            .id(clip.id)
            .onTapGesture { state.click(clip) }
            // Trascina la clip nel Finder o direttamente in DaVinci Resolve
            .onDrag { NSItemProvider(object: clip.url as NSURL) }
            .contextMenu {
                Button(clip.isPhoto ? L("Open") : L("Play")) { NSWorkspace.shared.open(clip.url) }
                Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([clip.url]) }
                Button(L("Copy")) {
                    if !state.selection.contains(clip.id) { state.selection = [clip.id] }
                    state.copySelection()
                }
                Divider()
                Button(clip.isPhoto ? L("Import only this photo") : L("Import only this clip")) { state.importClips([clip], move: false) }
                    .disabled(state.progress != nil)
                Button(clip.isPhoto ? L("Move only this photo (delete {0})", state.sourcePlace) : L("Move only this clip (delete {0})", state.sourcePlace)) {
                    state.importClips([clip], move: true)
                }
                .disabled(state.progress != nil)
                Divider()
                let flag = state.flag(clip)
                Button(flag == .pick ? L("Picked ✓ (P)") : L("Mark as picked (P)")) { flagOne(clip, .pick) }
                Button(flag == .reject ? L("Rejected ✓ (X)") : L("Mark as rejected (X)")) { flagOne(clip, .reject) }
                if flag != nil { Button(L("Remove flag (U)")) { flagOne(clip, nil) } }
                Divider()
                Button(imported ? L("Mark as not imported") : L("Mark as already imported")) {
                    state.setImported(clip, !imported)
                }
                Divider()
                Button(state.current?.isVolume ?? true ? L("Delete from card…") : L("Move to Trash")) {
                    if !state.selection.contains(clip.id) { state.selection = [clip.id] }
                    state.deleteSelection()
                }
                .disabled(state.progress != nil)
            }
    }
}

struct DayHeader: View {
    @EnvironmentObject var state: AppState
    let section: DaySection

    var body: some View {
        HStack(spacing: 8) {
            Text(Fmt.day(section.id)).font(.system(size: 13, weight: .semibold))
            Text(Fmt.clips(section.clips.count)).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Button(state.isDaySelected(section) ? L("Deselect day") : L("Select day")) {
                state.toggleDay(section)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.bar, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Miniatura

struct ClipCell: View {
    @EnvironmentObject var state: AppState
    let clip: Clip
    let selected: Bool
    let imported: Bool
    var flag: Flag? = nil
    var forceHover = false      // solo per le anteprime di prova

    @State private var thumb: NSImage?
    @State private var thumbFailed = false
    @State private var loadedDuration: Double?
    @State private var hovering = false

    // Anteprima scorrendo il mouse sulla miniatura
    @State private var scrubImage: NSImage?
    @State private var scrubFraction: CGFloat?
    @State private var scrubTask: Task<Void, Never>?
    @State private var lastRequested: CGFloat = -1
    @State private var generator: AVAssetImageGenerator?

    private var duration: Double? { clip.duration ?? loadedDuration }

    /// Scartate e già importate si sbiadiscono, ma il segnalibro resta pieno e leggibile.
    private var dim: Double {
        if flag == .reject { return selected ? 0.6 : 0.4 }
        return imported && !selected ? 0.55 : 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(clip.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .opacity(dim)
                    if imported {
                        // Grigio: il verde è riservato all'etichetta "scelta"
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .help(L("Already imported"))
                    }
                }
                Text("\(Fmt.time(clip.date)) · \(Fmt.bytes(clip.importSize))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .opacity(dim)
                if let tech = clip.techLabel {
                    Text(tech)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .opacity(dim)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 3)
            .padding(.bottom, 2)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(selected ? Color.accentColor.opacity(0.18) : (hovering ? Color.primary.opacity(0.05) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2.5)
        )
        .contentShape(Rectangle())

        .onHover { hovering = $0 }
        .help(Fmt.dateTime(clip.date))
    }

    private var thumbnail: some View {
        Color.black
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                if let image = scrubImage ?? thumb {
                    // Le foto verticali si vedono intere, senza tagliare teste e piedi
                    // Le scartate in bianco e nero: si vede al volo che sono fuori gioco
                    if clip.isPhoto && image.size.height > image.size.width {
                        Image(nsImage: image).resizable().scaledToFit().saturation(flag == .reject ? 0 : 1).opacity(dim)
                    } else {
                        Image(nsImage: image).resizable().scaledToFill().saturation(flag == .reject ? 0 : 1).opacity(dim)
                    }
                } else if thumbFailed {
                    Image(systemName: "film").font(.system(size: 28)).foregroundColor(.gray)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .overlay(
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in scrub(phase, width: geo.size.width) }
                }
            )
            .overlay(alignment: .bottomTrailing) {
                if clip.isPhoto, let badge = clip.badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                } else if let d = duration {
                    Text(Fmt.duration(d))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let f = scrubFraction {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * f, height: 3)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                // Etichetta: un segnalibro che pende dal bordo, mai un cerchio (quello è la selezione)
                if flag != nil || hovering || forceHover {
                    FlagRibbonButton(clip: clip, flag: flag).padding(.leading, 10)
                }
            }
            .overlay(alignment: .topTrailing) {
                if selected || hovering {
                    Button { state.toggle(clip) } label: {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(selected ? .accentColor : .white)
                            .background(Circle().fill(Color.black.opacity(selected ? 0 : 0.25)))
                            .shadow(color: .black.opacity(0.4), radius: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .help(selected ? L("Remove from selection") : L("Add to selection"))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .task(id: clip.id) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        guard thumb == nil else { return }
        let result = await ThumbnailLoader.load(clip)
        let hasOwnDuration = clip.duration != nil
        await MainActor.run {
            thumb = result.image
            thumbFailed = result.image == nil
            if !hasOwnDuration { loadedDuration = result.duration }
        }
    }

    private func scrub(_ phase: HoverPhase, width: CGFloat) {
        switch phase {
        case .active(let point):
            guard width > 0, clip.canPreview, let d = duration, d > 0 else { return }
            let f = min(max(point.x / width, 0), 1)
            scrubFraction = f
            guard abs(f - lastRequested) > 0.015 else { return }
            lastRequested = f
            scrubTask?.cancel()
            let gen = generator ?? ThumbnailLoader.makeScrubGenerator(for: clip.url)
            generator = gen
            let time = CMTime(seconds: d * Double(f) * 0.995, preferredTimescale: 600)
            scrubTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 35_000_000)
                if Task.isCancelled { return }
                if let cg = try? await gen.image(at: time).image, !Task.isCancelled, scrubFraction != nil {
                    scrubImage = NSImage(cgImage: cg, size: .zero)
                }
            }
        case .ended:
            scrubTask?.cancel()
            scrubTask = nil
            scrubFraction = nil
            scrubImage = nil
            lastRequested = -1
        }
    }
}

// MARK: - Etichette

extension Flag {
    var color: Color { self == .pick ? Color(red: 0.20, green: 0.70, blue: 0.33) : Color(red: 0.90, green: 0.22, blue: 0.21) }
    var symbol: String { self == .pick ? "flag.fill" : "flag.slash.fill" }
}

/// Forma a segnalibro: rettangolo con la coda a V.
struct RibbonShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY - r.width * 0.32))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Il segnalibro che pende dal bordo superiore della miniatura.
/// Vuoto (solo contorno) al passaggio del mouse; pieno quando la clip ha un'etichetta.
/// Clic: scelta sì/no · ⌥ clic: scartata · clic destro: menu.
struct FlagRibbonButton: View {
    @EnvironmentObject var state: AppState
    let clip: Clip
    let flag: Flag?
    @State private var over = false

    var body: some View {
        Button(action: click) { ribbon }
            .buttonStyle(.plain)
            .onHover { over = $0 }
            .help(help)
            .contextMenu {
                Button(flag == .pick ? L("Picked ✓ (P)") : L("Pick (P)")) { state.toggleFlag(.pick, on: clip) }
                Button(flag == .reject ? L("Rejected ✓ (X)") : L("Reject (X)")) { state.toggleFlag(.reject, on: clip) }
                if flag != nil { Button(L("Remove flag (U)")) { state.setFlag(nil, on: clip) } }
            }
    }

    private var ribbon: some View {
        ZStack(alignment: .top) {
            if let flag {
                RibbonShape().fill(flag.color)
            } else {
                RibbonShape().fill(Color.black.opacity(over ? 0.5 : 0.3))
                RibbonShape().stroke(Color.white.opacity(over ? 1 : 0.85), lineWidth: 1.5)
            }
            Image(systemName: flag?.symbol ?? "flag")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 7)
        }
        .frame(width: 26, height: 36)
        .scaleEffect(over ? 1.06 : 1, anchor: .top)
        .animation(.easeOut(duration: 0.12), value: over)
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        .contentShape(Rectangle())
    }

    private var help: String {
        switch flag {
        case .pick: return L("Picked: only picks get imported · click to remove · ⌥-click to reject")
        case .reject: return L("Rejected: won't be imported · click to remove")
        case nil: return L("Click: pick (P) · ⌥-click: reject (X) · right-click: more options")
        }
    }

    private func click() {
        if NSEvent.modifierFlags.contains(.option) {
            state.toggleFlag(.reject, on: clip)
        } else if flag == .reject {
            state.setFlag(nil, on: clip)
        } else {
            state.toggleFlag(.pick, on: clip)
        }
    }
}

enum ThumbnailLoader {
    struct Result {
        var image: NSImage?
        var duration: Double?
    }

    private static let cache = NSCache<NSURL, NSImage>()

    static func load(_ clip: Clip) async -> Result {
        if let cached = cache.object(forKey: clip.url as NSURL) { return Result(image: cached, duration: nil) }
        let result = await Task.detached(priority: .utility) { () -> Result in
            // 1) Miniatura già pronta di Sony: istantanea
            if let t = clip.thumbnailURL, let image = NSImage(contentsOf: t) {
                return Result(image: image, duration: nil)
            }
            if clip.isPhoto { return Result(image: photoThumbnail(clip.url), duration: nil) }
            guard clip.canPreview else { return Result(image: nil, duration: nil) }
            // 2) Fotogramma estratto dal video
            let asset = AVURLAsset(url: clip.url)
            var duration: Double?
            if clip.duration == nil, let d = try? await asset.load(.duration), d.seconds.isFinite {
                duration = d.seconds
            }
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 640, height: 360)
            let total = clip.duration ?? duration ?? 0
            let time = CMTime(seconds: min(1.0, total * 0.1), preferredTimescale: 600)
            if let cg = try? await gen.image(at: time).image {
                return Result(image: NSImage(cgImage: cg, size: .zero), duration: duration)
            }
            return Result(image: nil, duration: duration)
        }.value
        if let image = result.image { cache.setObject(image, forKey: clip.url as NSURL) }
        return result
    }

    /// Miniatura di una foto. JPEG/HEIF: ridotti dal file (nitidi, il thumbnail EXIF è minuscolo).
    /// RAW: anteprima incorporata, senza sviluppare il RAW (molto più veloce).
    static func photoThumbnail(_ url: URL) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let isRaw = CardScanner.rawExtensions.contains(url.pathExtension.lowercased())
        let opts: [CFString: Any] = [
            isRaw ? kCGImageSourceCreateThumbnailFromImageIfAbsent : kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 640,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    static func makeScrubGenerator(for url: URL) -> AVAssetImageGenerator {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 640, height: 360)
        // Tolleranza ampia = usa i fotogrammi chiave, molto più veloce dalla scheda
        let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
        gen.requestedTimeToleranceBefore = tolerance
        gen.requestedTimeToleranceAfter = tolerance
        return gen
    }
}

// MARK: - Barra in basso

struct ImportBar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if let p = state.progress {
                ProgressRow(progress: p)
            } else {
                controls
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 74)
        .background(.bar)
    }

    private var controls: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L("IMPORT TO")).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").foregroundStyle(.tint)
                    Text(state.destinationDisplay)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 240, alignment: .leading)
                        .help(state.destinationPath)
                    Button(L("Change…")) { state.chooseDestination() }.controlSize(.small)
                }
            }

            Divider().frame(height: 36)

            VStack(alignment: .leading, spacing: 5) {
                Text(L("ORGANIZE")).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Picker("", selection: $state.folderMode) {
                        ForEach(FolderMode.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    if state.folderMode == .custom {
                        TextField(L("Folder name"), text: $state.customFolderName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                    }
                }
                Text(state.destinationPreview)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Menu {
                Toggle(L("Also copy Sony XML metadata files"), isOn: $state.copySidecar)
                Toggle(L("Also copy proxies (in a “Proxy” folder, ready for DaVinci Resolve)"), isOn: $state.copyProxy)
                Toggle(L("Add date and time to file names"), isOn: $state.renameWithDate)
                Divider()
                Toggle(L("Show in Finder when done"), isOn: $state.revealAfter)
                Toggle(L("Eject the card when done"), isOn: $state.ejectAfter)
                Divider()
                Toggle(L("Open automatically when a card is inserted"), isOn: $state.autoOpen)
                Toggle(L("Start at login"), isOn: $state.launchAtLogin)
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L("Options"))

            VStack(alignment: .trailing, spacing: 6) {
                Button { state.startImport() } label: {
                    Label(state.importButtonTitle, systemImage: state.willMove ? "scissors" : "square.and.arrow.down")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(state.clipsToImport.isEmpty)
                .help(state.usingPicks ? L("Imports the new picked items (rejected ones are never imported)") : state.willMove
                      ? L("Copies, verifies byte by byte, then deletes the originals {0} (⌥⌘I)", state.sourcePlace)
                      : L("With nothing selected, imports everything new (⌘I) · hold ⌥ to move"))

                Toggle(L("Delete {0} after copying", state.sourcePlace), isOn: $state.deleteAfter)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .help((state.current?.isVolume ?? true)
                          ? L("Each file is deleted from the card only after verifying that the copy is identical")
                          : L("Originals go to the Trash only after verifying that the copy is identical"))
            }
        }
    }
}

struct ProgressRow: View {
    @EnvironmentObject var state: AppState
    let progress: ImportProgress

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(progress.verb.replacingOccurrences(of: "{0}", with: progress.currentName))
                        .font(.system(size: 13, weight: .semibold))
                    Text(L("{0} of {1}", progress.fileIndex + 1, progress.fileCount))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(progress.detail)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress.fraction)
            }
            Button(L("Cancel")) { state.cancelImport() }
        }
    }
}
