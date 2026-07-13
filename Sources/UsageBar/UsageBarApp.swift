import SwiftUI

@main
struct UsageBarApp: App {
    @StateObject private var store = UsageStore()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(store)
        } label: {
            Image(nsImage: MenuBarLabel.barImage(percent: store.menuBarPercent))
        }
        .menuBarExtraStyle(.window)
    }
}
