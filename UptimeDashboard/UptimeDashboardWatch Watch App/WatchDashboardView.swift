import SwiftUI

struct WatchDashboardView: View {
    @EnvironmentObject var viewModel: WatchDashboardViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.monitors.isEmpty && viewModel.sensors.isEmpty {
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
                    sectionList
                }
            }
            .navigationTitle("INVA")
            .refreshable {
                await viewModel.fetchFromAPI()
            }
        }
    }

    // MARK: - 3 Sections

    @ViewBuilder
    private var sectionList: some View {
        List {
            // Portali
            NavigationLink {
                WatchPortalsDetailView()
                    .environmentObject(viewModel)
            } label: {
                HStack {
                    Circle()
                        .fill(portalsColor)
                        .frame(width: 8, height: 8)
                    Image(systemName: "globe")
                        .font(.caption2)
                        .foregroundColor(portalsColor)
                    Text("Portali")
                        .font(.caption)
                    Spacer()
                    Text(portalsStatus)
                        .font(.caption2)
                        .foregroundColor(portalsColor)
                }
            }

            // Temperatura
            if !temperatureSensors.isEmpty {
                NavigationLink {
                    WatchTemperatureDetailView()
                        .environmentObject(viewModel)
                } label: {
                    HStack {
                        Circle()
                            .fill(temperatureColor)
                            .frame(width: 8, height: 8)
                        Image(systemName: "thermometer.medium")
                            .font(.caption2)
                            .foregroundColor(temperatureColor)
                        Text("Temperatura")
                            .font(.caption)
                        Spacer()
                        Text(temperatureStatus)
                            .font(.caption2)
                            .foregroundColor(temperatureColor)
                    }
                }
            }

            // Potenza
            if !powerSensors.isEmpty {
                NavigationLink {
                    WatchPowerDetailView()
                        .environmentObject(viewModel)
                } label: {
                    HStack {
                        Circle()
                            .fill(powerColor)
                            .frame(width: 8, height: 8)
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                            .foregroundColor(powerColor)
                        Text("Potenza")
                            .font(.caption)
                        Spacer()
                        Text(powerStatus)
                            .font(.caption2)
                            .foregroundColor(powerColor)
                    }
                }
            }
        }
    }

    // MARK: - Computed

    private var temperatureSensors: [SensorReading] {
        viewModel.sensors.filter { $0.category == .temperature }
    }

    private var powerSensors: [SensorReading] {
        viewModel.sensors.filter { $0.category == .power }
    }

    private var portalsColor: Color {
        switch viewModel.globalState {
        case "RED": return .red
        case "YELLOW": return .yellow
        default: return .green
        }
    }

    private var portalsStatus: String {
        let down = viewModel.monitors.filter { $0.isDown }.count
        let mismatch = viewModel.monitors.filter { $0.isMismatch }.count
        if down > 0 { return "\(down) DOWN" }
        if mismatch > 0 { return "\(mismatch) ⚠" }
        return "OK"
    }

    private var temperatureColor: Color {
        guard let t = viewModel.sensorThresholds else { return .orange }
        if temperatureSensors.contains(where: { $0.alertStatus(thresholds: t) == .critical }) { return .red }
        if temperatureSensors.contains(where: { $0.alertStatus(thresholds: t) == .warning }) { return .yellow }
        return .orange
    }

    private var temperatureStatus: String {
        guard let t = viewModel.sensorThresholds else { return "—" }
        let alerts = temperatureSensors.filter { $0.alertStatus(thresholds: t) != .normal }.count
        if alerts > 0 { return "\(alerts) ⚠" }
        return "OK"
    }

    private var powerColor: Color {
        guard let t = viewModel.sensorThresholds else { return .blue }
        if powerSensors.contains(where: { $0.alertStatus(thresholds: t) == .critical }) { return .red }
        if powerSensors.contains(where: { $0.alertStatus(thresholds: t) == .warning }) { return .yellow }
        return .blue
    }

    private var powerStatus: String {
        guard let t = viewModel.sensorThresholds else { return "—" }
        let alerts = powerSensors.filter { $0.alertStatus(thresholds: t) != .normal }.count
        if alerts > 0 { return "\(alerts) ⚠" }
        return "OK"
    }
}
