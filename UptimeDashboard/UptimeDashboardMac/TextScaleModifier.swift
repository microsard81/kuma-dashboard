import SwiftUI

// MARK: - Environment key per la scala del testo

private struct TextScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    var textScale: Double {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

// MARK: - Font extension per scala

extension Font {
    /// Restituisce un font scalato in base al fattore.
    static func scaled(_ style: Font.TextStyle, scale: Double) -> Font {
        let baseSize: CGFloat
        switch style {
        case .largeTitle: baseSize = 26
        case .title: baseSize = 22
        case .title2: baseSize = 20
        case .title3: baseSize = 18
        case .headline: baseSize = 15
        case .body: baseSize = 13
        case .callout: baseSize = 12
        case .subheadline: baseSize = 11
        case .footnote: baseSize = 10
        case .caption: baseSize = 10
        case .caption2: baseSize = 9
        default: baseSize = 13
        }
        return .system(size: baseSize * CGFloat(scale))
    }

    static func scaled(_ style: Font.TextStyle, scale: Double, weight: Font.Weight) -> Font {
        let baseSize: CGFloat
        switch style {
        case .largeTitle: baseSize = 26
        case .title: baseSize = 22
        case .title2: baseSize = 20
        case .title3: baseSize = 18
        case .headline: baseSize = 15
        case .body: baseSize = 13
        case .callout: baseSize = 12
        case .subheadline: baseSize = 11
        case .footnote: baseSize = 10
        case .caption: baseSize = 10
        case .caption2: baseSize = 9
        default: baseSize = 13
        }
        return .system(size: baseSize * CGFloat(scale), weight: weight)
    }
}
