import Foundation

enum WorkStatus: Codable, Hashable, Sendable {
    case workday
    case weekend
    case holiday
    case makeupWorkday
    case unknown

    var displayName: String {
        switch self {
        case .workday: "工作日"
        case .weekend: "周末"
        case .holiday: "休息日"
        case .makeupWorkday: "调休补班"
        case .unknown: "状态待确认"
        }
    }

    var isOffDay: Bool? {
        switch self {
        case .holiday, .weekend:
            true
        case .workday, .makeupWorkday:
            false
        case .unknown:
            nil
        }
    }

    var isWorkday: Bool? {
        switch self {
        case .workday, .makeupWorkday:
            true
        case .holiday, .weekend:
            false
        case .unknown:
            nil
        }
    }
}

enum DayStatusSource: Codable, Hashable, Sendable {
    case defaultWeekRule
    case userOverride
    case holidayProvider(providerID: String)
    case schoolOrCompany(name: String)
    case unknown
}

struct UserDayOverride: Codable, Hashable, Sendable {
    let dayID: DayID
    let status: WorkStatus
    let reason: String?

    init(dayID: DayID, status: WorkStatus, reason: String? = nil) {
        self.dayID = dayID
        self.status = status
        self.reason = reason
    }
}

struct DayPresentation: Codable, Hashable, Identifiable, Sendable {
    let dayID: DayID
    let workStatus: WorkStatus
    let statusSource: DayStatusSource
    let statusReason: String?
    let primaryAnnotation: DayAnnotation?
    let annotationCandidates: [DayAnnotation]
    let holidayLabels: [String]
    let vacationLabels: [String]
    let specialDayLabels: [String]
    let scheduleCount: Int

    var id: DayID { dayID }

    init(
        dayID: DayID,
        workStatus: WorkStatus,
        statusSource: DayStatusSource,
        statusReason: String? = nil,
        primaryAnnotation: DayAnnotation? = nil,
        annotationCandidates: [DayAnnotation] = [],
        holidayLabels: [String] = [],
        vacationLabels: [String] = [],
        specialDayLabels: [String] = [],
        scheduleCount: Int = 0
    ) {
        self.dayID = dayID
        self.workStatus = workStatus
        self.statusSource = statusSource
        self.statusReason = statusReason
        self.primaryAnnotation = primaryAnnotation
        self.annotationCandidates = annotationCandidates
        self.holidayLabels = holidayLabels
        self.vacationLabels = vacationLabels
        self.specialDayLabels = specialDayLabels
        self.scheduleCount = scheduleCount
    }
}
