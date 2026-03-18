// The MIT License (MIT)
//
// Copyright (c) 2024 Pulse Pro

import SwiftUI
import Pulse
import CoreData

struct SessionsView: View {
    let store: LoggerStore
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("会话管理")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            if sessions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("暂无会话")
                        .font(.headline)
                    Text("当前日志包中还没有记录到 Pulse 会话。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section("会话列表") {
                        ForEach(sessions, id: \.objectID) { session in
                            SessionRowView(
                                session: session,
                                isActive: session.id == store.session.id,
                                messageCount: messageCount(for: session.id),
                                taskCount: taskCount(for: session.id)
                            )
                        }
                    }
                }
            }
        }
    }

    private var sessions: [LoggerSessionEntity] {
        let request = LoggerSessionEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \LoggerSessionEntity.createdAt, ascending: false)]
        return ((try? store.viewContext.fetch(request)) as? [LoggerSessionEntity]) ?? []
    }

    private func messageCount(for id: UUID) -> Int {
        let request = LoggerMessageEntity.fetchRequest()
        request.predicate = NSPredicate(format: "session == %@", id as NSUUID)
        return (try? store.viewContext.count(for: request)) ?? 0
    }

    private func taskCount(for id: UUID) -> Int {
        let request = NetworkTaskEntity.fetchRequest()
        request.predicate = NSPredicate(format: "session == %@", id as NSUUID)
        return (try? store.viewContext.count(for: request)) ?? 0
    }
}

struct SessionRowView: View {
    let session: LoggerSessionEntity
    let isActive: Bool
    let messageCount: Int
    let taskCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isActive ? "当前会话" : "历史会话")
                    .font(.headline)
                Spacer()
                if isActive {
                    Text("当前")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(session.id.uuidString)
                    .font(.system(.caption, design: .monospaced))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(formatDate(session.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                Text("日志 \(messageCount)")
                Text("请求 \(taskCount)")
                if let version = session.version, !version.isEmpty {
                    Text("版本 \(version)")
                }
                if let build = session.build, !build.isEmpty {
                    Text("Build \(build)")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "-" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
