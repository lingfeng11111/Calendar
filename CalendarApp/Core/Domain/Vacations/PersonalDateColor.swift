enum PersonalDateColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case blue
    case teal
    case purple
    case orange

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blue:
            "蓝色"
        case .teal:
            "青绿色"
        case .purple:
            "紫色"
        case .orange:
            "橙色"
        }
    }

}
