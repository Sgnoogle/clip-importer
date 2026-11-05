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
    var bytesDone: Int64
    var bytesTotal: Int64
    var startedAt: Date
    var verb = L("Importing {0}")

    var fraction: Double {
        bytesTotal > 0 ? min(1, Double(bytesDone) / Double(bytesTotal)) : 0
    }

    var detail: String {
        var parts = [L("{0} of {1}", Fmt.bytes(bytesDone), Fmt.bytes(bytesTotal))]
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
