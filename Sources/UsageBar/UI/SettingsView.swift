import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var store: UsageStore
    @Binding var isPresented: Bool
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    withAnimation(PopoverView.uiSpring) { isPresented = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                        Text("Back")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(GhostButtonStyle())
                Spacer()
                Text("Settings")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Color.clear.frame(width: 50, height: 1)
            }

            VStack(alignment: .leading, spacing: 10) {
                Picker("Refresh every", selection: $store.refreshIntervalMinutes) {
                    Text("1 min").tag(1)
                    Text("5 min").tag(5)
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                }
                .font(.system(size: 12))

                Picker("Popover", selection: $store.popoverStyle) {
                    ForEach(PopoverStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .font(.system(size: 12))

                Picker("Menu bar icon", selection: $store.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .font(.system(size: 12))

                Toggle("Launch at login", isOn: $launchAtLogin)
                    .font(.system(size: 12))
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            loginError = nil
                        } catch {
                            loginError = "Only works from the installed app (/Applications)."
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }

                if let loginError {
                    Text(loginError)
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 4)

            Text("Data: Anthropic usage API + local Claude/Codex logs. Costs are estimates.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}
