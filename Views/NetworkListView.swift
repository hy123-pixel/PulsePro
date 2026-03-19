// The MIT License (MIT)
//
// Copyright (c) 2024 Pulse Pro

import AppKit
import SwiftUI
import Pulse
import CoreData

private let codeEditorFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
private let codeEditorLineHeight: CGFloat = 16
private let codeEditorTextInset: CGFloat = 12
private let codeEditorApproxCharWidth: CGFloat = 7.2
private let inspectorPageBackground = Color(nsColor: .windowBackgroundColor)
private let inspectorCardBackground = Color(nsColor: .textBackgroundColor)
private let inspectorMutedBackground = Color(nsColor: .underPageBackgroundColor)
private let inspectorBorderColor = Color(nsColor: .separatorColor).opacity(0.35)
private let inspectorChromeBackground = Color(nsColor: .controlBackgroundColor)
private let inspectorTabBarBackground = Color.clear
private let inspectorGutterBackground = Color(nsColor: .underPageBackgroundColor)

private let localizedHTTPStatusDescriptions: [Int: String] = [
    100: "继续",
    101: "切换协议",
    102: "处理中",
    103: "提前提示",
    200: "成功",
    201: "已创建",
    202: "已接受",
    203: "非权威信息",
    204: "无内容",
    205: "重置内容",
    206: "部分内容",
    207: "多状态",
    208: "已报告",
    226: "IM 已使用",
    300: "多种选择",
    301: "永久重定向",
    302: "临时重定向",
    303: "查看其他位置",
    304: "未修改",
    305: "使用代理",
    307: "临时重定向",
    308: "永久重定向",
    400: "错误请求",
    401: "未授权",
    402: "需要付款",
    403: "禁止访问",
    404: "未找到",
    405: "方法不允许",
    406: "不可接受",
    407: "需要代理认证",
    408: "请求超时",
    409: "资源冲突",
    410: "资源已删除",
    411: "需要内容长度",
    412: "前置条件失败",
    413: "请求体过大",
    414: "请求地址过长",
    415: "不支持的媒体类型",
    416: "请求范围不满足",
    417: "预期失败",
    421: "请求被误导",
    422: "无法处理的实体",
    423: "资源已锁定",
    424: "依赖失败",
    425: "请求过早",
    426: "需要升级协议",
    428: "需要前置条件",
    429: "请求过多",
    431: "请求头字段过大",
    451: "因法律原因不可用",
    500: "服务器内部错误",
    501: "尚未实现",
    502: "网关错误",
    503: "服务不可用",
    504: "网关超时",
    505: "HTTP 版本不受支持",
    506: "协商变体异常",
    507: "存储空间不足",
    508: "检测到循环",
    510: "未扩展",
    511: "需要网络认证"
]

struct NetworkListView: View {
    @EnvironmentObject private var controller: PulseProStoreController
    let store: LoggerStore
    @AppStorage("networkSplitRatio") private var splitRatio = 0.5
    @State private var searchText = ""
    @State private var filterStatus: NetworkStatusFilter = .all
    @State private var filterMethod: String = "全部"
    @State private var selectedTask: NetworkTaskEntity?
    @State private var selectedTaskID: NSManagedObjectID?

    var body: some View {
        GeometryReader { proxy in
            let dividerWidth: CGFloat = 10
            let minPanelWidth: CGFloat = 320
            let availableWidth = max(proxy.size.width - dividerWidth, minPanelWidth * 2)
            let clampedRatio = min(max(splitRatio, Double(minPanelWidth / max(availableWidth, 1))), Double(1 - (minPanelWidth / max(availableWidth, 1))))
            let leftWidth = max(CGFloat(clampedRatio) * availableWidth, minPanelWidth)
            let rightWidth = max(availableWidth - leftWidth, minPanelWidth)

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    NetworkBoardHeader(
                        totalCount: tasks.count,
                        searchText: $searchText,
                        filterStatus: $filterStatus,
                        filterMethod: $filterMethod,
                        clearLogs: controller.clearWritableStore
                    )
                    Divider()
                    NetworkTaskTable(tasks: filteredTasks, selectedTaskID: $selectedTaskID)
                }
                .frame(width: leftWidth)

                SplitDividerHandle(splitRatio: $splitRatio, totalWidth: availableWidth, minPanelWidth: minPanelWidth)
                    .frame(width: dividerWidth)

                NetworkInspectorPanel(task: selectedTask)
                    .frame(width: rightWidth)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .coordinateSpace(name: "network-split-space")
            .onChange(of: selectedTaskID) { objectID in
                selectedTask = filteredTasks.first(where: { $0.objectID == objectID })
            }
            .onChange(of: filteredTasks.map(\.objectID)) { ids in
                if let current = selectedTaskID, !ids.contains(current) {
                    selectedTaskID = nil
                    selectedTask = nil
                }
            }
        }
    }

    private var tasks: [NetworkTaskEntity] {
        let request = NetworkTaskEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \NetworkTaskEntity.createdAt, ascending: false)]
        return ((try? store.viewContext.fetch(request)) as? [NetworkTaskEntity]) ?? []
    }

    private var filteredTasks: [NetworkTaskEntity] {
        tasks.filter { task in
            guard matchesSearch(task), matchesStatus(task), matchesMethod(task) else {
                return false
            }
            return true
        }
    }

    private func matchesSearch(_ task: NetworkTaskEntity) -> Bool {
        guard !searchText.isEmpty else { return true }
        let keyword = searchText.localizedLowercase
        let haystacks = [
            task.url ?? "",
            task.host ?? "",
            task.httpMethod ?? "",
            task.taskDescription ?? ""
        ]
        return haystacks.contains { $0.localizedLowercase.contains(keyword) }
    }

    private func matchesStatus(_ task: NetworkTaskEntity) -> Bool {
        let status = Int(task.statusCode)
        switch filterStatus {
        case .all:
            return true
        case .success:
            return (200..<300).contains(status)
        case .redirect:
            return (300..<400).contains(status)
        case .clientError:
            return (400..<500).contains(status)
        case .serverError:
            return status >= 500
        }
    }

    private func matchesMethod(_ task: NetworkTaskEntity) -> Bool {
        filterMethod == "全部" || resolvedMethod(task) == filterMethod
    }
}

enum NetworkStatusFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case success = "成功"
    case redirect = "重定向"
    case clientError = "客户端错误"
    case serverError = "服务端错误"

    var id: String { rawValue }
}

private struct NetworkBoardHeader: View {
    let totalCount: Int
    @Binding var searchText: String
    @Binding var filterStatus: NetworkStatusFilter
    @Binding var filterMethod: String
    let clearLogs: () -> Void
    private let methods = ["全部", "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                BoardCountPill(title: "Network", count: totalCount, isPrimary: true)
                Button("清空", role: .destructive, action: clearLogs)
                    .buttonStyle(.link)
                Spacer()
            }

            HStack(spacing: 12) {
                TextField("搜索 URL / Host / Method", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)

                Picker("状态", selection: $filterStatus) {
                    ForEach(NetworkStatusFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .frame(width: 150)

                Picker("方法", selection: $filterMethod) {
                    ForEach(methods, id: \.self) { method in
                        Text(method).tag(method)
                    }
                }
                .frame(width: 110)

                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct BoardCountPill: View {
    let title: String
    let count: Int
    let isPrimary: Bool

    var body: some View {
        Text("\(title) (\(count))")
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isPrimary ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
            .foregroundColor(isPrimary ? .accentColor : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct NetworkTaskTable: View {
    let tasks: [NetworkTaskEntity]
    @Binding var selectedTaskID: NSManagedObjectID?

    var body: some View {
        Table(tasks, selection: $selectedTaskID) {
            TableColumn("") { task in
                Image(systemName: statusSymbol(for: task))
                    .foregroundStyle(statusColor(for: task))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .width(30)

            TableColumn("状态码") { task in
                Text("\(task.statusCode)")
                    .foregroundStyle(statusColor(for: task))
                    .font(.system(.body, design: .monospaced).weight(.semibold))
            }
            .width(58)

            TableColumn("方法") { task in
                Text(task.httpMethod ?? "-")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
            }
            .width(76)

            TableColumn("路径") { task in
                Text(taskPath(task))
                    .lineLimit(1)
            }
            .width(min: 220, ideal: 340)

            TableColumn("主机") { task in
                Text(task.host ?? host(from: task.url))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .width(min: 160, ideal: 220)

            TableColumn("时间") { task in
                Text(Self.timeFormatter.string(from: task.createdAt))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(110)

            TableColumn("耗时") { task in
                Text(durationText(for: task))
                    .font(.system(.body, design: .monospaced))
            }
            .width(90)

            TableColumn("请求") { task in
                Text(byteText(task.requestBodySize))
                    .font(.system(.body, design: .monospaced))
            }
            .width(90)

            TableColumn("响应大小") { task in
                Text(responseSizeText(for: task))
                    .font(.system(.body, design: .monospaced))
            }
            .width(120)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private func durationText(for task: NetworkTaskEntity) -> String {
        guard task.duration > 0 else { return "-" }
        if task.duration >= 1 {
            return String(format: "%.3f s", task.duration)
        }
        return String(format: "%.1f ms", task.duration * 1000)
    }

    private func responseSizeText(for task: NetworkTaskEntity) -> String {
        let text = byteText(task.responseBodySize)
        return task.isFromCache ? "\(text) (cache)" : text
    }

    private func byteText(_ value: Int64) -> String {
        guard value > 0 else { return "Zero KB" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func taskPath(_ task: NetworkTaskEntity) -> String {
        guard let urlString = task.url, let url = URL(string: urlString) else {
            return task.url ?? "-"
        }
        let path = url.path.isEmpty ? "/" : url.path
        if let query = url.query, !query.isEmpty {
            return "\(path)?\(query)"
        }
        return path
    }

    private func host(from url: String?) -> String {
        guard let url, let value = URL(string: url)?.host else { return "-" }
        return value
    }

    private func statusSymbol(for task: NetworkTaskEntity) -> String {
        let status = Int(task.statusCode)
        if (200..<300).contains(status) { return "checkmark.circle.fill" }
        if (300..<400).contains(status) { return "arrow.triangle.2.circlepath.circle.fill" }
        return "exclamationmark.circle.fill"
    }

    private func statusColor(for task: NetworkTaskEntity) -> Color {
        let status = Int(task.statusCode)
        if (200..<300).contains(status) { return .green }
        if (300..<400).contains(status) { return .blue }
        if (400..<500).contains(status) { return .orange }
        if status >= 500 { return .red }
        return .secondary
    }
}

private struct NetworkInspectorPanel: View {
    let task: NetworkTaskEntity?
    @State private var selectedTab: InspectorTab = .info

    var body: some View {
        if let task {
            VStack(spacing: 0) {
                InspectorTabBar(selectedTab: $selectedTab)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch selectedTab {
                        case .info:
                            InspectorInfoView(task: task)
                        case .request:
                            InspectorRequestView(task: task, request: task.currentRequest ?? task.originalRequest, fallbackURL: task.url)
                        case .response:
                            InspectorResponseView(task: task)
                        case .query:
                            InspectorQueryView(urlString: task.currentRequest?.url ?? task.originalRequest?.url ?? task.url)
                        case .headers:
                            InspectorHeadersView(task: task)
                        case .cookies:
                            InspectorCookiesView(task: task)
                        case .timing:
                            InspectorTimingView(task: task)
                        case .curl:
                            InspectorCurlView(task: task)
                        }
                    }
                    .padding(16)
                }
            }
            .background(inspectorPageBackground)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "rectangle.rightthird.inset.filled")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                Text("选择一条请求查看完整检查器")
                    .font(.headline)
                Text("右侧会显示概览、请求、响应、查询参数、请求头、Cookie、时序和 cURL。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(inspectorPageBackground)
        }
    }
}

private enum InspectorTab: String, CaseIterable, Identifiable {
    case info = "概览"
    case request = "请求"
    case response = "响应"
    case query = "查询参数"
    case headers = "请求头"
    case cookies = "Cookie"
    case timing = "时序"
    case curl = "cURL"

    var id: String { rawValue }
}

private struct InspectorTabBar: View {
    @Binding var selectedTab: InspectorTab

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(InspectorTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(selectedTab == tab ? Color.accentColor : Color.clear)
                            .foregroundColor(selectedTab == tab ? .white : .secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}

private struct InspectorInfoView: View {
    let task: NetworkTaskEntity

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                statusSummary
                transferSummary

                InspectorSection("基本信息") {
                    InspectorGrid(rows: [
                        ("任务类型", task.type?.urlSessionTaskClassName ?? "-"),
                        ("时间", dateText(task.createdAt)),
                        ("耗时", durationText(task.duration)),
                        ("缓存策略", cachePolicyText(task.currentRequest?.cachePolicy ?? task.originalRequest?.cachePolicy)),
                        ("超时时间", timeoutText(task.currentRequest?.timeoutInterval ?? task.originalRequest?.timeoutInterval)),
                        ("协议", URL(string: task.url ?? "")?.scheme ?? "-"),
                        ("主机", task.host ?? "-"),
                        ("路径", taskPath(task)),
                        ("请求方法", resolvedMethod(task))
                    ])
                }

                if let error = task.errorDebugDescription, !error.isEmpty {
                    InspectorSection("错误信息") {
                        Text(error)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 14) {
                InspectorTimingAnalysisView(task: task)
                networkLoadSummary
            }
            .frame(width: 320, alignment: .topLeading)
        }
    }

    private var statusSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: statusSymbol(for: task))
                    .foregroundStyle(statusColor(for: task))
                Text(statusText)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(statusColor(for: task))
                Spacer()
                Text(durationText(task.duration))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Text(task.url ?? "-")
                .font(.system(size: 14, weight: .medium))
                .textSelection(.enabled)
        }
        .padding(14)
        .background(inspectorCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(inspectorBorderColor, lineWidth: 1)
        )
    }

    private var transferSummary: some View {
        HStack(spacing: 0) {
            TransferCard(
                title: "发送",
                symbol: "arrow.up.circle",
                total: task.totalTransferSize.requestHeaderBytesSent + task.totalTransferSize.requestBodyBytesSent,
                headerBytes: task.totalTransferSize.requestHeaderBytesSent,
                bodyBytes: task.totalTransferSize.requestBodyBytesSent
            )

            Divider().padding(.vertical, 10)

            TransferCard(
                title: "接收",
                symbol: "arrow.down.circle",
                total: task.totalTransferSize.responseHeaderBytesReceived + task.totalTransferSize.responseBodyBytesReceived,
                headerBytes: task.totalTransferSize.responseHeaderBytesReceived,
                bodyBytes: task.totalTransferSize.responseBodyBytesReceived
            )
        }
        .padding(8)
        .background(inspectorCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(inspectorBorderColor, lineWidth: 1)
        )
    }

    private var networkLoadSummary: some View {
        InspectorSection("网络传输") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Label(bytes(task.totalTransferSize.requestHeaderBytesSent + task.totalTransferSize.requestBodyBytesSent), systemImage: "arrow.up.circle")
                    Label(bytes(task.totalTransferSize.responseHeaderBytesReceived + task.totalTransferSize.responseBodyBytesReceived), systemImage: "arrow.down.circle")
                }
                .foregroundStyle(.secondary)

                Text(task.url ?? "-")
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var statusText: String {
        let code = Int(task.statusCode)
        if code > 0 {
            return "\(code) \(localizedHTTPStatusText(for: code))"
        }
        return stateText(task.state)
    }

    private func stateText(_ state: NetworkTaskEntity.State) -> String {
        switch state {
        case .pending: return "等待中"
        case .success: return "成功"
        case .failure: return "失败"
        }
    }
}

private struct TransferCard: View {
    let title: String
    let symbol: String
    let total: Int64
    let headerBytes: Int64
    let bodyBytes: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(bytes(total))
                        .font(.system(size: 18, weight: .bold))
                }
            }
            Text("请求头：\(bytes(headerBytes))")
                .foregroundStyle(.secondary)
            Text("请求体：\(bytes(bodyBytes))")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}

private struct InspectorTimingAnalysisView: View {
    let task: NetworkTaskEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: statusSymbol(for: task))
                    .foregroundStyle(statusColor(for: task))
                Text(statusText)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(statusColor(for: task))
            }

            if let transaction = task.orderedTransactions.first {
                phaseSection(title: "调度", phases: schedulingPhases(transaction))
                phaseSection(title: "连接", phases: connectionPhases(transaction))
                phaseSection(title: "响应", phases: responsePhases(transaction))
            } else {
                Text("暂无时序数据")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(inspectorCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(inspectorBorderColor, lineWidth: 1)
        )
    }

    private var statusText: String {
        let code = Int(task.statusCode)
        if code > 0 {
            return "\(code) \(localizedHTTPStatusText(for: code))"
        }
        return stateText(task.state)
    }

    private func stateText(_ state: NetworkTaskEntity.State) -> String {
        switch state {
        case .pending: return "等待中"
        case .success: return "成功"
        case .failure: return "失败"
        }
    }

    private func phaseSection(title: String, phases: [TimingPhase]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            ForEach(phases) { phase in
                TimingPhaseRow(phase: phase, maxDuration: max(phases.map(\.duration).max() ?? 0.001, 0.001))
            }
        }
    }

    private func schedulingPhases(_ t: NetworkTransactionMetricsEntity) -> [TimingPhase] {
        [
            makePhase("排队", start: t.fetchStartDate, end: t.domainLookupStartDate ?? t.connectStartDate ?? t.requestStartDate, color: .gray)
        ].compactMap { $0 }
    }

    private func connectionPhases(_ t: NetworkTransactionMetricsEntity) -> [TimingPhase] {
        [
            makePhase("DNS 解析", start: t.domainLookupStartDate, end: t.domainLookupEndDate, color: .purple),
            makePhase("TCP 连接", start: t.connectStartDate, end: t.connectEndDate, color: .yellow),
            makePhase("TLS 握手", start: t.secureConnectionStartDate, end: t.secureConnectionEndDate, color: .red)
        ].compactMap { $0 }
    }

    private func responsePhases(_ t: NetworkTransactionMetricsEntity) -> [TimingPhase] {
        [
            makePhase("发送请求", start: t.requestStartDate, end: t.requestEndDate, color: .green),
            makePhase("等待响应", start: t.requestEndDate, end: t.responseStartDate, color: .gray),
            makePhase("下载响应", start: t.responseStartDate, end: t.responseEndDate, color: .blue)
        ].compactMap { $0 }
    }

    private func makePhase(_ title: String, start: Date?, end: Date?, color: Color) -> TimingPhase? {
        guard let start, let end else { return nil }
        let duration = max(end.timeIntervalSince(start), 0)
        guard duration > 0 else { return nil }
        return TimingPhase(title: title, duration: duration, color: color)
    }
}

private struct TimingPhase: Identifiable {
    let id = UUID()
    let title: String
    let duration: Double
    let color: Color
}

private struct TimingPhaseRow: View {
    let phase: TimingPhase
    let maxDuration: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(phase.title)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 4)
                    .fill(phase.color)
                    .frame(width: max(proxy.size.width * CGFloat(phase.duration / maxDuration), 3), height: 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 14)
            Text(durationText(phase.duration))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)
        }
    }
}

private struct InspectorRequestView: View {
    let task: NetworkTaskEntity
    let request: NetworkRequestEntity?
    let fallbackURL: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            InspectorSection("请求行") {
                InspectorGrid(rows: [
                    ("URL", request?.url ?? fallbackURL ?? "-"),
                    ("请求方法", resolvedMethod(task, request: request)),
                    ("缓存策略", cachePolicyText(request?.cachePolicy)),
                    ("超时时间", timeoutText(request?.timeoutInterval))
                ])
            }

            if let request {
                InspectorSection("请求选项") {
                    InspectorGrid(rows: [
                        ("允许蜂窝网络", yesNo(request.allowsCellularAccess)),
                        ("允许高成本网络", yesNo(request.allowsExpensiveNetworkAccess)),
                        ("允许受限网络", yesNo(request.allowsConstrainedNetworkAccess)),
                        ("自动处理 Cookie", yesNo(request.httpShouldHandleCookies)),
                        ("启用管线化", yesNo(request.httpShouldUsePipelining))
                    ])
                }

                InspectorSection("请求头") {
                    HeaderListView(headers: request.headers)
                }

                InspectorSection("请求体") {
                    RequestBodyPreview(task: task)
                }
            }
        }
    }

    private func yesNo(_ value: Bool) -> String { value ? "是" : "否" }
    private func timeoutText(_ value: Int32?) -> String { value.map { "\($0)s" } ?? "-" }
    private func cachePolicyText(_ value: URLRequest.CachePolicy?) -> String { value.map(String.init(describing:)) ?? "-" }
}

private struct InspectorResponseView: View {
    let task: NetworkTaskEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            InspectorSection("状态") {
                InspectorGrid(rows: [
                    ("状态码", "\(task.statusCode)"),
                    ("响应类型", task.responseContentType ?? "-"),
                    ("存储大小", bytes(task.responseBodySize))
                ])
            }

            if let response = task.response {
                InspectorSection("响应头") {
                    HeaderListView(headers: response.headers)
                }
            }

            InspectorSection("响应体") {
                ResponseBodyPreview(task: task)
            }
        }
    }
}

private struct InspectorQueryView: View {
    let urlString: String?

    var body: some View {
        let items = queryItems(from: urlString)
        return InspectorSection("查询参数") {
            if items.isEmpty {
                Text("暂无查询参数")
                    .foregroundStyle(.secondary)
            } else {
                InspectorGrid(rows: items.map { ($0.name, $0.value ?? "") })
            }
        }
    }

    private func queryItems(from urlString: String?) -> [URLQueryItem] {
        guard let urlString, let components = URLComponents(string: urlString) else { return [] }
        return components.queryItems ?? []
    }
}

private struct InspectorHeadersView: View {
    let task: NetworkTaskEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            InspectorSection("原始请求头") {
                HeaderListView(headers: task.originalRequest?.headers ?? [:])
            }

            if let current = task.currentRequest, current !== task.originalRequest {
                InspectorSection("当前请求头") {
                    HeaderListView(headers: current.headers)
                }
            }

            InspectorSection("响应头") {
                HeaderListView(headers: task.response?.headers ?? [:])
            }
        }
    }
}

private struct InspectorCookiesView: View {
    let task: NetworkTaskEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            InspectorSection("请求 Cookie") {
                CookieListView(rawCookie: task.originalRequest?.headers["Cookie"])
            }
            InspectorSection("响应 Cookie") {
                CookieListView(rawCookie: task.response?.headers["Set-Cookie"])
            }
        }
    }
}

private struct InspectorTimingView: View {
    let task: NetworkTaskEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if task.orderedTransactions.isEmpty {
                InspectorSection("时序") {
                    Text("暂无时序数据")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(task.orderedTransactions, id: \.objectID) { transaction in
                    InspectorSection("事务 \(transaction.index + 1)") {
                        InspectorGrid(rows: [
                            ("加载类型", String(describing: transaction.fetchType)),
                            ("协议", transaction.networkProtocol ?? "-"),
                            ("本地地址", transaction.localAddress ?? "-"),
                            ("远端地址", transaction.remoteAddress ?? "-"),
                            ("是否代理", transaction.isProxyConnection ? "是" : "否"),
                            ("是否复用连接", transaction.isReusedConnection ? "是" : "否"),
                            ("是否蜂窝网络", transaction.isCellular ? "是" : "否"),
                            ("是否高成本网络", transaction.isExpensive ? "是" : "否"),
                            ("是否受限网络", transaction.isConstrained ? "是" : "否"),
                            ("开始连接", dateText(transaction.connectStartDate)),
                            ("连接结束", dateText(transaction.connectEndDate)),
                            ("开始请求", dateText(transaction.requestStartDate)),
                            ("请求结束", dateText(transaction.requestEndDate)),
                            ("开始响应", dateText(transaction.responseStartDate)),
                            ("响应结束", dateText(transaction.responseEndDate))
                        ])
                    }
                }
            }
        }
    }
}

private struct InspectorCurlView: View {
    let task: NetworkTaskEntity

    var body: some View {
        InspectorSection("cURL") {
            Text(curlCommand)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var curlCommand: String {
        guard let request = task.currentRequest ?? task.originalRequest else { return "curl" }
        var parts = ["curl"]
        if let method = request.httpMethod, method != "GET" {
            parts.append("-X \(method)")
        }
        for key in request.headers.keys.sorted() {
            if let value = request.headers[key] {
                parts.append("-H '\(escape("\(key): \(value)"))'")
            }
        }
        if let url = request.url ?? task.url {
            parts.append("'\(escape(url))'")
        }
        return parts.joined(separator: " \\\n  ")
    }

    private func escape(_ string: String) -> String {
        string.replacingOccurrences(of: "'", with: "'\\''")
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    let isCollapsible: Bool
    @ViewBuilder let content: Content
    @State private var isExpanded = true

    init(_ title: String, isCollapsible: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        self.isCollapsible = isCollapsible
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !isCollapsible || isExpanded {
                content
            }
        }
        .padding(14)
        .background(inspectorCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(inspectorBorderColor, lineWidth: 1)
        )
    }

    private var header: some View {
        Button {
            guard isCollapsible else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                if isCollapsible {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.headline)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SplitDividerHandle: View {
    @Binding var splitRatio: Double
    let totalWidth: CGFloat
    let minPanelWidth: CGFloat
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            Rectangle()
                .fill(Color.secondary.opacity(0.18))
                .frame(width: 1)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.secondary.opacity(0.14))
                .frame(width: 6, height: 42)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering && !isHovering {
                NSCursor.resizeLeftRight.push()
                isHovering = true
            } else if !hovering && isHovering {
                NSCursor.pop()
                isHovering = false
            }
        }
        .onDisappear {
            if isHovering {
                NSCursor.pop()
                isHovering = false
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("network-split-space"))
                .onChanged { value in
                    let minRatio = Double(minPanelWidth / max(totalWidth, 1))
                    let maxRatio = 1 - minRatio
                    let proposed = Double(value.location.x / max(totalWidth, 1))
                    splitRatio = min(max(proposed, minRatio), maxRatio)
                }
        )
    }
}

private struct InspectorGrid: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top) {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .leading)
                    Text(row.1.isEmpty ? "-" : row.1)
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(.vertical, 6)

                if index != rows.count - 1 {
                    Divider()
                }
            }
        }
        .font(.system(size: 12.5))
    }
}

private struct HeaderListView: View {
    let headers: [String: String]

    var body: some View {
        if headers.isEmpty {
            Text("暂无请求头")
                .foregroundStyle(.secondary)
        } else {
            InspectorGrid(rows: headers.keys.sorted().map { ($0, headers[$0] ?? "") })
        }
    }
}

private struct CookieListView: View {
    let rawCookie: String?

    var body: some View {
        let rows = parseCookies(rawCookie)
        if rows.isEmpty {
            Text("暂无 Cookie")
                .foregroundStyle(.secondary)
        } else {
            InspectorGrid(rows: rows)
        }
    }

    private func parseCookies(_ rawCookie: String?) -> [(String, String)] {
        guard let rawCookie, !rawCookie.isEmpty else { return [] }
        return rawCookie
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { fragment in
                let parts = fragment.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    return (parts[0], parts[1])
                }
                return (fragment, "")
            }
    }
}

private struct ResponseBodyPreview: View {
    let task: NetworkTaskEntity
    @State private var isShowingImagePreview = false

    var body: some View {
        if let data = task.responseBody?.data {
            if let image = NSImage(data: data) {
                VStack(alignment: .leading, spacing: 12) {
                    Button("打开图片预览") {
                        isShowingImagePreview = true
                    }
                    .buttonStyle(.bordered)

                    Text(imageMetadata)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .sheet(isPresented: $isShowingImagePreview) {
                    ImagePreviewSheet(image: image, task: task)
                }
            } else {
                BodyContentView(content: formattedBody(from: data))
            }
        } else {
            Text("暂无响应体")
                .foregroundStyle(.secondary)
        }
    }

    private var imageMetadata: String {
        "\(task.responseContentType ?? "image") · \(ByteCountFormatter.string(fromByteCount: task.responseBodySize, countStyle: .file))"
    }

    private func formattedBody(from data: Data) -> BodyContent {
        if
            let json = try? JSONSerialization.jsonObject(with: data),
            let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
            let prettyString = String(data: prettyData, encoding: .utf8) {
            return .json(prettyString)
        }
        if let string = String(data: data, encoding: .utf8) {
            return .plain(string)
        }
        return .plain("二进制内容（\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))）")
    }
}

private struct RequestBodyPreview: View {
    let task: NetworkTaskEntity

    var body: some View {
        if let data = task.requestBody?.data, !data.isEmpty {
            BodyContentView(content: formattedBody(from: data))
        } else {
            Text("暂无请求体")
                .foregroundStyle(.secondary)
        }
    }

    private func formattedBody(from data: Data) -> BodyContent {
        if
            let json = try? JSONSerialization.jsonObject(with: data),
            let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
            let prettyString = String(data: prettyData, encoding: .utf8) {
            return .json(prettyString)
        }
        if let string = String(data: data, encoding: .utf8) {
            return .plain(string)
        }
        return .plain("二进制内容（\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))）")
    }
}

private enum BodyContent {
    case json(String)
    case plain(String)

    var rawValue: String {
        switch self {
        case .json(let value), .plain(let value):
            return value
        }
    }

    var isJSON: Bool {
        if case .json = self { return true }
        return false
    }
}

private struct BodyContentView: View {
    let content: BodyContent

    var body: some View {
        switch content {
        case .json(let source):
            EditorCodeView(text: source, attributedText: makeHighlightedJSON(source))
        case .plain(let text):
            EditorCodeView(text: text, attributedText: nil)
        }
    }
}

private struct EditorCodeView: View {
    let text: String
    let attributedText: AttributedString?
    @State private var collapsedBlockIDs: Set<Int> = []

    private var renderedJSON: RenderedJSON {
        renderJSONText(from: text, blocks: makeJSONFoldBlocks(from: text), collapsedBlockIDs: collapsedBlockIDs)
    }

    private var displayedText: String { renderedJSON.text }

    private var displayedAttributedText: AttributedString? {
        guard attributedText != nil else { return nil }
        return makeHighlightedJSON(displayedText)
    }

    private var lineCount: Int {
        max(displayedText.components(separatedBy: .newlines).count, 1)
    }

    private var contentHeight: CGFloat {
        CGFloat(lineCount) * codeEditorLineHeight + 24
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("JSON")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                if attributedText != nil {
                    Button("展开全部") {
                        collapsedBlockIDs.removeAll()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(inspectorChromeBackground)

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    LineNumberGutterView(
                        lineCount: lineCount,
                        visibleBlocks: renderedJSON.visibleBlocks,
                        onToggleFold: toggleFold(for:)
                    )
                        .frame(width: 72, height: contentHeight, alignment: .top)

                    Divider()

                    JSONSourceTextView(text: displayedText, attributedText: displayedAttributedText, contentHeight: contentHeight)
                        .frame(maxWidth: .infinity, minHeight: contentHeight, maxHeight: contentHeight, alignment: .leading)
                }
                .background(inspectorCardBackground)
            }
            .background(inspectorCardBackground)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(inspectorBorderColor, lineWidth: 1)
        )
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .leading)
    }

    private func toggleFold(for blockID: Int) {
        if collapsedBlockIDs.contains(blockID) {
            collapsedBlockIDs.remove(blockID)
        } else {
            collapsedBlockIDs.insert(blockID)
        }
    }
}

private struct JSONSourceTextView: NSViewRepresentable {
    let text: String
    let attributedText: AttributedString?
    let contentHeight: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = HorizontalOnlyScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.verticalScrollElasticity = .none
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(containerSize: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = false
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = BracketSelectableTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 400), textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = true
        textView.minSize = NSSize(width: 0, height: contentHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: codeEditorTextInset, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.font = codeEditorFont
        textView.string = text
        textView.setAttributedString(makeSourceAttributedString(text, attributedText: attributedText))
        textView.frame = NSRect(x: 0, y: 0, width: 800, height: contentHeight)

        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? BracketSelectableTextView else { return }
        textView.string = text
        textView.setAttributedString(makeSourceAttributedString(text, attributedText: attributedText))
        textView.frame.size.height = contentHeight
        textView.minSize.height = contentHeight
    }
}

private final class HorizontalOnlyScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        let absX = abs(event.scrollingDeltaX)
        let absY = abs(event.scrollingDeltaY)

        if absY > absX {
            nextResponder?.scrollWheel(with: event)
            return
        }

        super.scrollWheel(with: event)
    }
}

private struct LineNumberGutterView: View {
    let lineCount: Int
    let visibleBlocks: [VisibleFoldBlock]
    let onToggleFold: (Int) -> Void

    private let rowHeight: CGFloat = codeEditorLineHeight

    private var blocksByLine: [Int: VisibleFoldBlock] {
        Dictionary(uniqueKeysWithValues: visibleBlocks.map { ($0.displayedStartLine, $0) })
    }

    var body: some View {
        LazyVStack(alignment: .trailing, spacing: 0) {
            ForEach(1...lineCount, id: \.self) { line in
                HStack(spacing: 6) {
                    if let visibleBlock = blocksByLine[line] {
                        Button {
                            onToggleFold(visibleBlock.block.id)
                        } label: {
                            Image(systemName: visibleBlock.isCollapsed ? "chevron.right" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 10, height: 10)
                                .frame(width: 22, height: rowHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(width: 22, alignment: .center)
                    } else {
                        Color.clear.frame(width: 22, height: rowHeight)
                    }

                    Text("\(line)")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(inspectorCardBackground)
    }
}

private final class BracketSelectableTextView: NSTextView {
    private var bracketPairs: [Int: Int] = [:]
    private var highlightedBracketRanges: [NSRange] = []
    private let bracketHighlightColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.28)

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        setupSelectionObserver()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSelectionObserver()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2,
           let range = selectedBracketContentsRange(for: event) {
            setSelectedRange(range)
            updateBracketHighlight()
            return
        }
        super.mouseDown(with: event)
    }

    func setAttributedString(_ attributedString: NSAttributedString) {
        textStorage?.setAttributedString(attributedString)
        bracketPairs = makeBracketPairs(from: attributedString.string)
        updateBracketHighlight()
    }

    private func selectedBracketContentsRange(for event: NSEvent) -> NSRange? {
        let point = convert(event.locationInWindow, from: nil)
        var index = characterIndexForInsertion(at: point)
        let string = (self.string as NSString)
        guard string.length > 0 else { return nil }

        if index >= string.length { index = max(string.length - 1, 0) }

        let current = Character(UnicodeScalar(string.character(at: index)) ?? " ")
        if let close = bracketPairs[index], isOpeningBracket(current) {
            return NSRange(location: index, length: max(close - index + 1, 0))
        }
        if let open = bracketPairs[index], isClosingBracket(current) {
            return NSRange(location: open, length: max(index - open + 1, 0))
        }

        if index > 0 {
            let previousIndex = index - 1
            let previous = Character(UnicodeScalar(string.character(at: previousIndex)) ?? " ")
            if let close = bracketPairs[previousIndex], isOpeningBracket(previous) {
                return NSRange(location: previousIndex, length: max(close - previousIndex + 1, 0))
            }
            if let open = bracketPairs[previousIndex], isClosingBracket(previous) {
                return NSRange(location: open, length: max(previousIndex - open + 1, 0))
            }
        }

        return nil
    }

    private func updateBracketHighlight() {
        guard let layoutManager else { return }

        for range in highlightedBracketRanges {
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
        }
        highlightedBracketRanges.removeAll()

        guard let ranges = matchingBracketRangesForCurrentInsertionPoint() else { return }
        for range in ranges {
            layoutManager.addTemporaryAttribute(.backgroundColor, value: bracketHighlightColor, forCharacterRange: range)
            layoutManager.addTemporaryAttribute(.foregroundColor, value: NSColor.labelColor, forCharacterRange: range)
        }
        highlightedBracketRanges = ranges
    }

    private func matchingBracketRangesForCurrentInsertionPoint() -> [NSRange]? {
        let string = self.string as NSString
        guard string.length > 0 else { return nil }

        let caret = selectedRange().location
        let candidates = [caret, max(caret - 1, 0)]

        for candidate in candidates where candidate < string.length {
            let char = Character(UnicodeScalar(string.character(at: candidate)) ?? " ")

            if isOpeningBracket(char), let close = bracketPairs[candidate] {
                return [NSRange(location: candidate, length: 1), NSRange(location: close, length: 1)]
            }

            if isClosingBracket(char), let open = bracketPairs[candidate] {
                return [NSRange(location: open, length: 1), NSRange(location: candidate, length: 1)]
            }
        }

        return nil
    }

    private func setupSelectionObserver() {
        NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            self?.updateBracketHighlight()
        }
    }
}

private func makeSourceAttributedString(_ text: String, attributedText: AttributedString?) -> NSAttributedString {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.minimumLineHeight = codeEditorLineHeight
    paragraphStyle.maximumLineHeight = codeEditorLineHeight

    if let attributedText {
        let mutable = NSMutableAttributedString(attributedText)
        mutable.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: mutable.length))
        mutable.addAttribute(.font, value: codeEditorFont, range: NSRange(location: 0, length: mutable.length))
        return mutable
    }
    return NSAttributedString(string: text, attributes: [
        .foregroundColor: NSColor.labelColor,
        .font: codeEditorFont,
        .paragraphStyle: paragraphStyle
    ])
}

private func makeBracketPairs(from string: String) -> [Int: Int] {
    let nsString = string as NSString
    var stack: [(Character, Int)] = []
    var pairs: [Int: Int] = [:]
    var isInsideString = false
    var isEscaped = false

    for index in 0..<nsString.length {
        let char = Character(UnicodeScalar(nsString.character(at: index)) ?? " ")

        if isInsideString {
            if isEscaped {
                isEscaped = false
            } else if char == "\\" {
                isEscaped = true
            } else if char == "\"" {
                isInsideString = false
            }
            continue
        }

        if char == "\"" {
            isInsideString = true
            continue
        }

        if isOpeningBracket(char) {
            stack.append((char, index))
            continue
        }

        if isClosingBracket(char),
           let last = stack.last,
           bracketsMatch(open: last.0, close: char) {
            stack.removeLast()
            pairs[last.1] = index
            pairs[index] = last.1
        }
    }

    return pairs
}

private func isOpeningBracket(_ char: Character) -> Bool {
    char == "{" || char == "[" || char == "("
}

private func isClosingBracket(_ char: Character) -> Bool {
    char == "}" || char == "]" || char == ")"
}

private func bracketsMatch(open: Character, close: Character) -> Bool {
    (open == "{" && close == "}") ||
    (open == "[" && close == "]") ||
    (open == "(" && close == ")")
}

private struct JSONFoldBlock {
    let openChar: Character
    let closeChar: Character
    let openIndex: Int
    let closeIndex: Int
    let depth: Int

    let startLine: Int
    let endLine: Int
    let leadingSpaces: Int

    var id: Int { openIndex }

    var title: String {
        "L\(startLine) \(openChar)…\(closeChar)"
    }
}

private struct VisibleFoldBlock: Identifiable {
    let block: JSONFoldBlock
    let isCollapsed: Bool
    let displayedStartLine: Int

    var id: Int { block.id }
}

private struct RenderedJSON {
    let text: String
    let visibleBlocks: [VisibleFoldBlock]

    var lineCount: Int {
        max(text.components(separatedBy: .newlines).count, 1)
    }
}

private func renderJSONText(from string: String, blocks: [JSONFoldBlock], collapsedBlockIDs: Set<Int>) -> RenderedJSON {
    guard !blocks.isEmpty else {
        return RenderedJSON(text: string, visibleBlocks: [])
    }

    let nsString = string as NSString
    let blocksByOpenIndex = Dictionary(uniqueKeysWithValues: blocks.map { ($0.openIndex, $0) })
    var visibleBlocks: [VisibleFoldBlock] = []
    var result = ""
    var index = 0
    var displayedLine = 1

    while index < nsString.length {
        if let block = blocksByOpenIndex[index] {
            let isCollapsed = collapsedBlockIDs.contains(block.id)
            visibleBlocks.append(VisibleFoldBlock(block: block, isCollapsed: isCollapsed, displayedStartLine: displayedLine))

            if isCollapsed {
                result += String(block.openChar) + "…" + String(block.closeChar)
                index = block.closeIndex + 1
                continue
            }
        }

        let char = Character(UnicodeScalar(nsString.character(at: index)) ?? " ")
        result.append(char)
        if char == "\n" {
            displayedLine += 1
        }
        index += 1
    }

    return RenderedJSON(text: result, visibleBlocks: visibleBlocks)
}

private func makeJSONFoldBlocks(from string: String) -> [JSONFoldBlock] {
    let nsString = string as NSString
    var stack: [(char: Character, index: Int, depth: Int)] = []
    var blocks: [JSONFoldBlock] = []
    var isInsideString = false
    var isEscaped = false
    var currentLine = 1
    var startLines: [Int: Int] = [:]

    for index in 0..<nsString.length {
        let char = Character(UnicodeScalar(nsString.character(at: index)) ?? " ")

        if isInsideString {
            if isEscaped {
                isEscaped = false
            } else if char == "\\" {
                isEscaped = true
            } else if char == "\"" {
                isInsideString = false
            }
            continue
        }

        if char == "\"" {
            isInsideString = true
            continue
        }

        if isOpeningBracket(char) {
            stack.append((char, index, stack.count))
            startLines[index] = currentLine
            continue
        }

        if isClosingBracket(char), let last = stack.last, bracketsMatch(open: last.char, close: char) {
            stack.removeLast()
            let startLine = startLines[last.index] ?? currentLine
            let endLine = currentLine
            if endLine > startLine {
                blocks.append(JSONFoldBlock(openChar: last.char, closeChar: char, openIndex: last.index, closeIndex: index, depth: last.depth, startLine: startLine, endLine: endLine, leadingSpaces: leadingWhitespaceCount(in: nsString, at: last.index)))
            }
        }

        if char == "\n" {
            currentLine += 1
        }
    }

    return blocks.sorted { $0.openIndex < $1.openIndex }
}

private func leadingWhitespaceCount(in string: NSString, at index: Int) -> Int {
    var lineStart = index
    while lineStart > 0 {
        let previous = Character(UnicodeScalar(string.character(at: lineStart - 1)) ?? " ")
        if previous == "\n" { break }
        lineStart -= 1
    }

    var count = 0
    var cursor = lineStart
    while cursor < string.length {
        let char = Character(UnicodeScalar(string.character(at: cursor)) ?? " ")
        if char == " " {
            count += 1
            cursor += 1
            continue
        }
        break
    }

    return count
}

private func makeHighlightedJSON(_ string: String) -> AttributedString {
    let nsString = string as NSString
    let fullRange = NSRange(location: 0, length: nsString.length)
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.minimumLineHeight = codeEditorLineHeight
    paragraphStyle.maximumLineHeight = codeEditorLineHeight

    let attributed = NSMutableAttributedString(string: string, attributes: [
        .foregroundColor: NSColor.labelColor,
        .font: codeEditorFont,
        .paragraphStyle: paragraphStyle
    ])

    let patterns: [(String, NSColor)] = [
        (#"\"(?:\\.|[^\"\\])*\"\s*:(?=\s)"#, NSColor.systemRed),
        (#"(?<=:\s)\"(?:\\.|[^\"\\])*\""#, NSColor.systemBlue),
        (#"\b-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, NSColor.systemGreen),
        (#"\btrue\b|\bfalse\b"#, NSColor.systemPurple),
        (#"\bnull\b"#, NSColor.systemOrange)
    ]

    for (pattern, color) in patterns {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
        regex.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let match else { return }
            attributed.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }

    return AttributedString(attributed)
}

private func resolvedMethod(_ task: NetworkTaskEntity, request: NetworkRequestEntity? = nil) -> String {
    task.httpMethod ?? request?.httpMethod ?? task.currentRequest?.httpMethod ?? task.originalRequest?.httpMethod ?? "-"
}

private struct ImagePreviewSheet: View {
    let image: NSImage
    let task: NetworkTaskEntity
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(task.url ?? "图片预览")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
            .padding(12)

            Divider()

            HSplitView {
                GeometryReader { proxy in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .background(Color.black.opacity(0.2))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(URL(string: task.url ?? "")?.lastPathComponent ?? "图片")
                        .font(.headline)
                    InspectorGrid(rows: [
                        ("类型", task.responseContentType ?? "-"),
                        ("大小", ByteCountFormatter.string(fromByteCount: task.responseBodySize, countStyle: .file)),
                        ("分辨率", "\(Int(image.size.width)) × \(Int(image.size.height)) px"),
                        ("来源", task.url ?? "-")
                    ])
                    Spacer()
                }
                .padding(16)
                .frame(minWidth: 320)
            }
        }
        .frame(minWidth: 900, minHeight: 560)
    }
}

private func bytes(_ value: Int64) -> String {
    guard value > 0 else { return "-" }
    return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
}

private func localizedHTTPStatusText(for code: Int) -> String {
    localizedHTTPStatusDescriptions[code] ?? HTTPURLResponse.localizedString(forStatusCode: code)
}

private func cachePolicyText(_ value: URLRequest.CachePolicy?) -> String {
    value.map(String.init(describing:)) ?? "-"
}

private func timeoutText(_ value: Int32?) -> String {
    value.map { "\($0)s" } ?? "-"
}

private func taskPath(_ task: NetworkTaskEntity) -> String {
    guard let urlString = task.url, let url = URL(string: urlString) else {
        return task.url ?? "-"
    }
    let path = url.path.isEmpty ? "/" : url.path
    if let query = url.query, !query.isEmpty {
        return "\(path)?\(query)"
    }
    return path
}

private func statusSymbol(for task: NetworkTaskEntity) -> String {
    let status = Int(task.statusCode)
    if (200..<300).contains(status) { return "checkmark.circle.fill" }
    if (300..<400).contains(status) { return "arrow.triangle.2.circlepath.circle.fill" }
    return "exclamationmark.circle.fill"
}

private func statusColor(for task: NetworkTaskEntity) -> Color {
    let status = Int(task.statusCode)
    if (200..<300).contains(status) { return .green }
    if (300..<400).contains(status) { return .blue }
    if (400..<500).contains(status) { return .orange }
    if status >= 500 { return .red }
    return .secondary
}

private func durationText(_ duration: Double) -> String {
    guard duration > 0 else { return "-" }
    if duration >= 1 { return String(format: "%.3f s", duration) }
    return String(format: "%.1f ms", duration * 1000)
}

private func dateText(_ date: Date?) -> String {
    guard let date else { return "-" }
    return InspectorDateFormatter.shared.string(from: date)
}

private enum InspectorDateFormatter {
    static let shared: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
}
