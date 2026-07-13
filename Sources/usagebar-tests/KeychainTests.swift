import Foundation
import UsageBarCore

func testCredentials() {
    let json = #"{"claudeAiOauth":{"accessToken":"tok-abc","refreshToken":"r","expiresAt":1784523369000,"subscriptionType":"max"}}"#
    guard let c = ClaudeCredentials.parse(Data(json.utf8)) else { expect(false, "creds nil"); return }
    expectEq(c.accessToken, "tok-abc", "token")
    expectEq(c.subscriptionType, "max", "sub")
    expect(abs(c.expiresAt!.timeIntervalSince1970 - 1784523369) < 1, "ms epoch handled")
    expect(ClaudeCredentials.parse(Data("{}".utf8)) == nil, "missing oauth -> nil")
}
