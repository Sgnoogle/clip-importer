import AppKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    private let defaults = UserDefaults.standard

    // Sorgenti e clip
    @Published var sources: [Source] = []
    @Published var current: Source?
    @Published var clips: [Clip] = []
    @Published var scanning = false
    @Published var selection: Set<URL> = []
    @Published var importedKeys: Set<String> = ImportedStore.load()
    @Published var flags: [String: Flag] = FlagStore.load()
    /// Clip da portare in vista (frecce ← →)
    @Published var scrollTarget: URL?
    /// Cambia a ogni apertura di una sorgente (vedi ClipGrid)
    @Published var openGeneration = UUID()
    private var anchor: URL?
    private var watcher: FolderWatcher?
    private var rescanToken: UUID?
    private var pendingRescan = false

    /// Cartelle scelte a mano, la più recente per prima (ricordate tra un avvio e l'altro).
    private var recentFolders: [String] {
        get { defaults.stringArray(forKey: "recentFolders") ?? [] }
        set { defaults.set(Array(newValue.prefix(8)), forKey: "recentFolders") }
    }

    // Importazione
    @Published var progress: ImportProgress?
    @Published var banner: String?
    private var activeJob: UUID?
    private var cancelFlag: CancelFlag?
    private var bannerToken: UUID?

    /// Chiamata quando serve mostrare la finestra (es. scheda appena inserita).
    var onWantsWindow: (() -> Void)?

    // Impostazioni (salvate automaticamente)
    @Published var sortKey: SortKey { didSet { defaults.set(sortKey.rawValue, forKey: "sortKey") } }
    @Published var ascending: Bool { didSet { defaults.set(ascending, forKey: "ascending") } }
    @Published var hideImported: Bool { didSet { defaults.set(hideImported, forKey: "hideImported") } }
    @Published var mediaFilter: MediaFilter {
        didSet {
            defaults.set(mediaFilter.rawValue, forKey: "mediaFilter")
            // Quello che non si vede non resta selezionato (altrimenti si importerebbe "di nascosto")
            selection.formIntersection(clips.filter(mediaFilter.includes).map(\.id))
        }
    }
    @Published var thumbSize: Double { didSet { defaults.set(thumbSize, forKey: "thumbSize") } }
    @Published var destinationPath: String { didSet { defaults.set(destinationPath, forKey: "destinationPath") } }
    @Published var folderMode: FolderMode { didSet { defaults.set(folderMode.rawValue, forKey: "folderMode") } }
    @Published var customFolderName: String { didSet { defaults.set(customFolderName, forKey: "customFolderName") } }
    @Published var copySidecar: Bool { didSet { defaults.set(copySidecar, forKey: "copySidecar") } }
    @Published var copyProxy: Bool { didSet { defaults.set(copyProxy, forKey: "copyProxy") } }
    @Published var renameWithDate: Bool { didSet { defaults.set(renameWithDate, forKey: "renameWithDate") } }
    @Published var deleteAfter: Bool { didSet { defaults.set(deleteAfter, forKey: "deleteAfter") } }
    /// ⌥ premuto: come nel Finder, trasforma "Importa" in "Sposta"
    @Published var optionHeld = false
    @Published var revealAfter: Bool { didSet { defaults.set(revealAfter, forKey: "revealAfter") } }
    @Published var ejectAfter: Bool { didSet { defaults.set(ejectAfter, forKey: "ejectAfter") } }
    @Published var autoOpen: Bool { didSet { defaults.set(autoOpen, forKey: "autoOpen") } }
    @Published var launchAtLogin: Bool { didSet { LoginItem.setEnabled(launchAtLogin) } }

    private init() {
        let d = UserDefaults.standard
        let defaultDestination = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/Sony", isDirectory: true).path
        sortKey = SortKey(rawValue: d.string(forKey: "sortKey") ?? "") ?? .date
        ascending = d.object(forKey: "ascending") as? Bool ?? true
        hideImported = d.object(forKey: "hideImported") as? Bool ?? false
        mediaFilter = MediaFilter(rawValue: d.string(forKey: "mediaFilter") ?? "") ?? .all
        thumbSize = d.object(forKey: "thumbSize") as? Double ?? 230
        destinationPath = d.string(forKey: "destinationPath") ?? defaultDestination
        folderMode = FolderMode(rawValue: d.string(forKey: "folderMode") ?? "") ?? .byShootDay
        customFolderName = d.string(forKey: "customFolderName") ?? ""
        copySidecar = d.object(forKey: "copySidecar") as? Bool ?? false
        copyProxy = d.object(forKey: "copyProxy") as? Bool ?? false
        renameWithDate = d.object(forKey: "renameWithDate") as? Bool ?? false
        revealAfter = d.object(forKey: "revealAfter") as? Bool ?? true
        deleteAfter = d.object(forKey: "deleteAfter") as? Bool ?? false
        ejectAfter = d.object(forKey: "ejectAfter") as? Bool ?? false
        autoOpen = d.object(forKey: "autoOpen") as? Bool ?? true
        launchAtLogin = LoginItem.isEnabled

        // Ripristina le cartelle usate l'ultima volta (solo quelle che esistono ancora)
        let fm = FileManager.default
        for path in recentFolders {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
            let url = URL(fileURLWithPath: path, isDirectory: true)
            sources.append(Source(id: url, name: url.lastPathComponent, isVolume: false))
        }
    }

    /// All'avvio, se non c'è una scheda, riapre l'ultima cartella usata.
    func restoreLastFolder() {
        if current == nil, let first = sources.first(where: { !$0.isVolume }) { open(first) }
    }

    /// Schede prima, poi cartelle.
    var orderedSources: [Source] { sources.filter(\.isVolume) + sources.filter { !$0.isVolume } }

    // MARK: - Elenco visibile

    func isImported(_ clip: Clip) -> Bool { importedKeys.contains(ImportedStore.key(clip)) }

    var visibleClips: [Clip] {
        let filter = mediaFilter
        var list = clips.filter(filter.includes)
        if hideImported { list = list.filter { !isImported($0) } }
        let key = sortKey
        func less(_ a: Clip, _ b: Clip) -> Bool {
            switch key {
            case .date: return a.date < b.date
            case .name: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .duration: return (a.duration ?? 0) < (b.duration ?? 0)
            case .size: return a.size < b.size
            }
        }
        let asc = ascending
        list.sort { asc ? less($0, $1) : less($1, $0) }
        return list
    }

    var sections: [DaySection] {
        var result: [DaySection] = []
        let cal = Calendar.current
        for clip in visibleClips {
            let day = cal.startOfDay(for: clip.date)
            if let last = result.indices.last, result[last].id == day {
                result[last].clips.append(clip)
            } else {
                result.append(DaySection(id: day, clips: [clip]))
            }
        }
        return result
    }

    /// Clip del tipo mostrato (video/foto), importate o no.
    var filteredClips: [Clip] { clips.filter(mediaFilter.includes) }
    var newClips: [Clip] { filteredClips.filter { !isImported($0) } }
    var hasVideos: Bool { clips.contains { !$0.isPhoto } }
    var hasPhotos: Bool { clips.contains(where: \.isPhoto) }

    var summaryText: String {
        let total = clips.reduce(Int64(0)) { $0 + $1.importSize }
        let fresh = clips.filter { !isImported($0) }.count
        var parts = [Fmt.items(clips)]
        parts.append(fresh == 1 ? L("1 new") : L("{0} new", fresh))
        parts.append(Fmt.bytes(total))
        return parts.joined(separator: " · ")
    }

    func flag(_ clip: Clip) -> Flag? { flags[ImportedStore.key(clip)] }
    func isRejected(_ clip: Clip) -> Bool { flag(clip) == .reject }

    /// Se ci sono clip nuove segnate ✔️, senza selezione il pulsante importa solo quelle.
    var usingPicks: Bool { selection.isEmpty && newClips.contains { flag($0) == .pick } }

    /// Cosa importa il pulsante: la selezione, oppure (senza selezione) le nuove scelte ✔️ se ce ne sono,
    /// altrimenti tutte le nuove. Le scartate ✖️ non si importano mai.
    var clipsToImport: [Clip] {
        let list: [Clip]
        if selection.isEmpty {
            list = usingPicks ? newClips.filter { flag($0) == .pick } : newClips
        } else {
            list = clips.filter { selection.contains($0.id) }.sorted { $0.date < $1.date }
        }
        return list.filter { !isRejected($0) }
    }

    var rejectedCount: Int { filteredClips.filter(isRejected).count }

    // MARK: - Etichette (P / X / U, come in Lightroom)

    func flagSelection(_ f: Flag?) {
        let list = selectedClips
        guard !list.isEmpty else { NSSound.beep(); return }
        for clip in list {
            let key = ImportedStore.key(clip)
            // Premere di nuovo lo stesso tasto toglie l'etichetta
            if list.count == 1, flags[key] == f { flags[key] = nil } else { flags[key] = f }
        }
        FlagStore.save(flags)
    }

    /// Dai bottoncini sulla miniatura: se la clip è selezionata agisce su tutta la selezione,
    /// altrimenti solo su di lei. Ricliccare la stessa etichetta la toglie.
    func toggleFlag(_ f: Flag, on clip: Clip) {
        if selection.contains(clip.id) && selection.count > 1 {
            flagSelection(flag(clip) == f ? nil : f)
            return
        }
        let key = ImportedStore.key(clip)
        flags[key] = flags[key] == f ? nil : f
        FlagStore.save(flags)
    }

    func setFlag(_ f: Flag?, on clip: Clip) {
        if selection.contains(clip.id) && selection.count > 1 { flagSelection(f); return }
        flags[ImportedStore.key(clip)] = f
        FlagStore.save(flags)
    }

    /// Riga sotto il nome della sorgente: con una selezione, ricorda i tasti utili.
    var statusText: String {
        let n = selectedClips.count
        guard n > 0 else { return summaryText }
        let sel = n == 1 ? L("1 selected") : L("{0} selected", n)
        return sel + L(" · P pick · X reject · U unflag · Space preview · ⌘⌫ delete")
    }

    func selectFlagged(_ f: Flag) {
        selection = Set(visibleClips.filter { flag($0) == f }.map(\.id))
        anchor = nil
    }

    /// Frecce ← →: passa alla clip precedente/successiva (⇧ allarga la selezione).
    func moveSelection(by step: Int, extend: Bool) {
        let list = visibleClips
        guard !list.isEmpty else { return }
        let from = anchor.flatMap { a in list.firstIndex { $0.id == a } }
            ?? (step > 0 ? list.lastIndex { selection.contains($0.id) } : list.firstIndex { selection.contains($0.id) })
        let target: Int
        if let from { target = min(max(from + step, 0), list.count - 1) } else { target = step > 0 ? 0 : list.count - 1 }
        let id = list[target].id
        if extend { selection.insert(id) } else { selection = [id] }
        anchor = id
        scrollTarget = id
    }

    func deleteRejected() {
        selection = Set(visibleClips.filter(isRejected).map(\.id))
        guard !selection.isEmpty else { NSSound.beep(); return }
        deleteSelection()
    }

    /// Il prossimo clic sul pulsante sposterà (copia + verifica + cancella dalla sorgente)?
    var willMove: Bool { deleteAfter != optionHeld }

    /// "dalla scheda" / "dalla cartella"
    var sourcePlace: String { (current?.isVolume ?? true) ? L("from the card") : L("from the folder") }

    var importButtonTitle: String {
        let list = clipsToImport
        let size = Fmt.bytes(list.reduce(Int64(0)) { $0 + $1.importSize })
        if selection.isEmpty {
            if list.isEmpty { return L("Nothing new to import") }
            let move = willMove
            if list.count == 1 {
                let photo = list[0].isPhoto
                switch (move, usingPicks, photo) {
                case (false, false, false): return L("Import the new clip · {0}", size)
                case (false, false, true):  return L("Import the new photo · {0}", size)
                case (false, true, false):  return L("Import the picked clip · {0}", size)
                case (false, true, true):   return L("Import the picked photo · {0}", size)
                case (true, false, false):  return L("Move the new clip · {0}", size)
                case (true, false, true):   return L("Move the new photo · {0}", size)
                case (true, true, false):   return L("Move the picked clip · {0}", size)
                case (true, true, true):    return L("Move the picked photo · {0}", size)
                }
            }
            switch (move, usingPicks) {
            case (false, false): return L("Import {0} new · {1}", list.count, size)
            case (false, true):  return L("Import {0} picked · {1}", list.count, size)
            case (true, false):  return L("Move {0} new · {1}", list.count, size)
            case (true, true):   return L("Move {0} picked · {1}", list.count, size)
            }
        }
        return willMove ? L("Move {0} · {1}", Fmt.items(list), size) : L("Import {0} · {1}", Fmt.items(list), size)
    }

    var destinationDisplay: String { (destinationPath as NSString).abbreviatingWithTildeInPath }

    var destinationPreview: String {
        let options = currentOptions
        guard let clip = clipsToImport.first ?? clips.first else { return "" }
        let folder = Importer.folder(for: clip, options: options, now: Date())
        var parts = [options.destRoot.lastPathComponent]
        if folder.path != options.destRoot.path { parts.append(folder.lastPathComponent) }
        parts.append(Importer.targetName(for: clip, options: options))
        return parts.joined(separator: " › ")
    }

    private var currentOptions: ImportOptions {
        ImportOptions(destRoot: URL(fileURLWithPath: destinationPath, isDirectory: true),
                      folderMode: folderMode, customName: customFolderName,
                      copySidecar: copySidecar, copyProxy: copyProxy, renameWithDate: renameWithDate)
    }

    // MARK: - Schede e cartelle

    func volumeMounted(_ url: URL, showWindow: Bool) {
        Task { @MainActor in
            let isCard = await Task.detached(priority: .userInitiated) { CardScanner.isCameraCard(url) }.value
            guard isCard else { return }
            let source = Source(id: url, name: CardScanner.volumeName(url), isVolume: true)
            if !sources.contains(where: { $0.id.path == url.path }) { sources.append(source) }
            if progress == nil { open(source) }
            if showWindow && autoOpen { onWantsWindow?() }
        }
    }

    func volumeUnmounted(_ url: URL) {
        sources.removeAll { $0.id.path == url.path }
        if current?.id.path == url.path {
            current = nil
            clips = []
            selection = []
            watcher = nil
            if let next = orderedSources.first { open(next) }
        }
    }

    func open(_ source: Source) {
        current = source
        openGeneration = UUID()
        clips = []
        selection = []
        anchor = nil
        scanning = true
        pendingRescan = false
        let url = source.id
        if !source.isVolume { rememberFolder(url) }

        // Schede e cartelle vengono sorvegliate: le clip nuove compaiono da sole, quelle spostate
        // via dal Finder (⌥⌘V) spariscono da sole
        watcher = FolderWatcher(url: url) { [weak self] in
            Task { @MainActor in self?.scheduleRescan() }
        }

        let deep = !source.isVolume
        Task { @MainActor in
            let found = await Task.detached(priority: .userInitiated) { CardScanner.scan(url, deep: deep) }.value
            guard current?.id == url else { return }
            clips = found
            scanning = false
        }
    }

    /// Rilegge la sorgente attuale senza perdere la selezione.
    func refresh() {
        guard let source = current, !scanning else { return }
        guard progress == nil else { pendingRescan = true; return }
        let url = source.id
        let deep = !source.isVolume
        if !FileManager.default.fileExists(atPath: url.path) {
            if !source.isVolume { removeSource(source) }
            return
        }
        Task { @MainActor in
            let found = await Task.detached(priority: .userInitiated) { CardScanner.scan(url, deep: deep) }.value
            guard current?.id == url else { return }
            let ids = Set(found.map(\.id))
            clips = found
            selection.formIntersection(ids)
            if let a = anchor, !ids.contains(a) { anchor = nil }
        }
    }

    /// Attende che le modifiche si calmino (es. una copia in corso) prima di rileggere.
    private func scheduleRescan() {
        let token = UUID()
        rescanToken = token
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard rescanToken == token else { return }
            refresh()
        }
    }

    private func rememberFolder(_ url: URL) {
        var list = recentFolders.filter { $0 != url.path }
        list.insert(url.path, at: 0)
        recentFolders = list
    }

    /// Toglie una cartella dall'elenco (non cancella niente dal disco).
    func removeSource(_ source: Source) {
        guard !source.isVolume, progress == nil else { return }
        sources.removeAll { $0.id.path == source.id.path }
        recentFolders = recentFolders.filter { $0 != source.id.path }
        if current?.id.path == source.id.path {
            current = nil
            clips = []
            selection = []
            watcher = nil
            if let next = orderedSources.first { open(next) }
        }
    }

    func chooseSourceFolder() {
        guard progress == nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("Show clips")
        panel.message = L("Choose a card or a folder that contains video clips or photos")
        if let start = (current.flatMap { $0.isVolume ? nil : $0.id }) ?? recentFolders.first.map({ URL(fileURLWithPath: $0) }) {
            panel.directoryURL = start
        }
        // Dalla barra dei menu l'app è in secondo piano: senza questo la finestra finisce dietro le altre
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let source = sources.first(where: { $0.id.standardizedFileURL.path == url.standardizedFileURL.path })
            ?? Source(id: url, name: url.lastPathComponent, isVolume: false)
        if !sources.contains(source) { sources.append(source) }
        open(source)
        onWantsWindow?()
    }

    func revealCurrent() {
        guard let url = current?.id else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("Use this folder")
        panel.message = L("Choose where to import your clips")
        panel.directoryURL = URL(fileURLWithPath: destinationPath)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destinationPath = url.path
    }

    func eject() {
        guard let source = current, source.isVolume else { return }
        guard progress == nil else { return }
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: source.id)
        } catch {
            alert(L("Couldn't eject “{0}”", source.name),
                  L("Quit the apps that are using the card and try again.")
                  + "\n\n\(error.localizedDescription)")
        }
    }

    // MARK: - Selezione

    /// Clic sulla miniatura, come nel Finder: ⌘ aggiunge/toglie, ⇧ seleziona un intervallo,
    /// doppio clic riproduce la clip.
    func click(_ clip: Clip) {
        if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
            NSWorkspace.shared.open(clip.url)
            return
        }
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            toggle(clip)
        } else if flags.contains(.shift), let anchor {
            let list = visibleClips
            if let a = list.firstIndex(where: { $0.id == anchor }),
               let b = list.firstIndex(where: { $0.id == clip.id }) {
                selection.formUnion(list[min(a, b)...max(a, b)].map(\.id))
            } else {
                selection = [clip.id]
                self.anchor = clip.id
            }
        } else if selection == [clip.id] {
            // Riclic sull'unica selezionata: la deseleziona
            selection = []
            anchor = nil
        } else {
            selection = [clip.id]
            anchor = clip.id
        }
    }

    func toggle(_ clip: Clip) {
        if selection.contains(clip.id) { selection.remove(clip.id) } else { selection.insert(clip.id) }
        anchor = clip.id
    }

    func selectAll() { selection = Set(visibleClips.map(\.id)) }
    func selectNew() { selection = Set(visibleClips.filter { !isImported($0) && !isRejected($0) }.map(\.id)) }
    func selectNone() { selection = []; anchor = nil }

    func isDaySelected(_ section: DaySection) -> Bool {
        section.clips.allSatisfy { selection.contains($0.id) }
    }

    func toggleDay(_ section: DaySection) {
        let ids = section.clips.map(\.id)
        if isDaySelected(section) { selection.subtract(ids) } else { selection.formUnion(ids) }
    }

    func setImported(_ clip: Clip, _ imported: Bool) {
        let key = ImportedStore.key(clip)
        if imported { importedKeys.insert(key) } else { importedKeys.remove(key) }
        ImportedStore.save(importedKeys)
    }

    // MARK: - Appunti ed eliminazione (come nel Finder)

    /// Gli elementi su cui agiscono ⌘C, ⌫, spazio: la selezione, nell'ordine in cui si vede.
    var selectedClips: [Clip] { visibleClips.filter { selection.contains($0.id) } }

    /// ⌘C: mette i file negli appunti, da incollare nel Finder (o in DaVinci Resolve) con ⌘V.
    func copySelection() {
        let list = selectedClips
        guard !list.isEmpty else { NSSound.beep(); return }
        // Il RAW va sempre con il suo JPEG; l'XML Sony solo se si è scelto di copiarlo
        let urls = list.flatMap { [$0.url] + $0.companions + (copySidecar ? [$0.sidecarURL].compactMap { $0 } : []) }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
        showBanner(L("{0} copied · in Finder ⌘V copies, ⌥⌘V moves", Fmt.items(list)))
    }

    /// ⌘⌫ (o ⌫): dalla scheda elimina per sempre, dalle cartelle sposta nel Cestino.
    /// Insieme alla clip spariscono XML, miniatura, proxy e RAW abbinato.
    func deleteSelection() {
        let list = selectedClips
        guard !list.isEmpty, progress == nil, let source = current else { NSSound.beep(); return }
        if source.isVolume {
            let notImported = list.filter { !isImported($0) }.count
            let a = NSAlert()
            a.alertStyle = .warning
            a.messageText = list.count == 1
                ? L("Delete “{0}” from the card?", list[0].name)
                : L("Delete {0} from the card?", Fmt.items(list))
            var info = L("Related files (XML, thumbnail, proxy, RAW) are deleted too. This can't be undone.")
            if notImported > 0 {
                info = (notImported == list.count
                        ? (list.count == 1 ? L("⚠️ It hasn't been imported yet.\n\n")
                                           : L("⚠️ None of them has been imported yet.\n\n"))
                        : L("⚠️ {0} haven't been imported yet.\n\n", notImported)) + info
            }
            a.informativeText = info
            let del = a.addButton(withTitle: L("Delete"))
            let cancel = a.addButton(withTitle: L("Cancel"))
            if #available(macOS 11.0, *) { del.hasDestructiveAction = true }
            if notImported > 0 {
                // Se si perde qualcosa di mai importato, Invio annulla
                del.keyEquivalent = ""
                cancel.keyEquivalent = "\r"
            }
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        let mode: DeleteMode = source.isVolume ? .permanent : .trash
        var deleted: [Clip] = []
        var failures: [String] = []
        var sony: [URL: [String]] = [:]
        for clip in list {
            do {
                try Importer.deleteOriginals(of: clip, mode: mode)
                deleted.append(clip)
                let dir = clip.url.deletingLastPathComponent()
                if dir.lastPathComponent.uppercased() == "CLIP" {
                    sony[dir.deletingLastPathComponent(), default: []].append(clip.name)
                }
            } catch {
                failures.append("• \(clip.name): \(error.localizedDescription)")
            }
        }
        for (root, names) in sony { SonyIndex.remove(names, from: root) }
        let gone = Set(deleted.map(\.id))
        clips.removeAll { gone.contains($0.id) }
        selection.subtract(gone)
        if !deleted.isEmpty {
            NSSound(named: source.isVolume ? "Funk" : "Pop")?.play()
            showBanner(source.isVolume ? L("{0} deleted from the card", Fmt.items(deleted))
                                       : L("{0} moved to the Trash", Fmt.items(deleted)))
        }
        if !failures.isEmpty {
            alert(L("Some files couldn't be deleted"), failures.prefix(10).joined(separator: "\n"))
        }
    }

    // MARK: - Importazione

    func startImport() { importClips(clipsToImport, move: willMove) }

    /// ⌥⌘I: importa e cancella dalla sorgente, qualunque sia l'impostazione.
    func startMove() { importClips(clipsToImport, move: true) }

    func importClips(_ list: [Clip], move: Bool? = nil) {
        guard !list.isEmpty, progress == nil else { return }
        let move = move ?? deleteAfter
        var options = currentOptions
        if move {
            guard confirmMoveOnce(list) else { return }
            // Sulla scheda il Cestino non libera spazio: si cancella. Dalle cartelle del Mac, nel Cestino.
            options.deleteOriginals = (current?.isVolume ?? false) ? .permanent : .trash
        }

        if folderMode == .custom && Importer.sanitize(customFolderName).isEmpty {
            alert(L("Folder name missing"),
                  L("Type a folder name at the bottom, or pick another option under “Organize”."))
            return
        }
        let needed = list.reduce(Int64(0)) { $0 + $1.importSize + (copyProxy ? ($1.proxySize ?? 0) : 0) }
        if let free = Importer.freeSpace(at: options.destRoot), free < needed {
            alert(L("Not enough space"),
                  L("{0} needed, but the destination only has {1} free.", Fmt.bytes(needed), Fmt.bytes(free)))
            return
        }

        let job = UUID()
        let flag = CancelFlag()
        activeJob = job
        cancelFlag = flag
        progress = ImportProgress(fileIndex: 0, fileCount: list.count, currentName: list[0].name,
                                  bytesDone: 0, bytesTotal: needed, startedAt: Date())
        optionHeld = false
        let volume: URL? = (current?.isVolume ?? false) ? current?.id : nil

        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                Importer.run(list, options: options, cancel: flag) { p in
                    Task { @MainActor in AppState.shared.applyProgress(p, job: job) }
                }
            }.value
            finishImport(result, volume: volume)
        }
    }

    func applyProgress(_ p: ImportProgress, job: UUID) {
        guard activeJob == job else { return }
        progress = p
    }

    func cancelImport() { cancelFlag?.cancel() }

    private func finishImport(_ r: ImportResult, volume: URL?) {
        activeJob = nil
        cancelFlag = nil
        progress = nil
        if pendingRescan || !r.deleted.isEmpty { pendingRescan = false; refresh() }

        let done = r.imported + r.skipped
        for clip in done { importedKeys.insert(ImportedStore.key(clip)) }
        ImportedStore.save(importedKeys)
        selection.subtract(done.map(\.id))

        var message: String
        if r.cancelled {
            message = L("Import cancelled · {0} copied", Fmt.items(r.imported))
        } else {
            message = L("Imported: {0}", Fmt.items(r.imported))
            if !r.skipped.isEmpty { message += L(" · {0} were already there", r.skipped.count) }
        }
        if !r.deleted.isEmpty {
            let freed = r.deleted.reduce(Int64(0)) { $0 + $1.importSize + ($1.proxySize ?? 0) }
            message += L(" · {0} freed {1}", Fmt.bytes(freed), sourcePlace)
        }
        showBanner(message)
        NSSound(named: "Glass")?.play()

        if !r.failed.isEmpty {
            let lines = r.failed.prefix(10).map { "• \($0.clip.name): \($0.message)" }
            alert(L("Some items weren't imported"), lines.joined(separator: "\n"))
        }
        if !r.deleteFailures.isEmpty {
            let lines = r.deleteFailures.prefix(10).map { "• \($0.clip.name): \($0.message)" }
            alert(L("Imported, but not deleted {0}", sourcePlace),
                  L("The copies are safe; the originals were left where they were.")
                  + "\n\n" + lines.joined(separator: "\n"))
        }
        if revealAfter, !r.cancelled, !r.files.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(r.files)
        }
        if ejectAfter, !r.cancelled, r.failed.isEmpty, let volume {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: volume)
            } catch {
                alert(L("Imported, but the card couldn't be ejected"), error.localizedDescription)
            }
        }
    }

    // MARK: - Messaggi

    /// La prima volta che si sposta, spiega cosa succede (con "Non chiedere più").
    private func confirmMoveOnce(_ list: [Clip]) -> Bool {
        guard !defaults.bool(forKey: "moveConfirmed") else { return true }
        let a = NSAlert()
        let toTrash = !(current?.isVolume ?? true)
        let trashNote = toTrash ? L(" (moved to the Trash)") : ""
        a.messageText = L("Move {0} {1}?", Fmt.items(list), sourcePlace)
        a.informativeText = L("Each file is copied, read back from the destination and compared byte by byte with the original. Only if it's identical is the original deleted {0}{1}.\n\nIf anything goes wrong, or you cancel, the original stays where it is.", sourcePlace, trashNote)
        a.addButton(withTitle: L("Move"))
        a.addButton(withTitle: L("Cancel"))
        a.showsSuppressionButton = true
        a.suppressionButton?.title = L("Don't ask again")
        let ok = a.runModal() == .alertFirstButtonReturn
        if ok && a.suppressionButton?.state == .on { defaults.set(true, forKey: "moveConfirmed") }
        return ok
    }

    func showBanner(_ text: String) {
        let token = UUID()
        bannerToken = token
        withAnimation(.easeInOut(duration: 0.25)) { banner = text }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard bannerToken == token else { return }
            withAnimation(.easeInOut(duration: 0.25)) { banner = nil }
        }
    }

    func alert(_ title: String, _ message: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: "OK")
        a.runModal()
    }
}
