import Foundation

public struct ModelPricing {
    public let input: Double, output: Double, cacheWrite: Double, cacheRead: Double
    init(_ input: Double, _ output: Double, _ cacheWrite: Double, _ cacheRead: Double) {
        self.input = input; self.output = output; self.cacheWrite = cacheWrite; self.cacheRead = cacheRead
    }
}

public enum Pricing {
    // Most-specific prefixes first — first match wins.
    static let table: [(String, ModelPricing)] = [
        ("claude-fable-5",    ModelPricing(10, 50, 12.5, 1.0)),
        ("claude-mythos",     ModelPricing(10, 50, 12.5, 1.0)),
        ("claude-opus-4-1",   ModelPricing(15, 75, 18.75, 1.5)),
        ("claude-opus-4-0",   ModelPricing(15, 75, 18.75, 1.5)),
        ("claude-opus-4-20",  ModelPricing(15, 75, 18.75, 1.5)),
        ("claude-3-opus",     ModelPricing(15, 75, 18.75, 1.5)),
        ("claude-opus",       ModelPricing(5, 25, 6.25, 0.5)),
        ("claude-sonnet",     ModelPricing(3, 15, 3.75, 0.3)),
        ("claude-3-5-sonnet", ModelPricing(3, 15, 3.75, 0.3)),
        ("claude-3-7-sonnet", ModelPricing(3, 15, 3.75, 0.3)),
        ("claude-3-5-haiku",  ModelPricing(0.8, 4, 1.0, 0.08)),
        ("claude-haiku",      ModelPricing(1, 5, 1.25, 0.1)),
        ("gpt-",              ModelPricing(1.25, 10, 0, 0.125)),
        ("codex-",            ModelPricing(1.25, 10, 0, 0.125)),
    ]

    public static func pricing(forModel model: String) -> ModelPricing? {
        table.first { model.hasPrefix($0.0) }?.1
    }

    public static func costUSD(model: String, input: Int, output: Int, cacheWrite: Int, cacheRead: Int) -> Double {
        guard let p = pricing(forModel: model) else { return 0 }
        let m = 1_000_000.0
        return Double(input) / m * p.input
             + Double(output) / m * p.output
             + Double(cacheWrite) / m * p.cacheWrite
             + Double(cacheRead) / m * p.cacheRead
    }
}
