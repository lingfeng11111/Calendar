import Observation
import SwiftUI

@MainActor
@Observable
final class Theme {
    var tint: Color { Color(uiColor: .systemBlue) }

    var backgroundPrimary: Color { Color(uiColor: .systemBackground) }
    var backgroundSecondary: Color { Color(uiColor: .secondarySystemBackground) }
    var surfaceElevated: Color { Color(uiColor: .secondarySystemBackground) }
    var surfaceTinted: Color { Color(uiColor: .tertiarySystemBackground) }
    var separatorSubtle: Color { Color(uiColor: .separator) }
    var labelPrimary: Color { Color(uiColor: .label) }
    var labelSecondary: Color { Color(uiColor: .secondaryLabel) }
    var statusHoliday: Color { Color(uiColor: .systemRed) }
    var statusMakeupWorkday: Color { Color(uiColor: .systemOrange) }
    var statusVacation: Color { Color(uiColor: .systemTeal) }
    var statusUnknown: Color { Color(uiColor: .systemGray) }
    var annotationSolarTerm: Color { Color(uiColor: .systemIndigo) }
    var annotationFestival: Color { Color(uiColor: .systemPurple) }
}
