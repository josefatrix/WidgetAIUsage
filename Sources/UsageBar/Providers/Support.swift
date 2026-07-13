import Foundation
import UsageBarCore

enum ProviderID: String, CaseIterable, Identifiable {
    case codex, claude
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        }
    }
}

struct FetchFailure: Error { let message: String }

protocol UsageProvider {
    var id: ProviderID { get }
    func fetch() async -> Result<ProviderSnapshot, FetchFailure>
}

/// Per-file parse cache keyed by (path, mtime, size) so polls only re-parse changed files.
final class JSONLCache<Value> {
    private struct Entry { let mtime: Date; let size: Int; let value: Value }
    private var cache: [String: Entry] = [:]

    func value(forFile url: URL, compute: (String) -> Value) -> Value? {
        let path = url.path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date,
              let size = (attrs[.size] as? NSNumber)?.intValue else { return nil }
        if let e = cache[path], e.mtime == mtime, e.size == size { return e.value }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let value = compute(contents)
        cache[path] = Entry(mtime: mtime, size: size, value: value)
        return value
    }
}

func jsonlFiles(under root: URL, modifiedAfter cutoff: Date?) -> [URL] {
    let fm = FileManager.default
    guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                                 options: [.skipsHiddenFiles]) else { return [] }
    var out: [URL] = []
    for case let url as URL in en where url.pathExtension == "jsonl" {
        if let cutoff {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard let mtime, mtime > cutoff else { continue }
        }
        out.append(url)
    }
    return out
}

func fileMTime(_ url: URL) -> Date? {
    (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
}

let home = FileManager.default.homeDirectoryForCurrentUser
