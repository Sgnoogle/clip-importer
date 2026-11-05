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
    var badge: String? = nil        // "RAW + JPEG", "RAW", "HEIF"…

    var isPhoto: Bool { kind == .photo }

    /// Byte totali da copiare (foto + eventuale RAW abbinato)
    var importSize: Int64 { size + companionsSize }

    var canPreview: Bool {
        kind == .video && ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
    }

    var techLabel: String? {
        let parts = [resolution, fps].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

enum MediaKind: String { case video, photo }

/// Etichette alla Lightroom: P scelta, X scartata, U nessuna.
enum Flag: String, Codable { case pick, reject }

/// Cosa mostrare: tutto, solo i video o solo le foto.
enum MediaFilter: String, CaseIterable, Identifiable {
    case all, videos, photos
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "Tutto"
        case .videos: return "Video"
        case .photos: return "Foto"
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
        case .date: return "Data di ripresa"
        case .name: return "Nome"
        case .duration: return "Durata"
        case .size: return "Dimensione"
        }
    }
}

enum FolderMode: String, CaseIterable, Identifiable {
    case flat, byShootDay, byImportDay, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .flat: return "Tutto nella stessa cartella"
        case .byShootDay: return "Una cartella per giorno di ripresa"
        case .byImportDay: return "Una cartella con la data di oggi"
        case .custom: return "Una cartella con un nome a scelta"
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
    var bytesDone: Int64
    var bytesTotal: Int64
    var startedAt: Date
    var verb = "Importazione di"

    var fraction: Double {
        bytesTotal > 0 ? min(1, Double(bytesDone) / Double(bytesTotal)) : 0
    }

    var detail: String {
        var parts = ["\(Fmt.bytes(bytesDone)) di \(Fmt.bytes(bytesTotal))"]
        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed > 2, bytesDone > 0 {
            let speed = Double(bytesDone) / elapsed
            parts.append("\(Fmt.bytes(Int64(speed)))/s")
            parts.append(Fmt.remaining(Double(bytesTotal - bytesDone) / speed))
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
    static let italian = Locale(identifier: "it_IT")

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = italian; f.dateFormat = "EEEE d MMMM yyyy"; return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = italian; f.dateFormat = "HH:mm"; return f
    }()
    private static let shortFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = italian; f.dateFormat = "d MMM yyyy, HH:mm"; return f
    }()

    static func day(_ d: Date) -> String {
        let s = dayFormatter.string(from: d)
        return s.prefix(1).uppercased() + s.dropFirst()
    }
    static func time(_ d: Date) -> String { timeFormatter.string(from: d) }
    static func dateTime(_ d: Date) -> String { shortFormatter.string(from: d) }

    static func bytes(_ b: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: b)
    }

    static func duration(_ seconds: Double) -> String {
        let t = Int(seconds.rounded())
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func remaining(_ seconds: Double) -> String {
        if !seconds.isFinite { return "" }
        if seconds < 60 { return "meno di un minuto" }
        return "circa \(Int((seconds / 60).rounded(.up))) min"
    }

    static func clips(_ n: Int) -> String { n == 1 ? "1 clip" : "\(n) clip" }

    /// "12 clip e 30 foto", "3 foto", "1 clip"
    static func items(_ list: [Clip]) -> String {
        let photos = list.filter(\.isPhoto).count
        let videos = list.count - photos
        var parts: [String] = []
        if videos > 0 || photos == 0 { parts.append(clips(videos)) }
        if photos > 0 { parts.append("\(photos) foto") }
        return parts.joined(separator: " e ")
    }
}
