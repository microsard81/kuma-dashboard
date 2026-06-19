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

            // UPS
            if !upsSensors.isEmpty {
                NavigationLink {
                    WatchCategoryDetailView(category: .ups)
                        .environmentObject(viewModel)
                } label: {
                    HStack {
                        Circle()
                            .fill(upsColor)
                            .frame(width: 8, height: 8)
                        Image(systemName: "battery.75percent")
                            .font(.caption2)
                            .foregroundColor(upsColor)
                        Text("UPS")
                            .font(.caption)
                        Spacer()
                        Text(upsStatus)
                            .font(.caption2)
                            .foregroundColor(upsColor)
                    }
                }
            }

            // Generatori
            if !generatorSensors.isEmpty {
                NavigationLink {
                    WatchCategoryDetailView(category: .generator)
                        .environmentObject(viewModel)
                } label: {
                    HStack {
                        Circle()
                            .fill(generatorColor)
                            .frame(width: 8, height: 8)
                        Image(systemName: "fuelpump.fill")
                            .font(.caption2)
                            .foregroundColor(generatorColor)
                        Text("Generatori")
                            .font(.caption)
                        Spacer()
                        Text(generatorStatus)
                            .font(.caption2)
                            .foregroundColor(generatorColor)
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

    private var upsSensors: [SensorReading] {
        viewModel.sensors.filter { $0.category == .ups }
    }

    private var generatorSensors: [SensorReading] {
        viewModel.sensors.filter { $0.category == .generator }
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
        if temperatureSensors.contains(where: { $0.status == .critical }) { return .red }
        return .orange
    }

    private var temperatureStatus: String {
        let alerts = temperatureSensors.filter { $0.status == .critical }.count
        if alerts > 0 { return "\(alerts) ⚠" }
        return "OK"
    }

    private var powerColor: Color {
        if powerSensors.contains(where: { $0.status == .critical }) { return .red }
        return .blue
    }

    private var powerStatus: String {
        let alerts = powerSensors.filter { $0.status == .critical }.count
        if alerts > 0 { return "\(alerts) ⚠" }
        return "OK"
    }

    private var upsColor: Color {
        if upsSensors.contains(where: { $0.status == .critical }) { return .red }
        return .purple
    }

    private var upsStatus: String {
        let alerts = upsSensors.filter { $0.status == .critical }.count
        if alerts > 0 { return "\(alerts) ⚠" }
        return "OK"
    }

    private var generatorColor: Color {
        if generatorSensors.contains(where: { $0.status == .critical }) { return .red }
        return .orange
    }

    private var generatorStatus: String {
        let alerts = generatorSensors.filter { $0.status == .critical }.count
        if alerts > 0 { return "\(alerts) ⚠" }
        return "OK"
    }
}
