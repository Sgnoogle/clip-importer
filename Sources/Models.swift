import Foundation

/// Una clip video trovata sulla scheda.
struct Clip: Identifiable, Hashable {
    let id: URL                 // percorso del file sulla scheda
    var url: URL { id }
    let name: String
    let size: Int64
    let date: Date
    let duration: Double?       // secondi (dal file XML Sony, se presente)
    let thumbnailURL: URL?      // miniatura già pronta di Sony (PRIVATE/M4ROOT/THMBNL)
    let sidecarURL: URL?        // file XML dei metadati Sony (C0001M01.XML)
    let proxyURL: URL?          // proxy Sony (PRIVATE/M4ROOT/SUB)
    let proxySize: Int64?
    let fps: String?
    let resolution: String?
    // Foto
    var kind: MediaKind = .video
    var companions: [URL] = []      // es. il RAW (.ARW) scattato insieme al JPEG
    var companionsSize: Int64 = 0
    var parts: [PhotoPart] = []     // tutti i file della foto (il principale per primo)
    var badge: String? = nil        // "RAW + JPEG", "RAW", "HEIF"…

    var isPhoto: Bool { kind == .photo }

    /// Identità del file vero, non solo del percorso: due schede Sony hanno gli stessi nomi (C0001.MP4)
    /// e si montano nello stesso posto ("/Volumes/NO NAME"), quindi il percorso da solo non basta.
    var contentKey: String { "\(url.path)|\(size)|\(Int(date.timeIntervalSince1970))" }

    /// Byte totali da copiare (foto + eventuale RAW abbinato)
    var importSize: Int64 { size + companionsSize }

    /// Scattata in RAW + JPEG (o RAW + HEIF): si può scegliere quale dei due importare.
    var isRawPair: Bool { parts.contains(where: \.isRaw) && parts.contains { !$0.isRaw } }

    /// Il formato che accompagna il RAW: "JPEG", "HEIF"…
    var processedLabel: String { badge?.replacingOccurrences(of: "RAW + ", with: "") ?? "JPEG" }

    /// I file da importare con questa scelta (la scelta vale solo per le coppie RAW + JPEG).
    func parts(for format: PhotoFormat) -> [PhotoPart] { isRawPair ? parts.filter(format.wants) : parts }

    /// La stessa foto con i soli file da importare: è quella che si copia, si verifica e (spostando) si cancella.
    /// Il file escluso non ne fa parte, quindi non viene mai toccato.
    func restricted(to format: PhotoFormat) -> Clip {
        guard isRawPair, format != .both else { return self }
        let wanted = parts(for: format)
        guard let main = wanted.first else { return self }
        var c = Clip(id: main.url, name: main.url.lastPathComponent, size: main.size, date: date, duration: nil,
                     thumbnailURL: nil, sidecarURL: nil, proxyURL: nil, proxySize: nil, fps: nil, resolution: resolution)
        c.kind = .photo
        c.companions = wanted.dropFirst().map(\.url)
        c.companionsSize = wanted.dropFirst().reduce(0) { $0 + $1.size }
        c.parts = wanted
        c.badge = format == .raw ? "RAW" : processedLabel
        return c
    }

    var canPreview: Bool {
        kind == .video && ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
    }

    var techLabel: String? {
        let parts = [resolution, fps].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

enum MediaKind: String { case video, photo }

/// Uno dei file di una foto (il JPEG, il RAW…).
struct PhotoPart: Hashable {
    let url: URL
    let size: Int64
    let modified: Date
    let isRaw: Bool
}

/// Cosa importare delle foto scattate in RAW + JPEG.
enum PhotoFormat: String, CaseIterable, Identifiable {
    case both, processed, raw
    var id: String { rawValue }
    func wants(_ part: PhotoPart) -> Bool {
        switch self {
        case .both: return true
        case .processed: return !part.isRaw
        case .raw: return part.isRaw
        }
    }
    /// `processed`: come si chiama l'altro formato ("JPEG" o "HEIF")
    func label(processed: String) -> String {
        switch self {
        case .both: return L("Both")
        case .processed: return L("{0} only", processed)
        case .raw: return L("{0} only", "RAW")
        }
    }
}

/// Etichette alla Lightroom: P scelta, X scartata, U nessuna.
enum Flag: String, Codable { case pick, reject }

/// Cosa mostrare: tutto, solo i video o solo le foto.
enum MediaFilter: String, CaseIterable, Identifiable {
    case all, videos, photos
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return L("All")
        case .videos: return L("Videos")
        case .photos: return L("Photos")
        }
    }
    func includes(_ clip: Clip) -> Bool {
        switch self {
        case .all: return true
        case .videos: return clip.kind == .video
        case .photos: return clip.kind == .photo
        }
    }
}

/// Una sorgente da cui importare: una scheda inserita o una cartella scelta a mano.
struct Source: Identifiable, Hashable {
    let id: URL
    let name: String
    let isVolume: Bool
}

struct DaySection: Identifiable {
    let id: Date
    var clips: [Clip]
}

enum SortKey: String, CaseIterable, Identifiable {
    case date, name, duration, size
    var id: String { rawValue }
    var label: String {
        switch self {
        case .date: return L("Date taken")
        case .name: return L("Name")
        case .duration: return L("Duration")
        case .size: return L("Size")
        }
    }
}

enum FolderMode: String, CaseIterable, Identifiable {
    case flat, byShootDay, byImportDay, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .flat: return L("Everything in one folder")
        case .byShootDay: return L("One folder per shooting day")
        case .byImportDay: return L("One folder with today's date")
        case .custom: return L("One folder with a custom name")
        }
    }
}

struct ImportOptions {
    let destRoot: URL
    let folderMode: FolderMode
    let customName: String
    let copySidecar: Bool
    let copyProxy: Bool
    let renameWithDate: Bool
    var deleteOriginals: DeleteMode = .keep
}

/// Cosa fare degli originali dopo una copia verificata.
enum DeleteMode {
    case keep           // lasciali dove sono
    case permanent      // cancellali (scheda: il Cestino non libererebbe spazio)
    case trash          // spostali nel Cestino (cartelle sul Mac)
}

struct ImportProgress {
    var fileIndex: Int
    var fileCount: Int
    var currentName: String
    /// Lavoro fatto/totale (barra e tempo rimanente): spostando comprende anche la rilettura di verifica.
    var bytesDone: Int64
    var bytesTotal: Int64
    var startedAt: Date
    var verb = L("Importing {0}")
    /// Byte dei file davvero importati (quelli mostrati all'utente): senza la verifica, che non è un secondo file.
    var copiedDone: Int64 = 0
    var copiedTotal: Int64 = 0

    /// Quanta parte di `shown` corrisponde al lavoro fatto. In virgola mobile: byte × byte non sta in un Int64
    /// già con un file da circa 3 GB (2 GB spostando), e in Swift l'overflow chiude l'app.
    static func shownBytes(work: Int64, of total: Int64, shown: Int64) -> Int64 {
        guard total > 0, shown > 0, work > 0 else { return 0 }
        if work >= total { return shown }
        return min(shown, Int64(Double(work) / Double(total) * Double(shown)))
    }

    var fraction: Double {
        bytesTotal > 0 ? min(1, Double(bytesDone) / Double(bytesTotal)) : 0
    }

    var detail: String {
        let shownTotal = copiedTotal > 0 ? copiedTotal : bytesTotal
        let shownDone = copiedTotal > 0 ? min(copiedDone, copiedTotal) : bytesDone
        var parts = [L("{0} of {1}", Fmt.bytes(shownDone), Fmt.bytes(shownTotal))]
        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed > 2, bytesDone > 0, shownDone > 0 {
            parts.append("\(Fmt.bytes(Int64(Double(shownDone) / elapsed)))/s")
            parts.append(Fmt.remaining(Double(bytesTotal - bytesDone) / (Double(bytesDone) / elapsed)))
        }
        return parts.joined(separator: " · ")
    }
}

struct ImportFailure {
    let clip: Clip
    let message: String
}

struct ImportResult {
    var imported: [Clip] = []
    var skipped: [Clip] = []        // già presenti, identiche, nella destinazione
    var failed: [ImportFailure] = []
    var files: [URL] = []
    var cancelled = false
    var deleted: [Clip] = []                // originali cancellati dopo la verifica
    var deleteFailures: [ImportFailure] = []
}

/// Flag di annullamento condiviso tra interfaccia e copia in background.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func cancel() { lock.lock(); value = true; lock.unlock() }
}

enum Fmt {
    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Lang.locale
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }
    private static let dayFormatter = formatter("EEEEdMMMMyyyy")
    private static let timeFormatter = formatter("jmm")
    private static let shortFormatter = formatter("dMMMyyyyjmm")

    static func day(_ d: Date) -> String {
        let s = dayFormatter.string(from: d)
        return s.prefix(1).uppercased() + s.dropFirst()
    }
    static func time(_ d: Date) -> String { timeFormatter.string(from: d) }
    static func dateTime(_ d: Date) -> String { shortFormatter.string(from: d) }

    /// Dimensioni "da Finder" (base 1000), con separatore decimale della lingua dell'interfaccia.
    static func bytes(_ b: Int64) -> String {
        let units = ["KB", "MB", "GB", "TB"]
        guard b >= 1000 else { return L("{0} bytes", Int(b)) }
        var value = Double(b) / 1000
        var i = 0
        while value >= 1000 && i < units.count - 1 { value /= 1000; i += 1 }
        let f = NumberFormatter()
        f.locale = Lang.locale
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = i == 0 ? 0 : (i == 1 ? 1 : 2)
        return "\(f.string(from: NSNumber(value: value)) ?? "\(value)") \(units[i])"
    }

    static func duration(_ seconds: Double) -> String {
        let t = Int(seconds.rounded())
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func remaining(_ seconds: Double) -> String {
        if !seconds.isFinite { return "" }
        if seconds < 60 { return L("less than a minute") }
        let m = Int((seconds / 60).rounded(.up))
        return L("about {0} min left", m)
    }

    static func clips(_ n: Int) -> String { n == 1 ? L("1 clip") : L("{0} clips", n) }
    static func photos(_ n: Int) -> String { n == 1 ? L("1 photo") : L("{0} photos", n) }

    /// "12 clip e 30 foto", "3 foto", "1 clip"
    static func items(_ list: [Clip]) -> String {
        let photos = list.filter(\.isPhoto).count
        let videos = list.count - photos
        var parts: [String] = []
        if videos > 0 || photos == 0 { parts.append(clips(videos)) }
        if photos > 0 { parts.append(Fmt.photos(photos)) }
        return parts.joined(separator: L(" and "))
    }
}
