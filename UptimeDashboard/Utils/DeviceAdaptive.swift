import SwiftUI

/// Helper per adattare dimensioni e font in base al dispositivo (iPhone vs iPad).
enum DeviceAdaptive {
    static var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    // MARK: - Font sizes

    /// Font per il nome del monitor nella riga
    static var monitorNameFont: Font {
        isIPad ? .title3.bold() : .headline
    }

    /// Font per il badge stato (UP/DOWN)
    static var statusBadgeFont: Font {
        isIPad ? .subheadline.bold() : .caption.bold()
    }

    /// Font per le label delle sonde (Aruba, TIM, etc.)
    static var probeLabelFont: Font {
        isIPad ? .body : .caption
    }

    /// Font per il label di selezione sparkline (orario + stato)
    static var selectionLabelFont: Font {
        isIPad ? .caption.bold() : .caption2.bold()
    }

    /// Font per gli header delle sezioni (DOWN, Mismatch, UP)
    static var sectionHeaderFont: Font {
        isIPad ? .subheadline.bold() : .caption.bold()
    }

    // MARK: - Sizes

    /// Diametro del pallino della sonda
    static var probeDotSize: CGFloat {
        isIPad ? 12 : 8
    }

    /// Altezza della sparkline
    static var sparklineHeight: CGFloat {
        isIPad ? 44 : 28
    }

    /// Padding verticale della riga
    static var rowVerticalPadding: CGFloat {
        isIPad ? 10 : 6
    }

    /// Padding del badge stato
    static var badgeHPadding: CGFloat {
        isIPad ? 12 : 8
    }

    static var badgeVPadding: CGFloat {
        isIPad ? 5 : 3
    }
}
