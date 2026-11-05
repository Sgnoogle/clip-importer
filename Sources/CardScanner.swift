import Foundation
import ImageIO

/// Riconosce le schede delle fotocamere e ne elenca le clip.
///
/// Strutture supportate:
/// - XAVC S / XAVC HS / XAVC S-I (Sony recenti): PRIVATE/M4ROOT/CLIP/C0001.MP4
///   con metadati C0001M01.XML, miniature in THMBNL e proxy in SUB
/// - AVCHD (Sony più vecchie): PRIVATE/AVCHD/BDMV/STREAM/00000.MTS
/// - MP4 nella cartella DCIM (vecchie Sony e altre marche)
/// - Foto in DCIM (JPEG, HEIF, RAW .ARW): RAW e JPEG con lo stesso nome diventano un solo elemento
enum CardScanner {
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "mts", "m2ts"]
    static let rawExtensions: Set<String> = ["arw", "srf", "sr2", "dng", "cr2", "cr3", "nef", "raf", "orf", "rw2"]
    static let photoExtensions: Set<String> = rawExtensions.union(["jpg", "jpeg", "hif", "heif", "heic", "png", "tif", "tiff"])

    static func volumeName(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.volumeLocalizedNameKey])
        return values?.volumeLocalizedName ?? url.lastPathComponent
    }

    static func isCameraCard(_ volume: URL) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: volume.appendingPathComponent("PRIVATE/M4ROOT").path) { return true }
        if fm.fileExists(atPath: volume.appendingPathComponent("PRIVATE/AVCHD").path) { return true }
        let dcim = volume.appendingPathComponent("DCIM")
        if fm.fileExists(atPath: dcim.path) {
            return contents(of: dcim).filter(isDirectory).contains { !contents(of: $0).filter(isMedia).isEmpty }
        }
        return false
    }

    /// `deep`: se nella struttura standard non c'è niente, cerca i video in tutte le sottocartelle
    /// (utile quando si sceglie a mano una cartella).
    static func scan(_ root: URL, deep: Bool) -> [Clip] {
        let fm = FileManager.default
        var clips: [Clip] = []

        let clipDir = root.appendingPathComponent("PRIVATE/M4ROOT/CLIP")
        if fm.fileExists(atPath: clipDir.path) {
            clips += contents(of: clipDir).filter(isVideo).map(makeClip)
        }
        let avchd = root.appendingPathComponent("PRIVATE/AVCHD/BDMV/STREAM")
        if fm.fileExists(atPath: avchd.path) {
            clips += contents(of: avchd).filter(isVideo).map(makeClip)
        }
        let dcim = root.appendingPathComponent("DCIM")
        if fm.fileExists(atPath: dcim.path) {
            clips += scanDCIM(dcim)
        }
        if clips.isEmpty && deep {
            clips = scanRecursive(root)
        }
        return clips.sorted { $0.date < $1.date }
    }

    // MARK: - Ricerca file

    private static func contents(of dir: URL) -> [URL] {
        let keys: [URLResourceKey] = [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .isDirectoryKey]
        return (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles])) ?? []
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private static func isVideo(_ url: URL) -> Bool {
        videoExtensions.contains(url.pathExtension.lowercased())
    }

    private static func isPhoto(_ url: URL) -> Bool {
        photoExtensions.contains(url.pathExtension.lowercased())
    }

    private static func isMedia(_ url: URL) -> Bool { isVideo(url) || isPhoto(url) }

    private static func scanDCIM(_ dcim: URL) -> [Clip] {
        contents(of: dcim).filter(isDirectory).flatMap { folder in
            items(from: contents(of: folder))
        }
    }

    /// Video uno per uno, foto raggruppate per nome (DSC00001.JPG + DSC00001.ARW = un elemento).
    private static func items(from urls: [URL]) -> [Clip] {
        let videos = urls.filter(isVideo).map(makeClip)
        var groups: [String: [URL]] = [:]
        for url in urls where isPhoto(url) {
            groups[url.deletingPathExtension().path.uppercased(), default: []].append(url)
        }
        return videos + groups.values.map(makePhoto)
    }

    private static func scanRecursive(_ root: URL) -> [Clip] {
        guard let e = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var found: [URL] = []
        for case let url as URL in e {
            // Le cartelle SUB contengono i proxy Sony: non sono clip da mostrare
            if url.lastPathComponent.uppercased() == "SUB", isDirectory(url) { e.skipDescendants(); continue }
            if isMedia(url) { found.append(url) }
            if found.count >= 10000 { break }
        }
        return items(from: found)
    }

    // MARK: - Costruzione della clip

    static func makeClip(_ url: URL) -> Clip {
        let fm = FileManager.default
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
        let size = Int64(values?.fileSize ?? 0)
        var date = values?.creationDate ?? values?.contentModificationDate ?? Date()
        let base = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent()
        let parent = dir.deletingLastPathComponent()

        // Metadati XML Sony
        var sidecar: URL?
        for candidate in ["\(base)M01.XML", "\(base)M01.xml", "\(base).XML", "\(base).xml"] {
            let u = dir.appendingPathComponent(candidate)
            if fm.fileExists(atPath: u.path) { sidecar = u; break }
        }

        // Miniatura già pronta
        var thumb: URL?
        for candidate in ["\(base)T01.JPG", "\(base)T01.jpg"] {
            let u = parent.appendingPathComponent("THMBNL").appendingPathComponent(candidate)
            if fm.fileExists(atPath: u.path) { thumb = u; break }
        }

        // Proxy (SUB/C0001S03.MP4)
        var proxy: URL?
        var proxySize: Int64?
        let subDir = parent.appendingPathComponent("SUB")
        if let names = try? fm.contentsOfDirectory(atPath: subDir.path),
           let name = names.first(where: { $0.uppercased().hasPrefix(base.uppercased() + "S") && $0.uppercased().hasSuffix(".MP4") }) {
            let p = subDir.appendingPathComponent(name)
            proxy = p
            proxySize = Int64((try? p.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }

        var duration: Double?
        var fps: String?
        var resolution: String?
        if let sidecar {
            let meta = parseSidecar(sidecar)
            if let d = meta.date { date = d }
            duration = meta.duration
            fps = meta.fps
            resolution = meta.resolution
        }

        return Clip(id: url, name: url.lastPathComponent, size: size, date: date, duration: duration,
                    thumbnailURL: thumb, sidecarURL: sidecar, proxyURL: proxy, proxySize: proxySize,
                    fps: fps, resolution: resolution)
    }

    // MARK: - Foto

    /// `files`: stesso nome, estensioni diverse. Il JPEG/HEIF è quello mostrato, il RAW lo accompagna.
    static func makePhoto(_ files: [URL]) -> Clip {
        let rank: (URL) -> Int = { u in
            let e = u.pathExtension.lowercased()
            if ["jpg", "jpeg"].contains(e) { return 0 }
            if ["hif", "heif", "heic"].contains(e) { return 1 }
            if rawExtensions.contains(e) { return 3 }
            return 2
        }
        let sorted = files.sorted { rank($0) < rank($1) }
        let main = sorted[0]
        let others = Array(sorted.dropFirst())
        let keys: Set<URLResourceKey> = [.fileSizeKey, .creationDateKey, .contentModificationDateKey]
        let values = try? main.resourceValues(forKeys: keys)
        let size = Int64(values?.fileSize ?? 0)
        let otherSize = others.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }

        let exif = readPhotoInfo(main)
        let date = exif.date ?? values?.creationDate ?? values?.contentModificationDate ?? Date()

        let hasRaw = files.contains { rawExtensions.contains($0.pathExtension.lowercased()) }
        let mainExt = main.pathExtension.uppercased()
        let format: String
        if hasRaw && !others.isEmpty {
            format = "RAW + " + (["JPG", "JPEG"].contains(mainExt) ? "JPEG" : mainExt == "HIF" ? "HEIF" : mainExt)
        } else if hasRaw {
            format = "RAW"
        } else {
            format = ["JPG", "JPEG"].contains(mainExt) ? "JPEG" : mainExt == "HIF" ? "HEIF" : mainExt
        }

        var clip = Clip(id: main, name: main.lastPathComponent, size: size, date: date, duration: nil,
                        thumbnailURL: nil, sidecarURL: nil, proxyURL: nil, proxySize: nil,
                        fps: nil, resolution: exif.resolution)
        clip.kind = .photo
        clip.companions = others
        clip.companionsSize = otherSize
        clip.badge = format
        return clip
    }

    /// Data di scatto e risoluzione dall'EXIF (legge solo l'intestazione del file).
    static func readPhotoInfo(_ url: URL) -> (date: Date?, resolution: String?) {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, opts),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, opts) as? [CFString: Any]
        else { return (nil, nil) }
        var date: Date?
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let s = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy:MM:dd HH:mm:ss"
            date = f.date(from: s)
        }
        var resolution: String?
        if let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
            let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
            let (a, b) = orientation >= 5 ? (h, w) : (w, h)
            resolution = "\(a)×\(b)"
        }
        return (date, resolution)
    }

    // MARK: - XML Sony (NonRealTimeMeta)

    struct SidecarInfo {
        var date: Date?
        var duration: Double?
        var fps: String?
        var resolution: String?
    }

    static func parseSidecar(_ url: URL) -> SidecarInfo {
        var info = SidecarInfo()
        guard let data = try? Data(contentsOf: url),
              let xml = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return info }

        func attribute(_ tag: String, _ name: String) -> String? {
            guard let start = xml.range(of: "<\(tag) ") else { return nil }
            let rest = xml[start.upperBound...]
            guard let end = rest.firstIndex(of: ">") else { return nil }
            let body = rest[..<end]
            guard let a = body.range(of: "\(name)=\"") else { return nil }
            let after = body[a.upperBound...]
            guard let q = after.firstIndex(of: "\"") else { return nil }
            return String(after[..<q])
        }

        if let s = attribute("CreationDate", "value") {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            if let d = iso.date(from: s) {
                info.date = d
            } else {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                info.date = f.date(from: String(s.prefix(19)))
            }
        }

        let fpsString = attribute("VideoFrame", "formatFps") ?? attribute("VideoFrame", "captureFps")
        if let fpsString {
            info.fps = fpsString
            let numeric = fpsString.filter { $0.isNumber || $0 == "." }
            if var rate = Double(numeric), rate > 0 {
                if fpsString.lowercased().hasSuffix("i") { rate /= 2 }
                if let frames = attribute("Duration", "value").flatMap({ Double($0) }) {
                    info.duration = frames / rate
                }
            }
        }

        if let w = attribute("VideoLayout", "pixel"), let h = attribute("VideoLayout", "numOfVerticalLine") {
            info.resolution = "\(w)×\(h)"
        }
        return info
    }
}
