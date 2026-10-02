import Foundation

/// ChatGPT publishes no quota to the Mac: there is no rate-limit record anywhere
/// under ~/Library/Application Support/com.openai.chat, and the desktop app's
/// preferences carry only notification settings. What it does leave behind is one
/// opaque `.data` blob per conversation, in a per-account folder — so activity
/// (conversations touched per day) is the honest ceiling for what we can report,
/// the same bargain the Gemini provider already makes.
///
/// The blobs are never opened; only their modification dates are read.
public enum ChatGPTActivity {
    static let dirPrefix = "conversations-v3-"

    /// Per-account conversation folders. A Mac signed into two ChatGPT accounts
    /// has one each, and both count as this person's activity.
    public static func conversationDirs(in names: [String]) -> [String] {
        names.filter { $0.hasPrefix(dirPrefix) && $0.count > dirPrefix.count }
    }

    public static func isConversationFile(_ name: String) -> Bool {
        name.hasSuffix(".data") && !name.hasPrefix(".")
    }
}
