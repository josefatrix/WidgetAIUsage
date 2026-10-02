import Foundation
import UsageBarCore

/// ChatGPT exposes no quota locally (see `ChatGPTActivity`), so this provider
/// reports the same shape as Gemini: account plus a 30-day activity chart, no
/// limit bars. Activity = conversations touched per day, read from the desktop
/// app's cache timestamps — the blobs themselves are never opened.
///
/// Blind spots worth remembering: only what the desktop app cached counts, so
/// anything done on the web or on a phone is invisible, and a conversation
/// touched twice in a day counts once.
final class ChatGPTProvider: UsageProvider {
    let id = ProviderID.chatgpt

    func fetch() async -> Result<ProviderSnapshot, FetchFailure> {
        let fm = FileManager.default
        let root = home.appendingPathComponent("Library/Application Support/com.openai.chat")
        guard fm.fileExists(atPath: root.path) else {
            return .failure(FetchFailure(message: "ChatGPT desktop app not found"))
        }

        let names = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        let dirs = ChatGPTActivity.conversationDirs(in: names)
        guard !dirs.isEmpty else {
            return .failure(FetchFailure(message: "No ChatGPT conversations cached locally"))
        }

        var stamps: [Date] = []
        for dir in dirs {
            let url = root.appendingPathComponent(dir, isDirectory: true)
            guard let files = try? fm.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]) else { continue }
            for file in files where ChatGPTActivity.isConversationFile(file.lastPathComponent) {
                if let mtime = fileMTime(file) { stamps.append(mtime) }
            }
        }
        guard !stamps.isEmpty else {
            return .failure(FetchFailure(message: "No ChatGPT conversations cached locally"))
        }

        let now = Date()
        let cutoff = now.addingTimeInterval(-31 * 24 * 3600)
        let events = stamps.filter { $0 > cutoff }.map {
            // costUSD carries "1 conversation" — the snapshot is costUnit: .requests.
            UsageEvent(timestamp: $0, model: "chatgpt", input: 0, output: 0,
                       cacheWrite: 0, cacheRead: 0, dedupeKey: nil, costUSD: 1)
        }
        let history = Aggregation.dailyHistory(events: events, now: now, days: 30, calendar: .current)
        return .success(ProviderSnapshot(account: nil, plan: nil, limits: [],
                                         cost: nil, history: history, fetchedAt: now,
                                         dataThrough: stamps.max(),
                                         costUnit: .conversations))
    }
}
