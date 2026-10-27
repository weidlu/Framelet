import AppKit
import ServiceManagement
import SwiftUI

@MainActor final class LoginItemController: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var message: String?

    init() { refresh() }

    func refresh() {
        let status = SMAppService.mainApp.status
        enabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }

    func setEnabled(_ value: Bool) {
        message = nil
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { message = error.localizedDescription }
        refresh()
    }
}

struct LoginItemSettings: View {
    @StateObject private var login = LoginItemController()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("后台运行").font(.headline)
            Toggle("登录后自动启动拾影", isOn: Binding(get: { login.enabled }, set: { login.setEnabled($0) }))
            Text("平时只在菜单栏运行，不显示 Dock 图标；用快捷键直接截图。").font(.system(size: 11)).foregroundStyle(.secondary)
            if login.needsApproval {
                Text("等待系统批准登录项。").font(.caption).foregroundStyle(.orange)
                Button("打开登录项设置") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let message = login.message { Text(message).font(.caption).foregroundStyle(.orange) }
        }
        .onAppear { login.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.refresh() }
    }
}
