import SwiftUI

struct WatchDashboardView: View {
    @EnvironmentObject var viewModel: WatchDashboardViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.monitors.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("In attesa dei dati...")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                } else {
                    monitorList
                }
            }
            .navigationTitle("INVA")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Circle()
                        .fill(ledColor)
                        .frame(width: 10, height: 10)
                }
            }
        }
    }

    @ViewBuilder
    private var monitorList: some View {
        let downItems = viewModel.monitors.filter { $0.isDown }
        let mismatchItems = viewModel.monitors.filter { $0.isMismatch }
        let upItems = viewModel.monitors.filter { !$0.isDown && !$0.isMismatch }
        let allUp = downItems.isEmpty && mismatchItems.isEmpty

        List {
            if !downItems.isEmpty {
                Section {
                    ForEach(downItems) { WatchMonitorCard(monitor: $0) }
                } header: {
                    Label("DOWN", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }

            if !mismatchItems.isEmpty {
                Section {
                    ForEach(mismatchItems) { WatchMonitorCard(monitor: $0) }
                } header: {
                    Label("Mismatch", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                }
            }

            if !upItems.isEmpty {
                if allUp {
                    ForEach(upItems) { WatchMonitorCard(monitor: $0) }
                } else {
                    Section {
                        ForEach(upItems) { WatchMonitorCard(monitor: $0) }
                    } header: {
                        Label("UP", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
            }
        }
    }

    private var ledColor: Color {
        switch viewModel.globalState {
        case "RED": return .red
        case "YELLOW": return .yellow
        default: return .green
        }
    }
}
