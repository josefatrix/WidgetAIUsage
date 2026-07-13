import Foundation
import UsageBarCore

func testPricing() {
    // fable: 1M in = $10, 1M out = $50
    expectEq(Pricing.costUSD(model: "claude-fable-5", input: 1_000_000, output: 0, cacheWrite: 0, cacheRead: 0), 10.0, "fable input")
    expectEq(Pricing.costUSD(model: "claude-fable-5", input: 0, output: 1_000_000, cacheWrite: 0, cacheRead: 0), 50.0, "fable output")
    // opus 4.8: $5/$25, cache write 6.25, cache read 0.5
    expectEq(Pricing.costUSD(model: "claude-opus-4-8", input: 0, output: 0, cacheWrite: 1_000_000, cacheRead: 1_000_000), 6.75, "opus cache")
    // legacy opus 4.1 is $15/$75
    expectEq(Pricing.costUSD(model: "claude-opus-4-1", input: 1_000_000, output: 0, cacheWrite: 0, cacheRead: 0), 15.0, "opus 4.1")
    // haiku
    expectEq(Pricing.costUSD(model: "claude-haiku-4-5-20251001", input: 1_000_000, output: 1_000_000, cacheWrite: 0, cacheRead: 0), 6.0, "haiku")
    // codex estimate
    expectEq(Pricing.costUSD(model: "gpt-5.2-codex", input: 1_000_000, output: 0, cacheWrite: 0, cacheRead: 1_000_000), 1.375, "gpt5")
    // unknown model → 0
    expectEq(Pricing.costUSD(model: "mystery", input: 1_000_000, output: 0, cacheWrite: 0, cacheRead: 0), 0.0, "unknown")
    // synthetic skipped
    expectEq(Pricing.costUSD(model: "<synthetic>", input: 99, output: 99, cacheWrite: 0, cacheRead: 0), 0.0, "synthetic")
}
