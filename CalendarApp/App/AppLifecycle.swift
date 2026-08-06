import Observation

@MainActor
@Observable
final class AppLifecycle {
    var isActive = false

    func setActive(_ active: Bool) {
        isActive = active
    }
}
