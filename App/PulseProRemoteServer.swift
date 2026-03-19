import Foundation
import Network
import CoreData
import Pulse

@MainActor
final class PulseProRemoteServer: ObservableObject {
    enum State: String {
        case stopped = "未启动"
        case listening = "未连接"
        case connecting = "连接中"
        case connected = "已连接"
        case failed = "启动失败"
    }

    struct ConnectedDevice: Identifiable, Equatable {
        let id: String
        let name: String
        let representativeDeviceID: UUID
        let appNames: [String]
        let modelName: String?
        let systemVersionText: String
        let isActive: Bool
        let isStreaming: Bool

        var appName: String? {
            appNames.first
        }
    }

    @Published private(set) var state: State = .stopped
    @Published private(set) var lastError: String?
    @Published private(set) var recentEvents: [String] = []
    @Published private(set) var serviceName: String = Host.current().localizedName ?? "Pulse Pro"
    @Published private(set) var isStreaming = false
    @Published private(set) var connectedDevices: [ConnectedDevice] = []
    @Published private(set) var activeDeviceID: UUID?

    var connectedDeviceName: String? {
        connectedDevices.first(where: { $0.isActive })?.name
    }

    var connectedAppName: String? {
        connectedDevices.first(where: { $0.isActive })?.appName
    }

    var connectedDeviceModelName: String? {
        connectedDevices.first(where: { $0.isActive })?.modelName
    }

    var connectedDeviceSystemVersionText: String? {
        connectedDevices.first(where: { $0.isActive })?.systemVersionText
    }

    private weak var store: LoggerStore?
    private var listener: NWListener?
    private var connections: [UUID: ServerConnection] = [:]
    private var connectionToDeviceID: [UUID: UUID] = [:]
    private var sessions: [UUID: RemoteSession] = [:]
    private var pingTasks: [UUID: DispatchWorkItem] = [:]

    func start(with store: LoggerStore) {
        self.store = store
        stop()
        record("准备启动远程接收器")

        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true

            let listener = try NWListener(using: parameters, on: .any)
            serviceName = Host.current().localizedName ?? "Pulse Pro"
            listener.service = NWListener.Service(
                name: serviceName,
                type: "_pulse._tcp",
                domain: nil,
                txtRecord: NWTXTRecord(["protected": "false"])
            )
            listener.stateUpdateHandler = { [weak self] newState in
                Task { @MainActor in
                    self?.handleListenerState(newState)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.record("收到新的连接请求")
                    self?.accept(connection: connection)
                }
            }
            listener.start(queue: .main)

            self.listener = listener
            self.state = .listening
            self.lastError = nil
            record("Bonjour 已发布，等待 iPhone 连接")
        } catch {
            self.state = .failed
            self.lastError = error.localizedDescription
            record("启动失败: \(error.localizedDescription)")
        }
    }

    func stop() {
        pingTasks.values.forEach { $0.cancel() }
        pingTasks.removeAll()
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        connectionToDeviceID.removeAll()
        sessions.removeAll()
        activeDeviceID = nil
        connectedDevices = []
        isStreaming = false
        lastError = nil
        listener?.cancel()
        listener = nil
        if state != .failed {
            state = .stopped
        }
        record("远程接收器已停止")
    }

    private func handleListenerState(_ newState: NWListener.State) {
        switch newState {
        case .ready:
            updateState()
            lastError = nil
            record("监听器已就绪")
        case .failed(let error):
            state = .failed
            lastError = error.localizedDescription
            record("监听器失败: \(error.localizedDescription)")
        case .cancelled:
            if state != .failed {
                state = .stopped
            }
            record("监听器已取消")
        default:
            break
        }
    }

    private func accept(connection: NWConnection) {
        let serverConnection = ServerConnection(connection)
        connections[serverConnection.id] = serverConnection
        updateState()
        serverConnection.onStateChange = { [weak self] newState in
            Task { @MainActor in
                self?.handleConnectionState(newState, for: serverConnection)
            }
        }
        serverConnection.onError = { [weak self] message in
            Task { @MainActor in
                self?.lastError = message
                self?.record(message)
            }
        }
        serverConnection.onPacket = { [weak self] packet in
            Task { @MainActor in
                self?.handlePacket(packet, via: serverConnection)
            }
        }
        serverConnection.start()
    }

    private func handleConnectionState(_ newState: NWConnection.State, for connection: ServerConnection) {
        switch newState {
        case .ready:
            lastError = nil
            updateState()
            record("TCP 连接已建立，等待握手")
        case .failed(let error):
            lastError = error.localizedDescription
            record("连接失败: \(error.localizedDescription)")
            removeConnection(connection, shouldCancel: false)
        case .cancelled:
            record("连接已关闭")
            removeConnection(connection, shouldCancel: false)
        default:
            break
        }
    }

    private func handlePacket(_ packet: ServerConnection.Packet, via connection: ServerConnection) {
        do {
            switch packet.code {
            case .clientHello:
                record("收到 clientHello")
                let hello = try JSONDecoder().decode(ClientHello.self, from: packet.body)
                lastError = nil
                registerSession(for: connection, hello: hello)
                connection.send(code: .serverHello, entity: ServerHello(version: "4.0.0"))
                record("已发送 serverHello")
                applyStreamingState()
                store?.storeMessage(label: "remote", level: .info, message: "Connected: \(hello.deviceInfo.name) · \(hello.appInfo.name ?? "Unknown App")")
                schedulePing(for: connection.id)
            case .ping:
                record("收到客户端 ping")
                break
            case .storeEventMessageStored:
                guard isConnectionActive(connection) else { break }
                record("收到日志事件")
                let event = try JSONDecoder().decode(LoggerStore.Event.MessageCreated.self, from: packet.body)
                store?.storeMessage(
                    createdAt: event.createdAt,
                    label: event.label,
                    level: event.level,
                    message: event.message,
                    metadata: event.metadata?.reduce(into: [String: LoggerStore.MetadataValue]()) { result, item in
                        result[item.key] = .string(item.value)
                    },
                    file: event.file,
                    function: event.function,
                    line: event.line
                )
            case .storeEventNetworkTaskCompleted:
                guard isConnectionActive(connection) else { break }
                record("收到网络请求完成事件")
                let event = try PacketNetworkMessage.decode(packet.body)
                storeCompletedTask(event)
            case .message:
                record("收到自定义 message 包，当前未处理")
            case .storeEventNetworkTaskCreated, .storeEventNetworkTaskProgressUpdated, .serverHello, .pause, .resume:
                break
            }
        } catch {
            lastError = error.localizedDescription
            record("处理数据包失败: \(error.localizedDescription)")
        }
    }

    private func schedulePing(for connectionID: UUID) {
        pingTasks[connectionID]?.cancel()
        guard let connection = connections[connectionID] else { return }

        let task = DispatchWorkItem { [weak self, weak connection] in
            guard let self, let connection else { return }
            connection.send(code: .ping)
            self.record("已发送 ping")
            self.schedulePing(for: connectionID)
        }
        pingTasks[connectionID] = task
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2), execute: task)
    }

    func resumeStreaming() {
        isStreaming = true
        applyStreamingState()
        record("已恢复当前设备日志接收")
    }

    func pauseStreaming() {
        isStreaming = false
        applyStreamingState()
        record("已暂停所有设备日志接收")
    }

    func selectDevice(_ deviceID: UUID) {
        guard sessions[deviceID] != nil else { return }
        guard activeDeviceID != deviceID else { return }
        activeDeviceID = deviceID
        applyStreamingState()
        updateConnectedDevices()
        if let session = sessions[deviceID] {
            record("已切换当前设备到 \(session.deviceName)")
        }
    }

    func setAlias(_ alias: String?, forGroupKey groupKey: String) {
        let key = aliasStorageKey(forGroupKey: groupKey)
        let trimmed = alias?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(trimmed, forKey: key)
        }
        updateConnectedDevices()
    }

    private func registerSession(for connection: ServerConnection, hello: ClientHello) {
        if let existing = sessions[hello.deviceId], existing.connectionID != connection.id {
            connections[existing.connectionID]?.cancel()
            removeConnection(id: existing.connectionID, shouldCancel: false)
        }

        connectionToDeviceID[connection.id] = hello.deviceId
        sessions[hello.deviceId] = RemoteSession(
            deviceID: hello.deviceId,
            connectionID: connection.id,
            deviceName: hello.deviceInfo.name,
            appName: hello.appInfo.name,
            modelName: firstNonEmptyString([
                hello.deviceInfo.localizedModel,
                hello.deviceInfo.model
            ]),
            systemVersionText: "\(hello.deviceInfo.systemName) \(hello.deviceInfo.systemVersion)"
        )

        if activeDeviceID == nil {
            activeDeviceID = hello.deviceId
        }

        isStreaming = true

        updateConnectedDevices()
        updateState()
    }

    private func applyStreamingState() {
        for (deviceID, session) in sessions {
            guard let connection = connections[session.connectionID] else { continue }
            if isStreaming && activeDeviceID == deviceID {
                connection.send(code: .resume)
            } else {
                connection.send(code: .pause)
            }
        }
        updateConnectedDevices()
        updateState()
    }

    private func isConnectionActive(_ connection: ServerConnection) -> Bool {
        guard let deviceID = connectionToDeviceID[connection.id] else { return false }
        return activeDeviceID == deviceID && isStreaming
    }

    private func removeConnection(_ connection: ServerConnection, shouldCancel: Bool) {
        removeConnection(id: connection.id, shouldCancel: shouldCancel)
    }

    private func removeConnection(id connectionID: UUID, shouldCancel: Bool) {
        pingTasks[connectionID]?.cancel()
        pingTasks.removeValue(forKey: connectionID)

        if shouldCancel {
            connections[connectionID]?.cancel()
        }
        connections.removeValue(forKey: connectionID)

        let removedDeviceID = connectionToDeviceID.removeValue(forKey: connectionID)
        if let removedDeviceID {
            sessions.removeValue(forKey: removedDeviceID)
            if activeDeviceID == removedDeviceID {
                activeDeviceID = sessions.keys.sorted { lhs, rhs in
                    (sessions[lhs]?.deviceName ?? "") < (sessions[rhs]?.deviceName ?? "")
                }.first
            }
        }

        updateConnectedDevices()
        updateState()
        if sessions.isEmpty {
            isStreaming = false
        } else {
            applyStreamingState()
        }
    }

    private func updateConnectedDevices() {
        let grouped = Dictionary(grouping: sessions.values, by: physicalGroupKey(for:))
        connectedDevices = grouped
            .map { groupKey, sessions in
                let sortedSessions = sessions.sorted {
                    ($0.appName ?? "") < ($1.appName ?? "")
                }
                let representative = sortedSessions.first(where: { $0.deviceID == activeDeviceID }) ?? sortedSessions[0]
                let isActive = sessions.contains(where: { $0.deviceID == activeDeviceID })

                return ConnectedDevice(
                    id: groupKey,
                    name: preferredDisplayName(for: representative, groupKey: groupKey),
                    representativeDeviceID: representative.deviceID,
                    appNames: Array(Set(sortedSessions.compactMap(\.appName))).sorted(),
                    modelName: representative.modelName,
                    systemVersionText: representative.systemVersionText,
                    isActive: isActive,
                    isStreaming: isStreaming && isActive
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func updateState() {
        if listener == nil {
            if state != .failed {
                state = .stopped
            }
            return
        }
        if !sessions.isEmpty {
            state = .connected
            lastError = nil
        } else if !connections.isEmpty {
            state = .connecting
        } else {
            state = .listening
            lastError = nil
        }
    }

    private func preferredDisplayName(for session: RemoteSession, groupKey: String) -> String {
        if let alias = storedAlias(forGroupKey: groupKey) {
            return alias
        }

        let rawName = session.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let genericNames = ["iphone", "ipad", "ipod touch", "apple tv", "watch", "iwatch"]
        let normalized = rawName.lowercased()

        if !rawName.isEmpty, !genericNames.contains(normalized) {
            return rawName
        }

        let base = [session.modelName, rawName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && !genericNames.contains($0.lowercased()) })
            ?? (rawName.isEmpty ? "设备" : rawName)
        return base
    }

    private func storedAlias(forGroupKey groupKey: String) -> String? {
        let alias = UserDefaults.standard.string(forKey: aliasStorageKey(forGroupKey: groupKey))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return alias?.isEmpty == false ? alias : nil
    }

    private func aliasStorageKey(forGroupKey groupKey: String) -> String {
        "remoteDeviceAlias.\(groupKey)"
    }

    private func physicalGroupKey(for session: RemoteSession) -> String {
        let name = session.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let system = session.systemVersionText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let genericNames = ["iphone", "ipad", "ipod touch", "apple tv", "watch", "iwatch"]

        if !name.isEmpty, !genericNames.contains(name) {
            return "name:\(name)|system:\(system)"
        }

        return "family:\(deviceFamilyKey(for: session))|system:\(system)"
    }

    private func deviceFamilyKey(for session: RemoteSession) -> String {
        let candidates = [session.modelName, session.deviceName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        for value in candidates {
            if value.contains("iphone") { return "iphone" }
            if value.contains("ipad") { return "ipad" }
            if value.contains("watch") { return "watch" }
            if value.contains("apple tv") || value.contains("appletv") { return "appletv" }
            if !value.isEmpty {
                return value
            }
        }

        return "unknown"
    }

    private func firstNonEmptyString(_ values: [String?]) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private func storeCompletedTask(_ event: LoggerStore.Event.NetworkTaskCompleted) {
        guard let requestURL = event.originalRequest.url else { return }

        var request = URLRequest(url: requestURL)
        request.httpMethod = event.currentRequest?.httpMethod ?? event.originalRequest.httpMethod
        request.allHTTPHeaderFields = event.originalRequest.headers
        request.cachePolicy = event.originalRequest.cachePolicy
        request.timeoutInterval = event.originalRequest.timeout
        request.httpBody = event.requestBody
        request.allowsCellularAccess = event.originalRequest.options.contains(.allowsCellularAccess)
        request.allowsExpensiveNetworkAccess = event.originalRequest.options.contains(.allowsExpensiveNetworkAccess)
        request.allowsConstrainedNetworkAccess = event.originalRequest.options.contains(.allowsConstrainedNetworkAccess)
        request.httpShouldHandleCookies = event.originalRequest.options.contains(.httpShouldHandleCookies)
        request.httpShouldUsePipelining = event.originalRequest.options.contains(.httpShouldUsePipelining)

        let response = event.response.flatMap { response -> HTTPURLResponse? in
            guard let url = event.currentRequest?.url ?? event.originalRequest.url else { return nil }
            return HTTPURLResponse(
                url: url,
                statusCode: response.statusCode ?? 200,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers
            )
        }

        let error = event.error.map { NSError(domain: $0.domain, code: $0.code) }

        store?.storeRequest(
            request,
            response: response,
            error: error,
            data: event.responseBody,
            label: event.label,
            taskDescription: event.taskDescription
        )

        patchStoredTaskMetrics(event)
    }

    private func patchStoredTaskMetrics(_ event: LoggerStore.Event.NetworkTaskCompleted) {
        guard let store else { return }

        store.backgroundContext.performAndWait {
            let request = NSFetchRequest<NetworkTaskEntity>(entityName: "NetworkTaskEntity")
            request.fetchLimit = 1
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

            var predicates: [NSPredicate] = []
            if let url = event.originalRequest.url?.absoluteString {
                predicates.append(NSPredicate(format: "url == %@", url))
            }
            predicates.append(NSPredicate(format: "statusCode == %d", event.response?.statusCode ?? 0))
            if let taskDescription = event.taskDescription {
                predicates.append(NSPredicate(format: "taskDescription == %@", taskDescription))
            }
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

            guard let entity = try? store.backgroundContext.fetch(request).first else {
                return
            }

            entity.url = event.originalRequest.url?.absoluteString
            entity.host = event.originalRequest.url?.host
            entity.httpMethod = event.currentRequest?.httpMethod ?? event.originalRequest.httpMethod
            entity.responseContentType = event.response?.contentType?.type

            if let metrics = event.metrics {
                entity.startDate = metrics.taskInterval.start
                entity.duration = metrics.taskInterval.duration
                entity.redirectCount = Int16(min(Int(Int16.max), metrics.redirectCount))

                let existing = entity.transactions
                existing.forEach { store.backgroundContext.delete($0) }
                entity.transactions = Set(metrics.transactions.enumerated().map { index, transaction in
                    makeTransactionEntity(index: index, transaction: transaction, context: store.backgroundContext)
                })

                let transactions = metrics.transactions
                entity.isFromCache = transactions.last?.fetchType == .localCache || (transactions.last?.fetchType == .networkLoad && transactions.last?.response?.statusCode == 304)

                switch event.taskType {
                case .dataTask:
                    entity.requestBodySize = Int64(event.requestBody?.count ?? 0)
                    entity.responseBodySize = Int64(event.responseBody?.count ?? 0)
                case .downloadTask:
                    entity.responseBodySize = transactions.last(where: { $0.fetchType == .networkLoad })?.transferSize.responseBodyBytesReceived ?? entity.responseBodySize
                case .uploadTask:
                    entity.requestBodySize = transactions.last(where: { $0.fetchType == .networkLoad })?.transferSize.requestBodyBytesSent ?? entity.requestBodySize
                default:
                    break
                }
            }

            if let original = entity.originalRequest {
                store.backgroundContext.delete(original)
            }
            entity.originalRequest = makeRequestEntity(event.originalRequest, context: store.backgroundContext)

            if let current = entity.currentRequest {
                store.backgroundContext.delete(current)
            }
            entity.currentRequest = event.currentRequest.map { makeRequestEntity($0, context: store.backgroundContext) }

            if let response = entity.response {
                store.backgroundContext.delete(response)
            }
            entity.response = event.response.map { makeResponseEntity($0, context: store.backgroundContext) }

            try? store.backgroundContext.save()
        }
    }

    private func record(_ message: String) {
        let formatter = Self.eventDateFormatter
        recentEvents.insert("\(formatter.string(from: Date())) \(message)", at: 0)
        if recentEvents.count > 12 {
            recentEvents.removeLast(recentEvents.count - 12)
        }
    }

    private static let eventDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private func makeRequestEntity(_ request: NetworkLogger.Request, context: NSManagedObjectContext) -> NetworkRequestEntity {
    let entity = NetworkRequestEntity(context: context)
    entity.url = request.url?.absoluteString
    entity.httpMethod = request.httpMethod
    entity.httpHeaders = encodeHeaders(request.headers)
    entity.allowsCellularAccess = request.options.contains(.allowsCellularAccess)
    entity.allowsExpensiveNetworkAccess = request.options.contains(.allowsExpensiveNetworkAccess)
    entity.allowsConstrainedNetworkAccess = request.options.contains(.allowsConstrainedNetworkAccess)
    entity.httpShouldHandleCookies = request.options.contains(.httpShouldHandleCookies)
    entity.httpShouldUsePipelining = request.options.contains(.httpShouldUsePipelining)
    entity.timeoutInterval = NSNumber(value: request.timeout).int32Value
    entity.rawCachePolicy = UInt16(request.cachePolicy.rawValue)
    return entity
}

private func makeResponseEntity(_ response: NetworkLogger.Response, context: NSManagedObjectContext) -> NetworkResponseEntity {
    let entity = NetworkResponseEntity(context: context)
    entity.statusCode = Int16(response.statusCode ?? 0)
    entity.httpHeaders = encodeHeaders(response.headers)
    return entity
}

private func makeTransactionEntity(index: Int, transaction: NetworkLogger.TransactionMetrics, context: NSManagedObjectContext) -> NetworkTransactionMetricsEntity {
    let entity = NetworkTransactionMetricsEntity(context: context)
    entity.index = Int16(index)
    entity.rawFetchType = Int16(transaction.fetchType.rawValue)
    entity.request = makeRequestEntity(transaction.request, context: context)
    entity.response = transaction.response.map { makeResponseEntity($0, context: context) }
    entity.networkProtocol = transaction.networkProtocol
    entity.localAddress = transaction.localAddress
    entity.remoteAddress = transaction.remoteAddress
    entity.localPort = Int32(transaction.localPort ?? 0)
    entity.remotePort = Int32(transaction.remotePort ?? 0)
    entity.isProxyConnection = transaction.conditions.contains(.isProxyConnection)
    entity.isReusedConnection = transaction.conditions.contains(.isReusedConnection)
    entity.isCellular = transaction.conditions.contains(.isCellular)
    entity.isExpensive = transaction.conditions.contains(.isExpensive)
    entity.isConstrained = transaction.conditions.contains(.isConstrained)
    entity.isMultipath = transaction.conditions.contains(.isMultipath)
    entity.rawNegotiatedTLSProtocolVersion = Int32(transaction.negotiatedTLSProtocolVersion?.rawValue ?? 0)
    entity.rawNegotiatedTLSCipherSuite = Int32(transaction.negotiatedTLSCipherSuite?.rawValue ?? 0)
    entity.fetchStartDate = transaction.timing.fetchStartDate
    entity.domainLookupStartDate = transaction.timing.domainLookupStartDate
    entity.domainLookupEndDate = transaction.timing.domainLookupEndDate
    entity.connectStartDate = transaction.timing.connectStartDate
    entity.secureConnectionStartDate = transaction.timing.secureConnectionStartDate
    entity.secureConnectionEndDate = transaction.timing.secureConnectionEndDate
    entity.connectEndDate = transaction.timing.connectEndDate
    entity.requestStartDate = transaction.timing.requestStartDate
    entity.requestEndDate = transaction.timing.requestEndDate
    entity.responseStartDate = transaction.timing.responseStartDate
    entity.responseEndDate = transaction.timing.responseEndDate
    entity.requestHeaderBytesSent = transaction.transferSize.requestHeaderBytesSent
    entity.requestBodyBytesBeforeEncoding = transaction.transferSize.requestBodyBytesBeforeEncoding
    entity.requestBodyBytesSent = transaction.transferSize.requestBodyBytesSent
    entity.responseHeaderBytesReceived = transaction.transferSize.responseHeaderBytesReceived
    entity.responseBodyBytesAfterDecoding = transaction.transferSize.responseBodyBytesAfterDecoding
    entity.responseBodyBytesReceived = transaction.transferSize.responseBodyBytesReceived
    return entity
}

private func encodeHeaders(_ headers: [String: String]?) -> String {
    (headers ?? [:])
        .sorted { $0.key < $1.key }
        .map { "\($0.key): \($0.value)" }
        .joined(separator: "\n")
}

private struct RemoteSession {
    let deviceID: UUID
    let connectionID: UUID
    let deviceName: String
    let appName: String?
    let modelName: String?
    let systemVersionText: String
}

private final class ServerConnection {
    struct Packet {
        let code: PacketCode
        let body: Data
    }

    enum PacketCode: UInt8 {
        case clientHello = 0
        case serverHello = 1
        case pause = 2
        case resume = 3
        case ping = 6
        case storeEventMessageStored = 7
        case storeEventNetworkTaskCreated = 8
        case storeEventNetworkTaskProgressUpdated = 9
        case storeEventNetworkTaskCompleted = 10
        case message = 13
    }

    var onStateChange: ((NWConnection.State) -> Void)?
    var onPacket: ((Packet) -> Void)?
    var onError: ((String) -> Void)?

    let id = UUID()

    private let connection: NWConnection
    private var buffer = Data()
    private let queue = DispatchQueue(label: "PulsePro.RemoteServer.Connection")
    private let emptyControlPacket = EmptyPacket()

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            self?.onStateChange?(state)
        }
        receive()
        connection.start(queue: queue)
    }

    func cancel() {
        connection.cancel()
    }

    func send<T: Encodable>(code: PacketCode, entity: T) {
        guard let data = try? JSONEncoder().encode(entity) else { return }
        send(code: code, body: data)
    }

    func send(code: PacketCode) {
        send(code: code, entity: emptyControlPacket)
    }

    private func send(code: PacketCode, body: Data) {
        guard let encoded = try? Self.encode(code: code.rawValue, body: body) else { return }
        connection.send(content: encoded, completion: .contentProcessed { _ in })
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65535) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.process(data)
            }
            if isComplete {
                self.onError?("对端已关闭连接")
                self.connection.cancel()
                return
            }
            if let error {
                self.onError?("接收数据失败: \(error.localizedDescription)")
                self.connection.cancel()
                return
            }
            self.receive()
        }
    }

    private func process(_ incoming: Data) {
        buffer.append(incoming)
        while !buffer.isEmpty {
            do {
                let (packet, size) = try Self.decode(from: buffer)
                onPacket?(packet)
                buffer.removeFirst(size)
            } catch DecodeError.notEnoughData {
                return
            } catch {
                onError?("解析数据包失败: \(error.localizedDescription)")
                connection.cancel()
                return
            }
        }
    }

    private static func encode(code: UInt8, body: Data) throws -> Data {
        let compressed = try (body as NSData).compressed(using: .lzfse) as Data
        var data = Data()
        data.append(code)
        var size = UInt32(compressed.count).bigEndian
        data.append(Data(bytes: &size, count: MemoryLayout<UInt32>.size))
        data.append(compressed)
        return data
    }

    private static func decode(from data: Data) throws -> (Packet, Int) {
        guard data.count >= 5 else {
            throw DecodeError.notEnoughData
        }
        let code = data[data.startIndex]
        guard let compressedSize = readUInt32BE(from: data, offset: 1).map(Int.init) else {
            throw DecodeError.notEnoughData
        }
        guard data.count >= 5 + compressedSize else {
            throw DecodeError.notEnoughData
        }
        let compressedBody = safeSubdata(from: data, offset: 5, count: compressedSize)
        let body = try (compressedBody as NSData).decompressed(using: .lzfse) as Data
        guard let packetCode = PacketCode(rawValue: code) else {
            throw DecodeError.unsupportedCode
        }
        return (Packet(code: packetCode, body: body), 5 + compressedSize)
    }

    enum DecodeError: Error {
        case notEnoughData
        case unsupportedCode
    }
}

private struct EmptyPacket: Codable {}

private struct ClientHello: Codable {
    let version: String?
    let deviceId: UUID
    let deviceInfo: LoggerStore.Info.DeviceInfo
    let appInfo: LoggerStore.Info.AppInfo
    let session: LoggerStore.Session?
}

private struct ServerHello: Codable {
    let version: String
}

private enum PacketNetworkMessage {
    static func decode(_ data: Data) throws -> LoggerStore.Event.NetworkTaskCompleted {
        guard data.count >= 12 else {
            throw URLError(.cannotDecodeRawData)
        }

        guard
            let messageSize = readUInt32BE(from: data, offset: 0).map(Int.init),
            let requestBodySize = readUInt32BE(from: data, offset: 4).map(Int.init),
            let responseBodySize = readUInt32BE(from: data, offset: 8).map(Int.init)
        else {
            throw URLError(.cannotDecodeRawData)
        }
        let total = 12 + messageSize + requestBodySize + responseBodySize
        guard data.count >= total else {
            throw URLError(.cannotDecodeRawData)
        }

        let eventData = safeSubdata(from: data, offset: 12, count: messageSize)
        var event = try JSONDecoder().decode(LoggerStore.Event.NetworkTaskCompleted.self, from: eventData)

        if requestBodySize > 0 {
            event.requestBody = safeSubdata(from: data, offset: 12 + messageSize, count: requestBodySize)
        }
        if responseBodySize > 0 {
            let start = 12 + messageSize + requestBodySize
            event.responseBody = safeSubdata(from: data, offset: start, count: responseBodySize)
        }
        return event
    }
}

private func readUInt32BE(from data: Data, offset: Int) -> UInt32? {
    guard offset >= 0 else {
        return nil
    }

    guard let range = safeRange(in: data, offset: offset, count: 4) else {
        return nil
    }

    return data[range].reduce(UInt32(0)) { partial, byte in
        (partial << 8) | UInt32(byte)
    }
}

private func safeSubdata(from data: Data, offset: Int, count: Int) -> Data {
    guard let range = safeRange(in: data, offset: offset, count: count) else {
        return Data()
    }
    return Data(data[range])
}

private func safeRange(in data: Data, offset: Int, count: Int) -> Range<Data.Index>? {
    guard offset >= 0, count >= 0 else { return nil }
    guard let start = data.index(data.startIndex, offsetBy: offset, limitedBy: data.endIndex) else {
        return nil
    }
    guard let end = data.index(start, offsetBy: count, limitedBy: data.endIndex) else {
        return nil
    }
    return start..<end
}
