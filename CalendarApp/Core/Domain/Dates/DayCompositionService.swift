import Foundation

struct DayCompositionService: Sendable {
    let resolver: DayStatusResolver

    init(resolver: DayStatusResolver = DayStatusResolver()) {
        self.resolver = resolver
    }

    func compose(
        dayID: DayID,
        holidayState: HolidayYearRefreshState,
        userOverride: UserDayOverride? = nil,
        vacationPeriods: [VacationPeriod] = [],
        specialDays: [SpecialDay] = [],
        schedules: [ScheduleItem] = [],
        dateKnowledgeSnapshot: DateKnowledgeYearSnapshot? = nil
    ) -> DayPresentation {
        let basePresentation: DayPresentation
        let holidayRecord: HolidayRecord?
        let holidayProviderID: String
        let holidaySourceURL: URL?
        switch holidayState {
        case let .available(snapshot):
            let records = Dictionary(
                uniqueKeysWithValues: snapshot.records.map { ($0.dayID, $0) }
            )
            holidayRecord = records[dayID]
            holidayProviderID = snapshot.providerID
            holidaySourceURL = snapshot.sourceURL
            basePresentation = resolver.resolve(
                dayID: dayID,
                userOverride: userOverride,
                holidayRecord: holidayRecord,
                holidayProviderID: holidayProviderID
            )
        case .notPublished:
            holidayRecord = nil
            holidayProviderID = "official"
            holidaySourceURL = nil
            basePresentation = unknownPresentation(
                dayID: dayID,
                reason: "官方节假日安排尚未发布",
                userOverride: userOverride
            )
        case .unavailable:
            holidayRecord = nil
            holidayProviderID = "official"
            holidaySourceURL = nil
            basePresentation = unknownPresentation(
                dayID: dayID,
                reason: "节假日数据暂不可用",
                userOverride: userOverride
            )
        }

        return addingPersonalDates(
            to: basePresentation,
            dayID: dayID,
            vacationPeriods: vacationPeriods,
            specialDays: specialDays,
            schedules: schedules,
            holidayRecord: holidayRecord,
            holidayProviderID: holidayProviderID,
            holidaySourceURL: holidaySourceURL,
            knowledgeAnnotations: dateKnowledgeSnapshot?.annotations(on: dayID) ?? []
        )
    }

    func compose(
        dayIDs: [DayID],
        holidayState: HolidayYearRefreshState,
        userOverrides: [DayID: UserDayOverride] = [:],
        vacationPeriods: [VacationPeriod] = [],
        specialDays: [SpecialDay] = [],
        schedules: [ScheduleItem] = [],
        dateKnowledgeSnapshot: DateKnowledgeYearSnapshot? = nil
    ) -> [DayID: DayPresentation] {
        let recordsByDay: [DayID: HolidayRecord]
        let providerID: String
        let sourceURL: URL?
        switch holidayState {
        case let .available(snapshot):
            recordsByDay = Dictionary(
                uniqueKeysWithValues: snapshot.records.map { ($0.dayID, $0) }
            )
            providerID = snapshot.providerID
            sourceURL = snapshot.sourceURL
        case .notPublished, .unavailable:
            recordsByDay = [:]
            providerID = "unknown"
            sourceURL = nil
        }

        return Dictionary(
            uniqueKeysWithValues: dayIDs.map { dayID in
                let presentation: DayPresentation
                switch holidayState {
                case .available:
                    presentation = resolver.resolve(
                        dayID: dayID,
                        userOverride: userOverrides[dayID],
                        holidayRecord: recordsByDay[dayID],
                        holidayProviderID: providerID
                    )
                case .notPublished:
                    presentation = unknownPresentation(
                        dayID: dayID,
                        reason: "官方节假日安排尚未发布",
                        userOverride: userOverrides[dayID]
                    )
                case .unavailable:
                    presentation = unknownPresentation(
                        dayID: dayID,
                        reason: "节假日数据暂不可用",
                        userOverride: userOverrides[dayID]
                    )
                }
                return (
                    dayID,
                    addingPersonalDates(
                        to: presentation,
                        dayID: dayID,
                        vacationPeriods: vacationPeriods,
                        specialDays: specialDays,
                        schedules: schedules,
                        holidayRecord: recordsByDay[dayID],
                        holidayProviderID: providerID,
                        holidaySourceURL: sourceURL,
                        knowledgeAnnotations: dateKnowledgeSnapshot?.annotations(on: dayID) ?? []
                    )
                )
            }
        )
    }

    private func addingPersonalDates(
        to presentation: DayPresentation,
        dayID: DayID,
        vacationPeriods: [VacationPeriod],
        specialDays: [SpecialDay],
        schedules: [ScheduleItem],
        holidayRecord: HolidayRecord?,
        holidayProviderID: String,
        holidaySourceURL: URL?,
        knowledgeAnnotations: [DayAnnotation]
    ) -> DayPresentation {
        let vacationLabels = vacationPeriods
            .filter { $0.contains(dayID) }
            .map(\.title)

        let specialDayLabels = specialDays
            .filter { $0.resolvedDay(for: dayID.year) == dayID }
            .map(\.title)

        let scheduleCount = schedules.reduce(into: 0) { count, schedule in
            if schedule.occurs(on: dayID) {
                count += 1
            }
        }

        let annotationResolution = DayAnnotationResolver().resolve(
            dayID: dayID,
            holidayRecord: holidayRecord,
            knowledgeAnnotations: knowledgeAnnotations,
            specialDays: specialDays,
            holidayProviderID: holidayProviderID,
            holidaySourceURL: holidaySourceURL
        )

        return DayPresentation(
            dayID: presentation.dayID,
            workStatus: presentation.workStatus,
            statusSource: presentation.statusSource,
            statusReason: presentation.statusReason,
            primaryAnnotation: annotationResolution.primary,
            annotationCandidates: annotationResolution.candidates,
            holidayLabels: presentation.holidayLabels,
            vacationLabels: vacationLabels,
            specialDayLabels: specialDayLabels,
            scheduleCount: presentation.scheduleCount + scheduleCount
        )
    }

    private func unknownPresentation(
        dayID: DayID,
        reason: String,
        userOverride: UserDayOverride?
    ) -> DayPresentation {
        if let userOverride {
            return resolver.resolve(dayID: dayID, userOverride: userOverride)
        }

        return DayPresentation(
            dayID: dayID,
            workStatus: .unknown,
            statusSource: .unknown,
            statusReason: reason
        )
    }
}
