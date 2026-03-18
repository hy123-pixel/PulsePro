// The MIT License (MIT)
//
// Copyright (c) 2024 Pulse Pro

import SwiftUI
import Pulse
import PulseUI
import Combine
import CoreData

struct ContentView: View {
    @EnvironmentObject private var controller: PulseProStoreController
    @AppStorage("selectedMainTab") private var selectedTabStorage = AppTab.network.rawValue
    @AppStorage("sidebarCollapsed") private var sidebarCollapsed = true
    @State private var isShowingSettings = false
    @State private var isShowingRemotePopover = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly

    private var selectedTab: AppTab {
        get { AppTab(rawValue: selectedTabStorage) ?? .network }
        nonmutating set { selectedTabStorage = newValue.rawValue }
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedTab: Binding(get: { selectedTab }, set: { selectedTabStorage = $0.rawValue }))
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 300)
        } detail: {
            DetailView(selectedTab: selectedTab, store: controller.store)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: controller.openStorePanel) {
                    Label("打开日志包", systemImage: "folder")
                }
                .help("打开外部 Pulse 日志包")

                Button(action: controller.exportCurrentStore) {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
                .help("导出当前日志包")

                Button {
                    Task {
                        await controller.refreshInfo()
                    }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .help("刷新当前日志信息")

                Button {
                    isShowingRemotePopover.toggle()
                } label: {
                    RemoteStatusLabel(
                        state: controller.remoteServer.state,
                        isStreaming: controller.remoteServer.isStreaming
                    )
                }
                .buttonStyle(.bordered)
                .popover(isPresented: $isShowingRemotePopover, arrowEdge: .top) {
                    RemoteStatusPopover(controller: controller)
                        .frame(width: 360)
                        .padding(16)
                }
                
                Button(action: { isShowingSettings = true }) {
                    Label("设置", systemImage: "gear")
                }
                .help("设置")
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(controller: controller)
                .frame(width: 400, height: 500)
        }
        .alert(
            "Pulse Pro",
            isPresented: Binding(
                get: { controller.errorMessage != nil },
                set: { if !$0 { controller.errorMessage = nil } }
            ),
            actions: {
                Button("关闭", role: .cancel) {
                    controller.errorMessage = nil
                }
            },
            message: {
                Text(controller.errorMessage ?? "")
            }
        )
        .task {
            columnVisibility = sidebarCollapsed ? .detailOnly : .all
            await controller.refreshInfo()
        }
        .onChange(of: columnVisibility) { newValue in
            sidebarCollapsed = (newValue == .detailOnly)
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case liveConsole = "实时日志"
    case network = "网络检查"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .liveConsole: return "text.alignleft"
        case .network: return "network"
        }
    }

    var subtitle: String {
        switch self {
        case .liveConsole:
            return "看实时日志、错误与请求流"
        case .network:
            return "检查请求头、响应头、Body 与时序"
        }
    }
}

struct SidebarView: View {
    @Binding var selectedTab: AppTab
    
    var body: some View {
        List(selection: $selectedTab) {
            Section("采集与分析") {
                ForEach([AppTab.liveConsole, AppTab.network]) { tab in
                    SidebarRow(tab: tab)
                        .tag(tab)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Pulse Pro")
    }
}

struct SidebarRow: View {
    let tab: AppTab

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tab.icon)
                .frame(width: 18)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(tab.rawValue)
                Text(tab.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct RemoteStatusLabel: View {
    let state: PulseProRemoteServer.State
    let isStreaming: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)
            Text(labelText)
        }
    }

    private var indicatorColor: Color {
        switch state {
        case .connected:
            return isStreaming ? .green : .orange
        case .connecting:
            return .yellow
        case .listening:
            return .blue
        case .failed:
            return .red
        case .stopped:
            return .secondary
        }
    }

    private var labelText: String {
        switch state {
        case .connected:
            return isStreaming ? "已连接" : "已连接（已暂停）"
        case .connecting:
            return "连接中"
        case .listening:
            return "等待连接"
        case .failed:
            return "连接异常"
        case .stopped:
            return "未启动"
        }
    }
}

struct RemoteStatusPopover: View {
    @ObservedObject var controller: PulseProStoreController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("远程连接")
                    .font(.headline)
                Spacer()
                RemoteStatusLabel(
                    state: controller.remoteServer.state,
                    isStreaming: controller.remoteServer.isStreaming
                )
            }

            Group {
                RemoteInfoRow(label: "服务名", value: controller.remoteServer.serviceName)
                RemoteInfoRow(label: "状态", value: controller.remoteServer.state.rawValue)
                RemoteInfoRow(label: "日志接收", value: controller.remoteServer.isStreaming ? "进行中" : "已暂停")
                if let name = controller.remoteServer.connectedDeviceName {
                    RemoteInfoRow(label: "设备", value: name)
                }
                if let appName = controller.remoteServer.connectedAppName {
                    RemoteInfoRow(label: "来源应用", value: appName)
                }
            }

            HStack(spacing: 10) {
                Button("启动服务") { controller.startRemoteServer() }
                    .disabled(!controller.canHostRemoteConnections || (controller.isRemoteServerEnabled && controller.remoteServer.state != .stopped))
                Button("停止服务") { controller.stopRemoteServer() }
                    .disabled(controller.remoteServer.state == .stopped)
                Button("重启服务") { controller.restartRemoteServer() }
                    .disabled(!controller.canHostRemoteConnections)
            }

            HStack(spacing: 10) {
                Button(controller.remoteServer.isStreaming ? "暂停接收日志" : "开始接收日志") {
                    if controller.remoteServer.isStreaming {
                        controller.pauseReceivingRemoteEvents()
                    } else {
                        controller.startReceivingRemoteEvents()
                    }
                }
                .disabled(controller.remoteServer.state != .connected)

                Button("清空日志", role: .destructive) {
                    controller.clearWritableStore()
                }
                .disabled(controller.isReadOnlyStore)
            }

            if let error = controller.remoteServer.lastError {
                Text("异常: \(error)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !controller.remoteServer.recentEvents.isEmpty {
                Divider()
                Text("最近事件")
                    .font(.subheadline.weight(.semibold))
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(controller.remoteServer.recentEvents, id: \.self) { event in
                        Text(event)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

struct RemoteInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer()
        }
        .font(.caption)
    }
}

struct DetailView: View {
    let selectedTab: AppTab
    let store: LoggerStore
    
    var body: some View {
        Group {
            switch selectedTab {
            case .liveConsole:
                ConsoleContainerView(store: store)
            case .network:
                NetworkListView(store: store)
            }
        }
    }
}
