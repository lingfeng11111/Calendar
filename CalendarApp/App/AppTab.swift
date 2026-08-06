import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case calendar
    case vacation
    case settings

    var id: String { rawValue }

    @ViewBuilder
    var label: some View {
        switch self {
        case .calendar:
            Label("日历", systemImage: "calendar")
        case .vacation:
            Label("假期", systemImage: "sun.max")
        case .settings:
            Label("设置", systemImage: "gearshape")
        }
    }
}
