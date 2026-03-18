import AppKit
import Combine
import Foundation
import Pulse

@MainActor
final class PulseProStoreController: ObservableObject {
    let remoteServer = PulseProRemoteServer()
    @Published private(set) var store: LoggerStore
    @Published private(set) var storeURL: URL
    @Published private(set) var storeInfo: LoggerStore.Info?
    @Published private(set) var isReadOnlyStore: Bool
    @Published var refreshID = UUID()
    @Published var isRemoteServerEnabled = true
    @Published var errorMessage: String?
    @Published var isRefreshingInfo = false

    private let defaultStoreURL: URL
    private var scopedURL: URL?
    private var cancellables = Set<AnyCancellable>()

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = appSupport
            .appendingPathComponent("PulsePro", isDirectory: true)
            .appendingPathComponent("Stores", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let defaultStoreURL = directory.appendingPathComponent("current.pulse", isDirectory: true)
        self.defaultStoreURL = defaultStoreURL

        if let writableStore = try? LoggerStore(storeURL: defaultStoreURL, options: [.create, .sweep]) {
            self.store = writableStore
            self.storeURL = defaultStoreURL
            self.isReadOnlyStore = false
        } else {
            self.store = LoggerStore.shared
            self.storeURL = LoggerStore.shared.storeURL
            self.isReadOnlyStore = false
            self.errorMessage = "Pulse Pro 默认 store 创建失败，已回退到 Pulse.shared。"
        }

        Task {
            await refreshInfo()
        }

        remoteServer.objectWillChange
            .sink { [weak self] _ in
                self?.refreshID = UUID()
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        store.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshID = UUID()
                self?.objectWillChange.send()
                Task { [weak self] in
                    await self?.refreshInfo()
                }
            }
            .store(in: &cancellables)

        startRemoteServerIfNeeded()
    }

    var storeLocationDescription: String {
        storeURL.path
    }

    var sourceDescription: String {
        isReadOnlyStore ? "外部只读日志包" : "Pulse Pro 本地工作区"
    }

    var canHostRemoteConnections: Bool {
        !isReadOnlyStore
    }

    func refreshInfo() async {
        isRefreshingInfo = true
        defer { isRefreshingInfo = false }

        do {
            storeInfo = try await store.info()
        } catch {
            errorMessage = "读取日志信息失败：\(error.localizedDescription)"
        }
    }

    func openStorePanel() {
        let panel = NSOpenPanel()
        panel.title = "打开 Pulse 日志包"
        panel.message = "请选择 Pulse 生成的 .pulse 日志包目录"
        panel.prompt = "打开"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await openStore(at: url)
            }
        }
    }

    func exportCurrentStore() {
        let panel = NSSavePanel()
        panel.title = "导出 Pulse 日志包"
        panel.message = "导出为 .pulse 日志包目录"
        panel.prompt = "导出"
        panel.nameFieldStringValue = "PulsePro-\(Self.exportDateFormatter.string(from: Date())).pulse"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, var url = panel.url else {
            return
        }
        if url.pathExtension.lowercased() != "pulse" {
            url.appendPathExtension("pulse")
        }

        Task {
            do {
                try await store.export(to: url)
            } catch {
                errorMessage = "导出失败：\(error.localizedDescription)"
            }
        }
    }

    func resetToDefaultStore() {
        Task {
            await openDefaultStore()
        }
    }

    func clearWritableStore() {
        guard !isReadOnlyStore else {
            errorMessage = "当前打开的是外部只读日志包，不能直接清空。"
            return
        }
        store.removeAll()
        Task {
            await refreshInfo()
        }
    }

    func startRemoteServerIfNeeded() {
        guard isRemoteServerEnabled else { return }
        guard !isReadOnlyStore else { return }
        remoteServer.start(with: store)
    }

    func startRemoteServer() {
        isRemoteServerEnabled = true
        guard !isReadOnlyStore else {
            errorMessage = "当前打开的是外部只读日志包，请先回到默认工作区再开启远程接收。"
            return
        }
        remoteServer.start(with: store)
    }

    func stopRemoteServer() {
        isRemoteServerEnabled = false
        remoteServer.stop()
    }

    func restartRemoteServer() {
        remoteServer.stop()
        startRemoteServer()
    }

    func startReceivingRemoteEvents() {
        remoteServer.resumeStreaming()
    }

    func pauseReceivingRemoteEvents() {
        remoteServer.pauseStreaming()
    }

    private func openDefaultStore() async {
        releaseScopedURL()
        do {
            let nextStore = try LoggerStore(storeURL: defaultStoreURL, options: [.create, .sweep])
            apply(store: nextStore, url: defaultStoreURL, isReadOnly: false)
            await refreshInfo()
        } catch {
            errorMessage = "打开默认 store 失败：\(error.localizedDescription)"
        }
    }

    private func openStore(at url: URL) async {
        releaseScopedURL()

        let didAccess = url.startAccessingSecurityScopedResource()
        if didAccess {
            scopedURL = url
        }

        do {
            let nextStore = try LoggerStore(storeURL: url, options: [.readonly])
            apply(store: nextStore, url: url, isReadOnly: true)
            await refreshInfo()
        } catch {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
                scopedURL = nil
            }
            errorMessage = "打开日志包失败：\(error.localizedDescription)"
        }
    }

    private func apply(store: LoggerStore, url: URL, isReadOnly: Bool) {
        cancellables.removeAll()
        self.store = store
        self.storeURL = url
        self.isReadOnlyStore = isReadOnly
        bindStoreObservers()
        if isReadOnly {
            remoteServer.stop()
        } else if isRemoteServerEnabled {
            remoteServer.start(with: store)
        }
    }

    private func bindStoreObservers() {
        remoteServer.objectWillChange
            .sink { [weak self] _ in
                self?.refreshID = UUID()
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        store.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshID = UUID()
                self?.objectWillChange.send()
                Task { [weak self] in
                    await self?.refreshInfo()
                }
            }
            .store(in: &cancellables)
    }

    private func releaseScopedURL() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()
}
