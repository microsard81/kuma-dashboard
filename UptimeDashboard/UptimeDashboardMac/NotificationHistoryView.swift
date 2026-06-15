// Feature: native-apps-sensor-integration

import SwiftUI

/// View showing event history fetched from the backend (last 30 days).
/// Unread events appear at the top with blue background.
/// Swipe left to toggle read/unread state (local per-device).
struct NotificationHistoryView: View {
    @StateObject private var eventLog = EventLogService.shared
    @EnvironmentObject var viewModel: MacAppViewModel

    private var unreadEvents: [EventRecord] {
        eventLog.events.filter { !$0.isRead }
    }

    private var readEvents: [EventRecord] {
        eventLog.events.filter { $0.isRead }
    }

    var body: some View {
        Group {
            if eventLog.isLoading && eventLog.events.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Caricamento eventi...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if eventLog.events.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "bell.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Nessun evento")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Gli eventi di stato appariranno qui")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    // Unread first
                    if !unreadEvents.isEmpty {
                        Section {
                            ForEach(unreadEvents) { event in
                                EventRow(event: event)
                                    .listRowBackground(Color.blue.opacity(0.08))
                                    .swipeActions(edge: .trailing) {
                                        Button {
                                            eventLog.markAsRead(id: event.id)
                                        } label: {
                                            Label("Letta", systemImage: "envelope.open")
                                        }
                                        .tint(.blue)
                                    }
                            }
                        } header: {
                            Text("Non lette (\(unreadEvents.count))")
                        }
                    }

                    // Read
                    if !readEvents.isEmpty {
                        Section {
                            ForEach(readEvents) { event in
                                EventRow(event: event)
                                    .swipeActions(edge: .trailing) {
                                        Button {
                                            eventLog.markAsUnread(id: event.id)
                                        } label: {
                                            Label("Non letta", systemImage: "envelope.badge")
                                        }
                                        .tint(.blue)
                                    }
                            }
                        } header: {
                            if !unreadEvents.isEmpty {
                                Text("Lette")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await refreshEvents()
                }
                .overlay(alignment: .top) {
                    if !unreadEvents.isEmpty {
                        Text("↓ Tira per aggiornare")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, -20)
                    }
                }
            }
        }
        .navigationTitle("Eventi")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if !unreadEvents.isEmpty {
                    Button {
                        eventLog.markAllAsRead()
                    } label: {
                        Image(systemName: "envelope.open")
                    }
                    .help("Segna tutte come lette")
                }
            }
        }
        .task { await refreshEvents() }
    }

    private func refreshEvents() async {
        guard let baseURL = viewModel.baseURL else { return }
        await eventLog.fetchEvents(
            baseURL: baseURL,
            watchToken: viewModel.watchToken,
            session: viewModel.urlSession
        )
    }
}

// MARK: - EventRow

private struct EventRow: View {
    let event: EventRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if !event.isRead {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                }
                Text(event.title)
                    .font(.subheadline.bold())
                Spacer()
                Text(formatDate(event.date))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            if !event.body.isEmpty {
                Text(event.body)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "'Ieri' HH:mm"
        } else {
            formatter.dateFormat = "dd/MM HH:mm"
        }
        return formatter.string(from: date)
    }
}
