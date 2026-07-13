import Foundation

public struct UsageEvent: Codable {
    public let timestamp: Date
    public let model: String
    public let input: Int, output: Int, cacheWrite: Int, cacheRead: Int
    public let dedupeKey: String?
    public let costUSD: Double
    public init(timestamp: Date, model: String, input: Int, output: Int,
                cacheWrite: Int, cacheRead: Int, dedupeKey: String?, costUSD: Double) {
        self.timestamp = timestamp; self.model = model
        self.input = input; self.output = output
        self.cacheWrite = cacheWrite; self.cacheRead = cacheRead
        self.dedupeKey = dedupeKey; self.costUSD = costUSD
    }
}

public enum ClaudeCost {
    public static func parseLine(_ line: String) -> UsageEvent? {
        guard line.contains("\"assistant\""), let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["type"] as? String == "assistant",
              let msg = obj["message"] as? [String: Any],
              let usage = msg["usage"] as? [String: Any],
              let model = msg["model"] as? String, !model.hasPrefix("<"),
              let ts = ClaudeLimits.parseISODate(obj["timestamp"] as? String)
        else { return nil }
        func n(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
        let input = n("input_tokens"), output = n("output_tokens")
        let cw = n("cache_creation_input_tokens"), cr = n("cache_read_input_tokens")
        var key: String? = nil
        if let mid = msg["id"] as? String, let rid = obj["requestId"] as? String { key = "\(mid):\(rid)" }
        let cost = Pricing.costUSD(model: model, input: input, output: output, cacheWrite: cw, cacheRead: cr)
        return UsageEvent(timestamp: ts, model: model, input: input, output: output,
                          cacheWrite: cw, cacheRead: cr, dedupeKey: key, costUSD: cost)
    }
}
