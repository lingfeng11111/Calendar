import Foundation

enum SpecialDayRecurrence: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case yearlyGregorian
    case yearlyLunar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:
            "仅此一次"
        case .yearlyGregorian:
            "每年公历"
        case .yearlyLunar:
            "每年农历"
        }
    }
}

enum SpecialDayValidationError: Error, Equatable, Sendable, LocalizedError {
    case emptyTitle
    case unsupportedRecurrence(SpecialDayRecurrence)
    case invalidGregorianDate

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            "特殊日期名称不能为空"
        case let .unsupportedRecurrence(recurrence):
            "暂不支持\(recurrence.displayName)重复规则"
        case .invalidGregorianDate:
            "特殊日期不是有效的公历日期"
        }
    }
}

struct SpecialDay: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var anchorDay: DayID
    var recurrence: SpecialDayRecurrence
    var color: PersonalDateColor
    var note: String?

    init(
        id: UUID = UUID(),
        title: String,
        anchorDay: DayID,
        recurrence: SpecialDayRecurrence = .none,
        color: PersonalDateColor = .purple,
        note: String? = nil
    ) throws {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw SpecialDayValidationError.emptyTitle
        }
        guard recurrence != .yearlyLunar else {
            throw SpecialDayValidationError.unsupportedRecurrence(recurrence)
        }

        if recurrence == .yearlyGregorian,
           DayID(year: 2000, month: anchorDay.month, day: anchorDay.day) == nil {
            throw SpecialDayValidationError.invalidGregorianDate
        }

        self.id = id
        self.title = normalizedTitle
        self.anchorDay = anchorDay
        self.recurrence = recurrence
        self.color = color
        self.note = note?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func resolvedDay(for year: Int) -> DayID? {
        switch recurrence {
        case .none:
            anchorDay.year == year ? anchorDay : nil
        case .yearlyGregorian:
            DayID(year: year, month: anchorDay.month, day: anchorDay.day)
        case .yearlyLunar:
            nil
        }
    }

    func isVisible(in year: Int) -> Bool {
        resolvedDay(for: year) != nil
    }
}
