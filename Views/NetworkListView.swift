// The MIT License (MIT)
//
// Copyright (c) 2024 Pulse Pro

import AppKit
import SwiftUI
import Pulse
import CoreData

struct NetworkListView: View {
    @EnvironmentObject private var controller: PulseProStoreController
    let store: LoggerStore
    @State private var searchText = ""
    @State private var filterStatus: NetworkStatusFilter = .all
    @State private var filterMethod: String = "全部"
    @State private var selectedTask: NetworkTaskEntity?
    @State private var selectedTaskID: NSManagedObjectID?

    var body: some View {
        HSplitView {
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
            .frame(minWidth: 400)

            NetworkInspectorPanel(task: selectedTask)
                .frame(minWidth: 300, idealWidth: 400)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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

            TableColumn("Code") { task in
                Text("\(task.statusCode)")
                    .foregroundStyle(statusColor(for: task))
                    .font(.system(.body, design: .monospaced).weight(.semibold))
            }
            .width(58)

            TableColumn("Method") { task in
                Text(task.httpMethod ?? "-")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
            }
            .width(76)

            TableColumn("Path") { task in
                Text(taskPath(task))
                    .lineLimit(1)
            }
            .width(min: 220, ideal: 340)

            TableColumn("Host") { task in
                Text(task.host ?? host(from: task.url))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .width(min: 160, ideal: 220)

            TableColumn("Time") { task in
                Text(Self.timeFormatter.string(from: task.createdAt))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(110)

            TableColumn("Duration") { task in
                Text(durationText(for: task))
                    .font(.system(.body, design: .monospaced))
            }
            .width(90)

            TableColumn("Request") { task in
                Text(byteText(task.requestBodySize))
                    .font(.system(.body, design: .monospaced))
            }
            .width(90)

            TableColumn("Response Size") { task in
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
            .background(Color(nsColor: .underPageBackgroundColor))
        } else {
            VStack(spacing: 12) {
                Image(systemName: "rectangle.rightthird.inset.filled")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                Text("选择一条请求查看完整检查器")
                    .font(.headline)
                Text("右侧会显示 Info、Request、Response、Query、Headers、Cookies、Timing 和 cURL。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .underPageBackgroundColor))
        }
    }
}

private enum InspectorTab: String, CaseIterable, Identifiable {
    case info = "Info"
    case request = "Request"
    case response = "Response"
    case query = "Query"
    case headers = "Headers"
    case cookies = "Cookies"
    case timing = "Timing"
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

                InspectorSection("Information") {
                    InspectorGrid(rows: [
                        ("Task", task.type?.urlSessionTaskClassName ?? "-"),
                        ("Date", dateText(task.createdAt)),
                        ("Duration", durationText(task.duration)),
                        ("Cache Policy", cachePolicyText(task.currentRequest?.cachePolicy ?? task.originalRequest?.cachePolicy)),
                        ("Timeout Interval", timeoutText(task.currentRequest?.timeoutInterval ?? task.originalRequest?.timeoutInterval)),
                        ("Scheme", URL(string: task.url ?? "")?.scheme ?? "-"),
                        ("Host", task.host ?? "-"),
                        ("Path", taskPath(task)),
                        ("Method", resolvedMethod(task))
                    ])
                }

                if let error = task.errorDebugDescription, !error.isEmpty {
                    InspectorSection("Error") {
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
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var transferSummary: some View {
        HStack(spacing: 0) {
            TransferCard(
                title: "Sent",
                symbol: "arrow.up.circle",
                total: task.totalTransferSize.requestHeaderBytesSent + task.totalTransferSize.requestBodyBytesSent,
                headerBytes: task.totalTransferSize.requestHeaderBytesSent,
                bodyBytes: task.totalTransferSize.requestBodyBytesSent
            )

            Divider().padding(.vertical, 10)

            TransferCard(
                title: "Received",
                symbol: "arrow.down.circle",
                total: task.totalTransferSize.responseHeaderBytesReceived + task.totalTransferSize.responseBodyBytesReceived,
                headerBytes: task.totalTransferSize.responseHeaderBytesReceived,
                bodyBytes: task.totalTransferSize.responseBodyBytesReceived
            )
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var networkLoadSummary: some View {
        InspectorSection("Network Load") {
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
            return "\(code) \(HTTPURLResponse.localizedString(forStatusCode: code).uppercased())"
        }
        return stateText(task.state)
    }

    private func stateText(_ state: NetworkTaskEntity.State) -> String {
        switch state {
        case .pending: return "Pending"
        case .success: return "Success"
        case .failure: return "Failure"
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
            Text("Headers: \(bytes(headerBytes))")
                .foregroundStyle(.secondary)
            Text("Body: \(bytes(bodyBytes))")
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
                phaseSection(title: "Scheduling", phases: schedulingPhases(transaction))
                phaseSection(title: "Connection", phases: connectionPhases(transaction))
                phaseSection(title: "Response", phases: responsePhases(transaction))
            } else {
                Text("No timing metrics")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var statusText: String {
        let code = Int(task.statusCode)
        if code > 0 {
            return "\(code) \(HTTPURLResponse.localizedString(forStatusCode: code).uppercased())"
        }
        return "\(task.state)"
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
            makePhase("Queued", start: t.fetchStartDate, end: t.domainLookupStartDate ?? t.connectStartDate ?? t.requestStartDate, color: .gray)
        ].compactMap { $0 }
    }

    private func connectionPhases(_ t: NetworkTransactionMetricsEntity) -> [TimingPhase] {
        [
            makePhase("DNS", start: t.domainLookupStartDate, end: t.domainLookupEndDate, color: .purple),
            makePhase("TCP", start: t.connectStartDate, end: t.connectEndDate, color: .yellow),
            makePhase("Secure", start: t.secureConnectionStartDate, end: t.secureConnectionEndDate, color: .red)
        ].compactMap { $0 }
    }

    private func responsePhases(_ t: NetworkTransactionMetricsEntity) -> [TimingPhase] {
        [
            makePhase("Request", start: t.requestStartDate, end: t.requestEndDate, color: .green),
            makePhase("Waiting", start: t.requestEndDate, end: t.responseStartDate, color: .gray),
            makePhase("Download", start: t.responseStartDate, end: t.responseEndDate, color: .blue)
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
            InspectorSection("Line") {
                InspectorGrid(rows: [
                    ("URL", request?.url ?? fallbackURL ?? "-"),
                    ("Method", resolvedMethod(task, request: request)),
                    ("Cache Policy", cachePolicyText(request?.cachePolicy)),
                    ("Timeout", timeoutText(request?.timeoutInterval))
                ])
            }

            if let request {
                InspectorSection("Options") {
                    InspectorGrid(rows: [
                        ("Allows Cellular", yesNo(request.allowsCellularAccess)),
                        ("Allows Expensive", yesNo(request.allowsExpensiveNetworkAccess)),
                        ("Allows Constrained", yesNo(request.allowsConstrainedNetworkAccess)),
                        ("Handle Cookies", yesNo(request.httpShouldHandleCookies)),
                        ("Use Pipelining", yesNo(request.httpShouldUsePipelining))
                    ])
                }

                InspectorSection("Headers") {
                    HeaderListView(headers: request.headers)
                }

                InspectorSection("Body") {
                    RequestBodyPreview(task: task)
                }
            }
        }
    }

    private func yesNo(_ value: Bool) -> String { value ? "Yes" : "No" }
    private func timeoutText(_ value: Int32?) -> String { value.map { "\($0)s" } ?? "-" }
    private func cachePolicyText(_ value: URLRequest.CachePolicy?) -> String { value.map(String.init(describing:)) ?? "-" }
}

private struct InspectorResponseView: View {
    let task: NetworkTaskEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            InspectorSection("Status") {
                InspectorGrid(rows: [
                    ("Code", "\(task.statusCode)"),
                    ("MIME", task.responseContentType ?? "-"),
                    ("Stored Size", bytes(task.responseBodySize))
                ])
            }

            if let response = task.response {
                InspectorSection("Headers") {
                    HeaderListView(headers: response.headers)
                }
            }

            InspectorSection("Body") {
                ResponseBodyPreview(task: task)
            }
        }
    }
}

private struct InspectorQueryView: View {
    let urlString: String?

    var body: some View {
        let items = queryItems(from: urlString)
        return InspectorSection("Query Items") {
            if items.isEmpty {
                Text("No query items")
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
            InspectorSection("Original Request Headers") {
                HeaderListView(headers: task.originalRequest?.headers ?? [:])
            }

            if let current = task.currentRequest, current !== task.originalRequest {
                InspectorSection("Current Request Headers") {
                    HeaderListView(headers: current.headers)
                }
            }

            InspectorSection("Response Headers") {
                HeaderListView(headers: task.response?.headers ?? [:])
            }
        }
    }
}

private struct InspectorCookiesView: View {
    let task: NetworkTaskEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            InspectorSection("Request Cookies") {
                CookieListView(rawCookie: task.originalRequest?.headers["Cookie"])
            }
            InspectorSection("Response Cookies") {
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
                InspectorSection("Timing") {
                    Text("No timing metrics")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(task.orderedTransactions, id: \.objectID) { transaction in
                    InspectorSection("Transaction \(transaction.index + 1)") {
                        InspectorGrid(rows: [
                            ("Fetch Type", String(describing: transaction.fetchType)),
                            ("Protocol", transaction.networkProtocol ?? "-"),
                            ("Local Address", transaction.localAddress ?? "-"),
                            ("Remote Address", transaction.remoteAddress ?? "-"),
                            ("Proxy", transaction.isProxyConnection ? "Yes" : "No"),
                            ("Reused", transaction.isReusedConnection ? "Yes" : "No"),
                            ("Cellular", transaction.isCellular ? "Yes" : "No"),
                            ("Expensive", transaction.isExpensive ? "Yes" : "No"),
                            ("Constrained", transaction.isConstrained ? "Yes" : "No"),
                            ("Connect Start", dateText(transaction.connectStartDate)),
                            ("Connect End", dateText(transaction.connectEndDate)),
                            ("Request Start", dateText(transaction.requestStartDate)),
                            ("Request End", dateText(transaction.requestEndDate)),
                            ("Response Start", dateText(transaction.responseStartDate)),
                            ("Response End", dateText(transaction.responseEndDate))
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
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            Text("No headers")
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
            Text("No cookies")
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
                Text(prettyBody(from: data))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("No response body")
                .foregroundStyle(.secondary)
        }
    }

    private var imageMetadata: String {
        "\(task.responseContentType ?? "image") · \(ByteCountFormatter.string(fromByteCount: task.responseBodySize, countStyle: .file))"
    }

    private func prettyBody(from data: Data) -> String {
        if
            let json = try? JSONSerialization.jsonObject(with: data),
            let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
            let prettyString = String(data: prettyData, encoding: .utf8) {
            return prettyString
        }
        if let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "Binary body (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))"
    }
}

private struct RequestBodyPreview: View {
    let task: NetworkTaskEntity

    var body: some View {
        if let data = task.requestBody?.data, !data.isEmpty {
            Text(prettyBody(from: data))
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("No request body")
                .foregroundStyle(.secondary)
        }
    }

    private func prettyBody(from data: Data) -> String {
        if
            let json = try? JSONSerialization.jsonObject(with: data),
            let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
            let prettyString = String(data: prettyData, encoding: .utf8) {
            return prettyString
        }
        if let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "Binary body (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))"
    }
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
                Text(task.url ?? "Image Preview")
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
                    Text(URL(string: task.url ?? "")?.lastPathComponent ?? "Image")
                        .font(.headline)
                    InspectorGrid(rows: [
                        ("Type", task.responseContentType ?? "-"),
                        ("Size", ByteCountFormatter.string(fromByteCount: task.responseBodySize, countStyle: .file)),
                        ("Resolution", "\(Int(image.size.width)) × \(Int(image.size.height)) px"),
                        ("Source", task.url ?? "-")
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
