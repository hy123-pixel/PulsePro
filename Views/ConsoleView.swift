// The MIT License (MIT)
//
// Copyright (c) 2024 Pulse Pro

import SwiftUI
import Pulse
import PulseUI
import CoreData
import Combine

struct ConsoleContainerView: View {
    let store: LoggerStore
    @State private var searchText = ""
    @State private var selectedMessage: LoggerMessageEntity?
    
    var body: some View {
        HSplitView {
            // 日志列表
            VStack(spacing: 0) {
                // 工具栏
                ConsoleToolbar(
                    searchText: $searchText,
                    store: store
                )
                
                Divider()
                
                // 日志列表内容
                ConsoleListContent(
                    store: store,
                    searchText: searchText,
                    selectedMessage: $selectedMessage
                )
            }
            .frame(minWidth: 400)
            
            // 详情面板
            DetailPanelView(
                message: selectedMessage,
                task: nil,
                store: store
            )
            .frame(minWidth: 300, idealWidth: 400)
        }
    }
}

struct ConsoleToolbar: View {
    @EnvironmentObject private var controller: PulseProStoreController
    @Binding var searchText: String
    let store: LoggerStore
    
    var body: some View {
        HStack(spacing: 16) {
            // 搜索框
            TextField("搜索...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
            
            Spacer()
             
            Button(action: controller.clearWritableStore) {
                Label("清除日志", systemImage: "trash")
            }
            .help("清除当前工作区日志")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// 日志列表内容
struct ConsoleListContent: View {
    let store: LoggerStore
    let searchText: String
    @Binding var selectedMessage: LoggerMessageEntity?
    
    var body: some View {
        TableModeView(
            store: store,
            searchText: searchText,
            selectedMessage: $selectedMessage
        )
    }
}

// 表格模式视图
struct TableModeView: View {
    let store: LoggerStore
    let searchText: String
    @Binding var selectedMessage: LoggerMessageEntity?
    
    var body: some View {
        let context = store.viewContext
        let request = LoggerMessageEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \LoggerMessageEntity.createdAt, ascending: false)]
        
        let messages = (try? context.fetch(request)) as? [LoggerMessageEntity] ?? []
        
        return List(messages, selection: $selectedMessage) { message in
            MessageRowView(message: message)
                .tag(message)
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }
}

// 文本模式视图
struct TextModeView: View {
    let store: LoggerStore
    let mode: ConsoleMode
    let searchText: String
    
    var body: some View {
        let context = store.viewContext
        let request = LoggerMessageEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \LoggerMessageEntity.createdAt, ascending: false)]
        
        let messages = (try? context.fetch(request)) as? [LoggerMessageEntity] ?? []
        
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(messages, id: \.objectID) { message in
                    TextRowView(message: message)
                }
            }
            .padding()
        }
        .background(Color(nsColor: .textBackgroundColor))
        .font(.system(.body, design: .monospaced))
    }
}

struct MessageRowView: View {
    let message: LoggerMessageEntity
    
    var body: some View {
        HStack(spacing: 12) {
            Text(formatDate(message.createdAt))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)
            
            LabelLevelView(level: message.level)
                .frame(width: 50, alignment: .leading)
            
            Text(message.text)
                .lineLimit(2)
                .font(.system(.body, design: .monospaced))
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

struct TextRowView: View {
    let message: LoggerMessageEntity
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(formatDate(message.createdAt))
                .foregroundColor(.secondary)
            
            Text(levelText(message.level))
                .foregroundColor(levelColor(message.level))
                .frame(width: 50, alignment: .leading)
            
            Text(message.text)
                .textSelection(.enabled)
            
            Spacer()
        }
        .padding(.vertical, 2)
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
    
    private func levelText(_ level: Int16) -> String {
        switch level {
        case 0: return "调试"
        case 1: return "信息"
        case 2: return "警告"
        case 3: return "错误"
        default: return "未知"
        }
    }
    
    private func levelColor(_ level: Int16) -> Color {
        switch level {
        case 0: return .secondary
        case 1: return .blue
        case 2: return .orange
        case 3: return .red
        default: return .secondary
        }
    }
}

// 详情面板
struct DetailPanelView: View {
    let message: LoggerMessageEntity?
    let task: NetworkTaskEntity?
    let store: LoggerStore
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let message = message {
                    MessageDetailView(message: message)
                } else if let task = task {
                    NetworkTaskDetailView(task: task)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("选择一项查看详情")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                }
            }
            .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct MessageDetailView: View {
    let message: LoggerMessageEntity
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("日志详情")
                .font(.headline)
            
            GroupBox("基本信息") {
                VStack(alignment: .leading, spacing: 8) {
                    DetailRow(label: "时间", value: formatDate(message.createdAt))
                    DetailRow(label: "级别", value: levelText(message.level))
                    DetailRow(label: "标签", value: message.label)
                    DetailRow(label: "文件", value: "\(message.file):\(message.line)")
                }
                .padding(8)
            }
            
            GroupBox("内容") {
                Text(message.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        }
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
    
    private func levelText(_ level: Int16) -> String {
        switch level {
        case 0: return "调试"
        case 1: return "信息"
        case 2: return "警告"
        case 3: return "错误"
        default: return "未知"
        }
    }
}

struct NetworkTaskDetailView: View {
    let task: NetworkTaskEntity
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("网络请求详情")
                .font(.headline)
            
            GroupBox("基本信息") {
                VStack(alignment: .leading, spacing: 8) {
                    DetailRow(label: "URL", value: task.url ?? "Unknown")
                    DetailRow(label: "方法", value: task.httpMethod ?? "GET")
                    DetailRow(label: "状态", value: "\(task.statusCode)")
                    DetailRow(label: "耗时", value: task.duration > 0 ? String(format: "%.2f ms", task.duration * 1000) : "N/A")
                }
                .padding(8)
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer()
        }
    }
}

struct LabelLevelView: View {
    let level: Int16
    
    var body: some View {
        Text(levelText)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(4)
    }
    
    private var levelText: String {
        switch level {
        case 0: return "调试"
        case 1: return "信息"
        case 2: return "警告"
        case 3: return "错误"
        default: return "未知"
        }
    }
    
    private var backgroundColor: Color {
        switch level {
        case 0: return Color.gray.opacity(0.2)
        case 1: return Color.blue.opacity(0.2)
        case 2: return Color.orange.opacity(0.2)
        case 3: return Color.red.opacity(0.2)
        default: return Color.gray.opacity(0.2)
        }
    }
    
    private var foregroundColor: Color {
        switch level {
        case 0: return .gray
        case 1: return .blue
        case 2: return .orange
        case 3: return .red
        default: return .gray
        }
    }
}
