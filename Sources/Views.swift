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
                        ProgressView(source.isVolume ? "Lettura della scheda…" : "Lettura della cartella…")
                    } else if state.clips.isEmpty {
                        VStack(spacing: 14) {
                            MessageView(icon: "film", title: "Nessuna foto o video qui",
                                        subtitle: source.isVolume
                                            ? "Su questa scheda non c'è niente da importare."
                                            : "In questa cartella non ci sono foto o video. Quelli che ci aggiungi compaiono da soli.")
                            Button("Scegli un'altra cartella…") { state.chooseSourceFolder() }
                        }
                    } else if state.filteredClips.isEmpty {
                        VStack(spacing: 14) {
                            MessageView(icon: state.mediaFilter == .photos ? "photo" : "film",
                                        title: state.mediaFilter == .photos ? "Nessuna foto qui" : "Nessun video qui",
                                        subtitle: "Ci sono solo \(state.mediaFilter == .photos ? "video" : "foto").")
                            Button("Mostra tutto") { state.mediaFilter = .all }
                        }
                    } else if state.visibleClips.isEmpty {
                        MessageView(icon: "checkmark.circle", title: "Hai già importato tutto",
                                    subtitle: "Togli la spunta da «Nascondi importate» per rivederle.")
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
            Text("Inserisci la scheda SD della fotocamera")
                .font(.title2.weight(.semibold))
            Text("Clip Importer si apre da solo quando colleghi la scheda e ti mostra le clip da importare. Puoi chiudere questa finestra: resta attivo nella barra dei menu.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Button("Sfoglia una cartella…") { state.chooseSourceFolder() }
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
                    Button("Sfoglia un'altra cartella… (⌘O)") { state.chooseSourceFolder() }
                    Button("Aggiorna (⌘R)") { state.refresh() }
                    Button("Mostra nel Finder") { state.revealCurrent() }
                    if !source.isVolume {
                        Divider()
                        Button("Togli «\(source.name)» dall'elenco") { state.removeSource(source) }
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

            Button("Cambia cartella…") { state.chooseSourceFolder() }
                .controlSize(.small)
                .disabled(state.progress != nil)
                .help("Scegli un'altra cartella da cui importare")

            Button { state.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .help(source.isVolume ? "Rileggi la scheda (⌘R)"
                      : "Rileggi la cartella (⌘R) · le clip nuove compaiono comunque da sole")
                .disabled(state.progress != nil || state.scanning)

            Spacer(minLength: 10)

            Picker("Mostra", selection: $state.mediaFilter) {
                ForEach(MediaFilter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Mostra foto e video, solo i video o solo le foto")

            Spacer(minLength: 10)

            Menu {
                Picker("Ordina per", selection: $state.sortKey) {
                    ForEach(SortKey.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Picker("Ordine", selection: $state.ascending) {
                    Text(state.sortKey == .date ? "Dalla più vecchia" : "Crescente").tag(true)
                    Text(state.sortKey == .date ? "Dalla più recente" : "Decrescente").tag(false)
                }
                .pickerStyle(.inline)
            } label: {
                Label(state.sortKey.label, systemImage: "arrow.up.arrow.down")
            }
            .fixedSize()
            .help("Ordinamento")

            Toggle("Nascondi importate", isOn: $state.hideImported)
                .toggleStyle(.checkbox)

            Menu("Seleziona") {
                Button("Tutte (⌘A)") { state.selectAll() }
                Button("Solo le nuove (⇧⌘A)") { state.selectNew() }
                Button("Nessuna (⌥⌘A)") { state.selectNone() }
                Divider()
                Button("Le scelte") { state.selectFlagged(.pick) }
                Button("Le scartate") { state.selectFlagged(.reject) }
            }
            .fixedSize()

            HStack(spacing: 4) {
                Image(systemName: "square.grid.3x3").font(.system(size: 10))
                Slider(value: $state.thumbSize, in: 150...380).frame(width: 70)
                Image(systemName: "square.grid.2x2").font(.system(size: 13))
            }
            .foregroundStyle(.secondary)
            .help("Dimensione delle miniature")

            if source.isVolume {
                Button { state.eject() } label: { Image(systemName: "eject") }
                    .help("Espelli la scheda")
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
                Button(clip.isPhoto ? "Apri" : "Riproduci") { NSWorkspace.shared.open(clip.url) }
                Button("Mostra nel Finder") { NSWorkspace.shared.activateFileViewerSelecting([clip.url]) }
                Button("Copia") {
                    if !state.selection.contains(clip.id) { state.selection = [clip.id] }
                    state.copySelection()
                }
                Divider()
                Button(clip.isPhoto ? "Importa solo questa foto" : "Importa solo questa clip") { state.importClips([clip], move: false) }
                    .disabled(state.progress != nil)
                Button("Sposta solo questa \(clip.isPhoto ? "foto" : "clip") (cancella \(state.sourcePlace))") {
                    state.importClips([clip], move: true)
                }
                .disabled(state.progress != nil)
                Divider()
                let flag = state.flag(clip)
                Button(flag == .pick ? "Scelta ✓ (P)" : "Segna come scelta (P)") { flagOne(clip, .pick) }
                Button(flag == .reject ? "Scartata ✓ (X)" : "Segna come scartata (X)") { flagOne(clip, .reject) }
                if flag != nil { Button("Togli etichetta (U)") { flagOne(clip, nil) } }
                Divider()
                Button(imported ? "Segna come non importata" : "Segna come già importata") {
                    state.setImported(clip, !imported)
                }
                Divider()
                Button(state.current?.isVolume ?? true ? "Elimina dalla scheda…" : "Sposta nel Cestino") {
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
            Button(state.isDaySelected(section) ? "Deseleziona giorno" : "Seleziona giorno") {
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
                            .help("Già importata")
                    }
                    Spacer(minLength: 4)
                    FlagControls(clip: clip, flag: flag, visible: hovering || flag != nil)
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
                if let flag { FlagRibbon(flag: flag).padding(.leading, 10) }
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
                    .help(selected ? "Togli dalla selezione" : "Aggiungi alla selezione")
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
struct FlagRibbon: View {
    let flag: Flag
    var body: some View {
        RibbonShape()
            .fill(flag.color)
            .frame(width: 22, height: 30)
            .overlay(alignment: .top) {
                Image(systemName: flag.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 6)
            }
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .help(flag == .pick ? "Scelta (P) · si importano solo le scelte" : "Scartata (X) · non verrà importata")
            .allowsHitTesting(true)
    }
}

/// Le due bandierine nella riga del nome: grigie al passaggio del mouse, colorate se attive.
struct FlagControls: View {
    @EnvironmentObject var state: AppState
    let clip: Clip
    let flag: Flag?
    let visible: Bool

    var body: some View {
        HStack(spacing: 2) {
            button(.pick, help: flag == .pick ? "Togli «scelta» (U)" : "Scegli (P)")
            button(.reject, help: flag == .reject ? "Togli «scartata» (U)" : "Scarta (X) · non verrà importata")
        }
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
    }

    private func button(_ f: Flag, help: String) -> some View {
        Button { state.toggleFlag(f, on: clip) } label: {
            Image(systemName: flag == f ? f.symbol : (f == .pick ? "flag" : "flag.slash"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(flag == f ? AnyShapeStyle(f.color) : AnyShapeStyle(.secondary))
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
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
                Text("IMPORTA IN").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").foregroundStyle(.tint)
                    Text(state.destinationDisplay)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 240, alignment: .leading)
                        .help(state.destinationPath)
                    Button("Cambia…") { state.chooseDestination() }.controlSize(.small)
                }
            }

            Divider().frame(height: 36)

            VStack(alignment: .leading, spacing: 5) {
                Text("ORGANIZZA").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Picker("", selection: $state.folderMode) {
                        ForEach(FolderMode.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    if state.folderMode == .custom {
                        TextField("Nome della cartella", text: $state.customFolderName)
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
                Toggle("Copia anche i file XML dei metadati Sony", isOn: $state.copySidecar)
                Toggle("Copia anche i proxy (in una cartella «Proxy», pronta per DaVinci Resolve)", isOn: $state.copyProxy)
                Toggle("Aggiungi data e ora al nome dei file", isOn: $state.renameWithDate)
                Divider()
                Toggle("Mostra le clip nel Finder al termine", isOn: $state.revealAfter)
                Toggle("Espelli la scheda al termine", isOn: $state.ejectAfter)
                Divider()
                Toggle("Apri automaticamente quando inserisci una scheda", isOn: $state.autoOpen)
                Toggle("Avvia all'accesso al Mac", isOn: $state.launchAtLogin)
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Opzioni")

            VStack(alignment: .trailing, spacing: 6) {
                Button { state.startImport() } label: {
                    Label(state.importButtonTitle, systemImage: state.willMove ? "scissors" : "square.and.arrow.down")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(state.clipsToImport.isEmpty)
                .help(state.usingPicks ? "Importa le clip nuove segnate come scelte (le scartate non si importano mai)" : state.willMove
                      ? "Copia, verifica byte per byte e poi cancella gli originali \(state.sourcePlace) (⌥⌘I)"
                      : "Senza selezione importa tutto ciò che è nuovo (⌘I) · tieni premuto ⌥ per spostare")

                Toggle("Cancella \(state.sourcePlace) dopo la copia", isOn: $state.deleteAfter)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .help((state.current?.isVolume ?? true)
                          ? "Ogni file viene cancellato dalla scheda solo dopo aver verificato che la copia è identica"
                          : "Gli originali finiscono nel Cestino solo dopo aver verificato che la copia è identica")
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
                    Text("\(progress.verb) \(progress.currentName)")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(progress.fileIndex + 1) di \(progress.fileCount)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(progress.detail)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress.fraction)
            }
            Button("Annulla") { state.cancelImport() }
        }
    }
}
