// The MIT License (MIT)
//
// Copyright (c) 2024 Pulse Pro

import SwiftUI
import Pulse
import CoreData

struct MockingView: View {
    @AppStorage("mockRules") private var storedRules = "[]"
    @State private var mocks: [MockRule] = []
    @State private var isAddingRule = false
    @State private var selectedRuleID: UUID?
    
    var body: some View {
        HSplitView {
            // 模拟规则列表
            VStack(spacing: 0) {
                // 工具栏
                HStack {
                    Text("响应模拟")
                        .font(.headline)
                    Spacer()
                    Text("Pulse Pro 本地规则")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button(action: { isAddingRule = true }) {
                        Label("添加规则", systemImage: "plus")
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                
                Divider()

                Text("这些规则保存在 Pulse Pro 客户端本地，不会修改 `pulse` SDK，也不会侵入它的运行逻辑。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 12)
                
                if mocks.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("暂无模拟规则")
                            .foregroundColor(.secondary)
                        Text("添加规则来模拟网络响应")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selectedRuleID) {
                        ForEach(mocks) { rule in
                            MockRuleRow(rule: rule)
                                .tag(rule.id)
                        }
                    }
                }
            }
            .frame(minWidth: 300)
            
            // 规则详情
            if let ruleID = selectedRuleID,
               let rule = mocks.first(where: { $0.id == ruleID }) {
                MockRuleDetailView(rule: rule, onDelete: {
                    mocks.removeAll { $0.id == ruleID }
                    selectedRuleID = nil
                    persistRules()
                })
            } else {
                VStack {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("选择一个规则查看详情")
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 400)
            }
        }
        .sheet(isPresented: $isAddingRule) {
            MockRuleEditor(rule: nil) { newRule in
                mocks.append(newRule)
                persistRules()
            }
        }
        .onAppear(perform: loadRules)
    }

    private func loadRules() {
        guard let data = storedRules.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([MockRule].self, from: data) else {
            mocks = []
            return
        }
        mocks = decoded
    }

    private func persistRules() {
        guard let data = try? JSONEncoder().encode(mocks),
              let string = String(data: data, encoding: .utf8) else {
            return
        }
        storedRules = string
    }
}

struct MockRule: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var urlPattern: String
    var method: String
    var responseStatus: Int
    var responseBody: String
    var responseHeaders: [String: String]
    var delay: Double // 毫秒
    var isEnabled: Bool
}

struct MockRuleRow: View {
    let rule: MockRule
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(rule.name)
                        .font(.headline)
                    if !rule.isEnabled {
                        Text("已禁用")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                HStack {
                    Text(rule.method)
                        .font(.caption)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.2))
                        .foregroundColor(.purple)
                        .cornerRadius(2)
                    Text(rule.urlPattern)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Text("\(rule.responseStatus)")
                .foregroundColor(statusColor(rule.responseStatus))
        }
        .padding(.vertical, 4)
    }
    
    private func statusColor(_ status: Int) -> Color {
        if status >= 200 && status < 300 { return .green }
        if status >= 400 { return .red }
        return .orange
    }
}

struct MockRuleDetailView: View {
    let rule: MockRule
    let onDelete: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 头部
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.name)
                            .font(.title2.bold())
                        Text(rule.urlPattern)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Toggle("启用", isOn: .constant(rule.isEnabled))
                        .toggleStyle(.switch)
                }
                
                Divider()
                
                // 规则信息
                GroupBox("规则信息") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        GridRow {
                            Text("URL 模式").foregroundColor(.secondary)
                            Text(rule.urlPattern)
                                .font(.system(.body, design: .monospaced))
                        }
                        GridRow {
                            Text("方法").foregroundColor(.secondary)
                            Text(rule.method)
                        }
                        GridRow {
                            Text("状态码").foregroundColor(.secondary)
                            Text("\(rule.responseStatus)")
                        }
                        GridRow {
                            Text("延迟").foregroundColor(.secondary)
                            Text("\(Int(rule.delay)) ms")
                        }
                    }
                    .padding(8)
                }
                
                // 响应 Headers
                GroupBox("响应 Headers") {
                    if rule.responseHeaders.isEmpty {
                        Text("无")
                            .foregroundColor(.secondary)
                            .padding(8)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(rule.responseHeaders.keys.sorted()), id: \.self) { key in
                                Text("\(key): \(rule.responseHeaders[key] ?? "")")
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                        .padding(8)
                    }
                }
                
                // 响应体
                GroupBox("响应体") {
                    ScrollView {
                        Text(rule.responseBody)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 300)
                }
                
                // 操作按钮
                HStack {
                    Button("复制") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(rule.responseBody, forType: .string)
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("删除", role: .destructive) {
                        onDelete()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
            }
            .padding()
        }
    }
}

struct MockRuleEditor: View {
    let rule: MockRule?
    let onSave: (MockRule) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var urlPattern = ""
    @State private var method = "GET"
    @State private var responseStatus = 200
    @State private var responseBody = ""
    @State private var delay: Double = 0
    
    let methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]
    
    var body: some View {
        VStack(spacing: 0) {
            // 头部
            HStack {
                Text(rule == nil ? "添加模拟规则" : "编辑模拟规则")
                    .font(.headline)
                Spacer()
                Button("取消") {
                    dismiss()
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // 表单
            Form {
                Section("基本信息") {
                    TextField("名称", text: $name)
                    TextField("URL 模式 (支持 * 和 ?)", text: $urlPattern)
                    Picker("方法", selection: $method) {
                        ForEach(methods, id: \.self) { m in
                            Text(m).tag(m)
                        }
                    }
                    Stepper("状态码: \(responseStatus)", value: $responseStatus, in: 100...599)
                    HStack {
                        Text("延迟: \(Int(delay)) ms")
                        Slider(value: $delay, in: 0...10000, step: 100)
                    }
                }
                
                Section("响应体") {
                    TextEditor(text: $responseBody)
                        .frame(minHeight: 200)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .formStyle(.grouped)
            
            Divider()
            
            // 底部按钮
            HStack {
                Spacer()
                Button("保存") {
                    let newRule = MockRule(
                        name: name,
                        urlPattern: urlPattern,
                        method: method,
                        responseStatus: responseStatus,
                        responseBody: responseBody,
                        responseHeaders: ["Content-Type": "application/json"],
                        delay: delay,
                        isEnabled: true
                    )
                    onSave(newRule)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || urlPattern.isEmpty)
            }
            .padding()
        }
        .frame(width: 600, height: 600)
    }
}
