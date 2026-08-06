import Observation

@MainActor
@Observable
final class AppRouter {
    var path: [AppRoute] = []
    var presentedSheet: SheetDestination?

    func navigate(to route: AppRoute) {
        path.append(route)
    }

    func reset() {
        path.removeAll()
        presentedSheet = nil
    }
}

enum AppRoute: Hashable {
    case dayDetail(dayID: DayID)
    case settings
}

enum SheetDestination: Hashable, Identifiable {
    case placeholder

    var id: String {
        switch self {
        case .placeholder:
            "placeholder"
        }
    }
}
