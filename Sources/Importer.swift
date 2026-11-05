import CryptoKit
import Foundation

/// Copia delle clip nella destinazione, con avanzamento e annullamento.
enum Importer {
    static func folder(for clip: Clip, options o: ImportOptions, now: Date) -> URL {
        switch o.folderMode {
        case .flat:
            return o.destRoot
        case .byShootDay:
            return o.destRoot.appendingPathComponent(dayString(clip.date), isDirectory: true)
        case .byImportDay:
            return o.destRoot.appendingPathComponent(dayString(now), isDirectory: true)
        case .custom:
            let name = sanitize(o.customName)
            return name.isEmpty ? o.destRoot : o.destRoot.appendingPathComponent(name, isDirectory: true)
        }
    }

    static func targetName(for clip: Clip, options o: ImportOptions) -> String {
        guard o.renameWithDate else { return clip.name }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "\(f.string(from: clip.date))_\(clip.name)"
    }

    static func dayString(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    static func sanitize(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func freeSpace(at url: URL) -> Int64? {
        var probe = url
        while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 {
            probe = probe.deletingLastPathComponent()
        }
        // «ImportantUsage» su dischi esterni non APFS (ExFAT, HFS+) vale 0: va confrontato con lo
        // spazio libero classico e si prende il valore più alto. Se nessuno è affidabile, nessun blocco.
        let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                         .volumeAvailableCapacityKey])
        let statfs = (try? FileManager.default.attributesOfFileSystem(forPath: probe.path))?[.systemFreeSize] as? NSNumber
        let candidates: [Int64?] = [values?.volumeAvailableCapacityForImportantUsage,
                                    values?.volumeAvailableCapacity.map(Int64.init),
                                    statfs?.int64Value]
        guard let best = candidates.compactMap({ $0 }).max(), best > 0 else { return nil }
        return best
    }

    static func fileSize(_ url: URL) -> Int64? {
        guard let s = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return nil }
        return Int64(s)
    }

    static func uniqueURL(_ url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 2
        while true {
            let candidate = dir.appendingPathComponent("\(base) (\(n))").appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    static func run(_ clips: [Clip], options o: ImportOptions, cancel: CancelFlag,
                    progress: @escaping @Sendable (ImportProgress) -> Void) -> ImportResult {
        let fm = FileManager.default
        var result = ImportResult()
        let start = Date()
        let moving = o.deleteOriginals != .keep
        // Spostando, ogni file viene anche riletto dalla destinazione per verificarlo: il doppio dei byte
        let total = clips.reduce(Int64(0)) {
            $0 + $1.importSize * (moving ? 2 : 1) + (o.copyProxy ? ($1.proxySize ?? 0) : 0)
        }
        var sonyIndexRemovals: [URL: [String]] = [:]    // M4ROOT → nomi delle clip da togliere da MEDIAPRO.XML
        var done: Int64 = 0
        var lastReport = Date.distantPast
        var current = ImportProgress(fileIndex: 0, fileCount: clips.count, currentName: "",
                                     bytesDone: 0, bytesTotal: total, startedAt: start)

        func report(force: Bool = false) {
            let now = Date()
            guard force || now.timeIntervalSince(lastReport) > 0.15 else { return }
            lastReport = now
            current.bytesDone = done
            progress(current)
        }

        for (index, clip) in clips.enumerated() {
            if cancel.isCancelled { result.cancelled = true; break }
            current.fileIndex = index
            current.currentName = clip.name
            current.verb = "Importazione di"
            report(force: true)
            var extrasOK = true     // XML e proxy richiesti copiati davvero (se no l'originale non si cancella)
            var verifiedPairs: [(src: URL, dst: URL)] = []

            let folder = self.folder(for: clip, options: o, now: start)
            let proxyBytes = o.copyProxy ? (clip.proxySize ?? 0) : 0
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                var dst = folder.appendingPathComponent(targetName(for: clip, options: o))

                if fm.fileExists(atPath: dst.path), fileSize(dst) == clip.size,
                   try !moving || sameContents(clip.url, dst, cancel: cancel, onBytes: { n in done += n; report() }) {
                    // Stesso file già presente: non lo ricopio (ma completo l'eventuale RAW mancante)
                    if !moving { done += clip.size }
                    current.verb = "Importazione di"
                    let pairs = try copyCompanions(of: clip, base: dst.deletingPathExtension().lastPathComponent,
                                                   in: folder, verify: moving, cancel: cancel) { n in done += n; report() }
                    verifiedPairs = [(clip.url, dst)] + pairs
                    result.skipped.append(clip)
                    result.files.append(dst)
                } else {
                    if fm.fileExists(atPath: dst.path) { dst = uniqueURL(dst) }

                    let hash = try copyFile(clip.url, to: dst, hashing: moving, cancel: cancel) { n in done += n; report() }
                    if moving {
                        current.verb = "Verifica di"
                        try verify(dst, expected: hash, cancel: cancel) { n in done += n; report() }
                        current.verb = "Importazione di"
                    }
                    let dstBase = dst.deletingPathExtension().lastPathComponent
                    // RAW abbinato al JPEG: stesso nome, così restano accoppiati in Lightroom/Capture One
                    let pairs = try copyCompanions(of: clip, base: dstBase, in: folder, verify: moving,
                                                   cancel: cancel) { n in done += n; report() }
                    verifiedPairs = [(clip.url, dst)] + pairs
                    result.imported.append(clip)
                    result.files.append(dst)

                    if o.copySidecar, let xml = clip.sidecarURL {
                        let xmlDst = folder.appendingPathComponent("\(dstBase)M01.\(xml.pathExtension)")
                        if !fm.fileExists(atPath: xmlDst.path) {
                            do { try fm.copyItem(at: xml, to: xmlDst) } catch { extrasOK = false }
                        }
                    }
                }
                let dstBase = verifiedPairs[0].dst.deletingPathExtension().lastPathComponent

                if o.copyProxy, let proxy = clip.proxyURL {
                    // Stesso nome dell'originale dentro "Proxy": DaVinci Resolve li collega da solo
                    let proxyDir = folder.appendingPathComponent("Proxy", isDirectory: true)
                    let proxyDst = proxyDir.appendingPathComponent(dstBase).appendingPathExtension(proxy.pathExtension)
                    do {
                        try fm.createDirectory(at: proxyDir, withIntermediateDirectories: true)
                        if fm.fileExists(atPath: proxyDst.path) {
                            done += proxyBytes
                        } else {
                            try copyFile(proxy, to: proxyDst, cancel: cancel) { n in done += n; report() }
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // Un proxy mancante non blocca l'importazione della clip (ma la clip resta sulla scheda)
                        extrasOK = false
                    }
                }

                // Copia verificata: ora (e solo ora) si cancellano gli originali
                if moving && !cancel.isCancelled {
                    guard extrasOK else {
                        result.deleteFailures.append(ImportFailure(clip: clip,
                            message: "copiata, ma XML o proxy non sono stati copiati: lasciata sulla scheda"))
                        continue
                    }
                    // Mai cancellare se origine e destinazione sono lo stesso file
                    if verifiedPairs.contains(where: { sameFile($0.src, $0.dst) }) { continue }
                    current.verb = "Cancellazione di"
                    report(force: true)
                    do {
                        try deleteOriginals(of: clip, mode: o.deleteOriginals)
                        result.deleted.append(clip)
                        let clipDir = clip.url.deletingLastPathComponent()
                        if clipDir.lastPathComponent.uppercased() == "CLIP" {
                            sonyIndexRemovals[clipDir.deletingLastPathComponent(), default: []].append(clip.name)
                        }
                    } catch {
                        result.deleteFailures.append(ImportFailure(clip: clip, message: error.localizedDescription))
                    }
                }
            } catch is CancellationError {
                result.cancelled = true
                break
            } catch {
                result.failed.append(ImportFailure(clip: clip, message: error.localizedDescription))
            }
        }
        for (root, names) in sonyIndexRemovals { SonyIndex.remove(names, from: root) }
        report(force: true)
        return result
    }

    // MARK: - Verifica e cancellazione

    struct VerifyError: LocalizedError {
        var errorDescription: String? { "la copia non corrisponde all'originale (verifica fallita): l'originale non è stato toccato" }
    }

    /// Rilegge la copia dal disco (senza cache) e ne confronta l'impronta SHA-256.
    static func verify(_ dst: URL, expected: SHA256.Digest?, cancel: CancelFlag, onBytes: (Int64) -> Void) throws {
        let actual = try hashFile(dst, cancel: cancel, onBytes: onBytes)
        guard let expected, actual == expected else {
            try? FileManager.default.removeItem(at: dst)     // copia difettosa: via
            throw VerifyError()
        }
    }

    /// Il file nella destinazione è identico all'originale? (per i file "già presenti")
    static func sameContents(_ a: URL, _ b: URL, cancel: CancelFlag, onBytes: (Int64) -> Void) throws -> Bool {
        if sameFile(a, b) { return true }
        return try hashFile(a, cancel: cancel, onBytes: onBytes) == hashFile(b, cancel: cancel, onBytes: onBytes)
    }

    static func hashFile(_ url: URL, cancel: CancelFlag, onBytes: (Int64) -> Void) throws -> SHA256.Digest {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        _ = fcntl(h.fileDescriptor, F_NOCACHE, 1)      // legge davvero dal disco, non dalla RAM
        var hasher = SHA256()
        while true {
            if cancel.isCancelled { throw CancellationError() }
            let data: Data = try autoreleasepool { try h.read(upToCount: 8 * 1024 * 1024) ?? Data() }
            if data.isEmpty { break }
            hasher.update(data: data)
            onBytes(Int64(data.count))
        }
        return hasher.finalize()
    }

    static func sameFile(_ a: URL, _ b: URL) -> Bool {
        if a.standardizedFileURL.resolvingSymlinksInPath().path == b.standardizedFileURL.resolvingSymlinksInPath().path { return true }
        let ia = try? a.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        let ib = try? b.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        if let ia, let ib { return ia.isEqual(ib) }
        return false
    }

    /// Cancella la clip e tutto ciò che la accompagna sulla scheda (RAW, XML, miniatura, proxy).
    static func deleteOriginals(of clip: Clip, mode: DeleteMode) throws {
        let fm = FileManager.default
        let main = [clip.url] + clip.companions
        let extras = [clip.sidecarURL, clip.thumbnailURL, clip.proxyURL].compactMap { $0 }
        func remove(_ u: URL) throws {
            guard fm.fileExists(atPath: u.path) else { return }
            if mode == .trash { try fm.trashItem(at: u, resultingItemURL: nil) } else { try fm.removeItem(at: u) }
        }
        do {
            for u in main { try remove(u) }
        } catch {
            if (error as NSError).code == NSFileWriteVolumeReadOnlyError || (error as NSError).code == NSFileWriteNoPermissionError {
                throw CocoaError(.fileWriteVolumeReadOnly, userInfo: [NSLocalizedDescriptionKey:
                    "la scheda è protetta da scrittura (controlla la levetta LOCK sul lato della SD)"])
            }
            throw error
        }
        for u in extras { try? remove(u) }
    }

    /// Copia i file abbinati (es. .ARW) accanto al principale, con lo stesso nome base.
    /// Restituisce le coppie origine → copia (verificate, se `verify`).
    @discardableResult
    static func copyCompanions(of clip: Clip, base: String, in folder: URL, verify mustVerify: Bool,
                               cancel: CancelFlag, onBytes: (Int64) -> Void) throws -> [(src: URL, dst: URL)] {
        var pairs: [(src: URL, dst: URL)] = []
        for src in clip.companions {
            let dst = folder.appendingPathComponent(base).appendingPathExtension(src.pathExtension)
            let size = fileSize(src) ?? 0
            if FileManager.default.fileExists(atPath: dst.path), fileSize(dst) == size {
                if mustVerify {
                    guard try sameContents(src, dst, cancel: cancel, onBytes: onBytes) else {
                        throw CocoaError(.fileWriteFileExists, userInfo: [NSLocalizedDescriptionKey:
                            "nella destinazione c'è già un \(dst.lastPathComponent) diverso"])
                    }
                } else {
                    onBytes(size)
                }
            } else {
                let hash = try copyFile(src, to: dst, hashing: mustVerify, cancel: cancel, onBytes: onBytes)
                if mustVerify { try verify(dst, expected: hash, cancel: cancel, onBytes: onBytes) }
            }
            pairs.append((src, dst))
        }
        return pairs
    }

    /// Copia a blocchi da 8 MB su un file temporaneo nascosto, poi lo rinomina.
    /// Così una copia interrotta non lascia mai un file "buono a metà".
    /// Con `hashing` calcola durante la copia l'impronta SHA-256 dei byte letti dall'originale.
    @discardableResult
    static func copyFile(_ src: URL, to dst: URL, hashing: Bool = false, cancel: CancelFlag,
                         onBytes: (Int64) -> Void) throws -> SHA256.Digest? {
        let fm = FileManager.default
        let tmp = dst.deletingLastPathComponent().appendingPathComponent(".\(dst.lastPathComponent).part")
        try? fm.removeItem(at: tmp)
        guard fm.createFile(atPath: tmp.path, contents: nil) else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: tmp.path])
        }

        let input = try FileHandle(forReadingFrom: src)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: tmp)
        if hashing { _ = fcntl(output.fileDescriptor, F_NOCACHE, 1) }   // la verifica deve rileggere dal disco
        var hasher = hashing ? SHA256() : nil
        var completed = false
        defer {
            try? output.close()
            if !completed { try? fm.removeItem(at: tmp) }
        }

        let chunkSize = 8 * 1024 * 1024
        while true {
            if cancel.isCancelled { throw CancellationError() }
            let data: Data = try autoreleasepool { try input.read(upToCount: chunkSize) ?? Data() }
            if data.isEmpty { break }
            hasher?.update(data: data)
            try output.write(contentsOf: data)
            onBytes(Int64(data.count))
        }
        try output.synchronize()
        try fm.moveItem(at: tmp, to: dst)
        completed = true

        // Mantiene le date originali della clip
        if let attrs = try? fm.attributesOfItem(atPath: src.path) {
            var keep: [FileAttributeKey: Any] = [:]
            if let c = attrs[.creationDate] { keep[.creationDate] = c }
            if let m = attrs[.modificationDate] { keep[.modificationDate] = m }
            try? fm.setAttributes(keep, ofItemAtPath: dst.path)
        }
        return hasher?.finalize()
    }
}

/// Indice delle clip delle Sony XAVC (PRIVATE/M4ROOT/MEDIAPRO.XML).
/// Quando si cancellano clip dal computer va aggiornato, altrimenti la fotocamera trova voci orfane
/// e chiede di riparare il database. Si tolgono solo i blocco <Material> delle clip cancellate,
/// lasciando il resto del file identico byte per byte.
enum SonyIndex {
    static func remove(_ clipNames: [String], from m4root: URL) {
        let url = m4root.appendingPathComponent("MEDIAPRO.XML")
        guard let data = try? Data(contentsOf: url), var xml = String(data: data, encoding: .utf8) else { return }
        let original = xml
        for name in clipNames {
            let escaped = NSRegularExpression.escapedPattern(for: name)
            let pattern = #"[ \t]*<Material\s+uri="\./CLIP/"# + escaped + #""[^>]*?(?:/>|>.*?</Material>)[ \t]*\r?\n?"#
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
            else { continue }
            xml = re.stringByReplacingMatches(in: xml, range: NSRange(xml.startIndex..., in: xml), withTemplate: "")
        }
        guard xml != original, xml.contains("</MediaProfile>") else { return }
        try? Data(xml.utf8).write(to: url, options: .atomic)
    }
}

/// Ricorda quali clip sono già state importate (anche dopo aver tolto e reinserito la scheda).
enum ImportedStore {
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Clip Importer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("imported.json")
    }

    static func key(_ clip: Clip) -> String {
        "\(clip.name.uppercased())|\(clip.size)|\(Int(clip.date.timeIntervalSince1970))"
    }

    static func load() -> Set<String> {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(list)
    }

    static func save(_ keys: Set<String>) {
        guard let data = try? JSONEncoder().encode(keys.sorted()) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Etichette ✔️/✖️, ricordate anche togliendo e reinserendo la scheda.
enum FlagStore {
    static var fileURL: URL { ImportedStore.fileURL.deletingLastPathComponent().appendingPathComponent("flags.json") }

    static func load() -> [String: Flag] {
        guard let data = try? Data(contentsOf: fileURL),
              let map = try? JSONDecoder().decode([String: Flag].self, from: data) else { return [:] }
        return map
    }

    static func save(_ flags: [String: Flag]) {
        guard let data = try? JSONEncoder().encode(flags) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Avvio automatico all'accesso tramite un LaunchAgent dell'utente.
/// L'app parte con --background: resta nella barra dei menu senza aprire finestre.
enum LoginItem {
    static let label = "com.sgnoogle.clipimporter"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    static func setEnabled(_ enabled: Bool) {
        let fm = FileManager.default
        guard enabled else { try? fm.removeItem(at: plistURL); return }
        guard let exe = Bundle.main.executablePath else { return }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [exe, "--background"],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
        ]
        try? fm.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: plistURL, options: .atomic)
        }
    }
}
