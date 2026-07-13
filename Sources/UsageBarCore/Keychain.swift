import Foundation

public struct ClaudeCredentials {
    public let accessToken: String
    public let expiresAt: Date?
    public let subscriptionType: String?

    public static func parse(_ data: Data) -> ClaudeCredentials? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { return nil }
        var expires: Date? = nil
        if let raw = (oauth["expiresAt"] as? NSNumber)?.doubleValue {
            expires = Date(timeIntervalSince1970: raw > 1e12 ? raw / 1000 : raw)
        }
        return ClaudeCredentials(accessToken: token, expiresAt: expires,
                                 subscriptionType: oauth["subscriptionType"] as? String)
    }
}
