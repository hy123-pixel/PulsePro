// The MIT License (MIT)
//
// Copyright (c) 2024 Pulse Pro

import SwiftUI
import Pulse
import AppKit

struct SettingsView: View {
    @ObservedObject var controller: PulseProStoreController
    @Environment(\.dismiss) private var dismiss
    @AppStorage("autoRefresh") private var autoRefresh = true
    @AppStorage("refreshInterval") private var refreshInterval = 1.0
    @AppStorage("maxLogEntries") private var maxLogEntries = 1000
    @AppStorage("enableJSONFilter") private var enableJSONFilter = true
    @AppStorage("showNetworkMetrics") private var showNetworkMetrics = true
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    
    var body: some View {
        VStack(spacing: 0) {
            // 头部
            HStack {
                Text("设置")
                    .font(.headline)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // 设置内容
            Form {
                Section("常规") {
                    Toggle("自动刷新", isOn: $autoRefresh)
                    
                    if autoRefresh {
                        Picker("刷新间隔", selection: $refreshInterval) {
                            Text("0.5 秒").tag(0.5)
                            Text("1 秒").tag(1.0)
                            Text("2 秒").tag(2.0)
                            Text("5 秒").tag(5.0)
                        }
                    }
                    
                    Stepper("最大日志条目: \(maxLogEntries)", value: $maxLogEntries, in: 100...10000, step: 100)
                }
                
                Section("网络") {
                    Toggle("显示性能指标", isOn: $showNetworkMetrics)
                    Toggle("启用 JSON 过滤器", isOn: $enableJSONFilter)
                }
                
                Section("外观") {
                    Picker("主题模式", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("存储") {
                    HStack {
                        Text("日志存储位置")
                        Spacer()
                        Text(controller.storeLocationDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    HStack {
                        Text("当前来源")
                        Spacer()
                        Text(controller.sourceDescription)
                            .foregroundColor(.secondary)
                    }
                    
                    Button("打开外部日志包...") {
                        controller.openStorePanel()
                    }

                    Button("回到默认工作区") {
                        controller.resetToDefaultStore()
                    }

                    Button("清除默认工作区日志", role: .destructive) {
                        clearAllLogs()
                    }
                    .disabled(controller.isReadOnlyStore)
                }

                Section("远程接收") {
                    HStack {
                        Text("服务状态")
                        Spacer()
                        Text(controller.remoteServer.state.rawValue)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Bonjour 名称")
                        Spacer()
                        Text(controller.remoteServer.serviceName)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("日志接收")
                        Spacer()
                        Text(controller.remoteServer.isStreaming ? "进行中" : "已暂停")
                            .foregroundColor(.secondary)
                    }

                    Button("启动远程接收") {
                        controller.startRemoteServer()
                    }
                    .disabled(!controller.canHostRemoteConnections || (controller.isRemoteServerEnabled && controller.remoteServer.state != .stopped))

                    Button("停止远程接收") {
                        controller.stopRemoteServer()
                    }
                    .disabled(controller.remoteServer.state == .stopped)

                    Button("重启远程接收") {
                        controller.restartRemoteServer()
                    }
                    .disabled(!controller.canHostRemoteConnections)

                    Button(controller.remoteServer.isStreaming ? "暂停日志接收" : "开始日志接收") {
                        if controller.remoteServer.isStreaming {
                            controller.pauseReceivingRemoteEvents()
                        } else {
                            controller.startReceivingRemoteEvents()
                        }
                    }
                    .disabled(controller.remoteServer.state != .connected)
                }
                
                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link("官方网站", destination: URL(string: "https://pulselogger.com")!)
                    
                    Link("GitHub", destination: URL(string: "https://github.com/kean/Pulse")!)
                }
            }
            .formStyle(.grouped)
        }
    }
    
    private func close() {
        dismiss()
    }
    
    private func clearAllLogs() {
        let alert = NSAlert()
        alert.messageText = "清除所有日志？"
        alert.informativeText = "此操作无法撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清除")
        alert.addButton(withTitle: "取消")
        
        if alert.runModal() == .alertFirstButtonReturn {
            controller.clearWritableStore()
        }
    }
}
