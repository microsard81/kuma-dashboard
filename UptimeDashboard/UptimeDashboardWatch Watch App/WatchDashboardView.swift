import SwiftUI

struct WatchDashboardView: View {
    @EnvironmentObject var viewModel: WatchDashboardViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.monitors.isEmpty {
                    VStack(spacing: 12) {
                        if viewModel.isLoading {
                            ProgressView()
                            Text("Caricamento...")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        } else if let error = viewModel.lastError {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.title3)
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Riprova") {
                                Task { await viewModel.fetchFromAPI() }
                            }
                            .font(.caption)
                        } else {
                            ProgressView()
                            Text("In attesa dei dati...")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.fetchFromAPI() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
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

            // Sensor section — hidden if no sensor data and no error
            if !viewModel.sensors.isEmpty || viewModel.sensorError != nil {
                Section {
                    WatchSensorListView(
                        sensors: viewModel.sensors,
                        thresholds: viewModel.sensorThresholds,
                        error: viewModel.sensorError
                    )
                } header: {
                    Label("Sensori", systemImage: "thermometer.medium")
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
