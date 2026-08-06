import Foundation
import SwiftData
import XCTest
@testable import CalendarApp

private struct FixtureHolidayProvider: HolidayProvider {
    let id = "fixture"
    let snapshot: HolidayYearSnapshot

    func fetchYear(_ year: Int) async throws -> HolidayYearSnapshot {
        guard year == snapshot.year else {
            throw HolidayProviderError.invalidYear(year)
        }

        return snapshot
    }
}

private actor RecordingDateKnowledgeProvider: DateKnowledgeProvider {
    let id: String
    let outcome: Result<DateKnowledgeYearSnapshot, DateKnowledgeError>
    private var requestedYears: [Int] = []

    init(
        id: String,
        outcome: Result<DateKnowledgeYearSnapshot, DateKnowledgeError>
    ) {
        self.id = id
        self.outcome = outcome
    }

    func fetchYear(_ year: Int) async throws -> DateKnowledgeYearSnapshot {
        requestedYears.append(year)
        return try outcome.get()
    }

    func requestedYearList() -> [Int] {
        requestedYears
    }
}

private struct HTTPFixturePayload: Codable, Equatable, Sendable {
    let value: String
}

private enum URLProtocolStubError: Error, Sendable {
    case missingHandler
    case missingURL
}

private final class URLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLProtocolStubError.missingHandler)
            return
        }

        Self.lastRequest = request
        Self.requestCount += 1

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private enum RecordingProviderOutcome: Sendable {
    case success(HolidayYearSnapshot)
    case failure(HolidayProviderError)
}

private actor RecordingHolidayProvider: HolidayProvider {
    let id: String
    let outcome: RecordingProviderOutcome
    private var requestedYears: [Int] = []

    init(id: String, outcome: RecordingProviderOutcome) {
        self.id = id
        self.outcome = outcome
    }

    func fetchYear(_ year: Int) async throws -> HolidayYearSnapshot {
        requestedYears.append(year)

        switch outcome {
        case let .success(snapshot):
            return snapshot
        case let .failure(error):
            throw error
        }
    }

    func requestedYearList() -> [Int] {
        requestedYears
    }
}

private actor MultiYearHolidayProvider: HolidayProvider {
    let id: String
    let snapshots: [Int: HolidayYearSnapshot]
    private var requestedYears: [Int] = []

    init(id: String, snapshots: [Int: HolidayYearSnapshot]) {
        self.id = id
        self.snapshots = snapshots
    }

    func fetchYear(_ year: Int) async throws -> HolidayYearSnapshot {
        requestedYears.append(year)

        guard let snapshot = snapshots[year] else {
            throw HolidayProviderError.notPublished
        }

        return snapshot
    }

    func requestedYearList() -> [Int] {
        requestedYears
    }
}

@MainActor
private final class MockSystemCalendarService: SystemCalendarServiceProtocol {
    var access: SystemCalendarAccess
    let requestedAccess: SystemCalendarAccess
    var requestCount = 0
    var fixtureEvents: [SystemCalendarEventSnapshot] = []
    var eventError: SystemCalendarServiceError?

    init(
        access: SystemCalendarAccess,
        requestedAccess: SystemCalendarAccess
    ) {
        self.access = access
        self.requestedAccess = requestedAccess
    }

    func requestReadAccess() async -> SystemCalendarAccess {
        requestCount += 1
        access = requestedAccess
        return access
    }

    func events(
        in interval: DateInterval,
        calendarIDs: Set<String>?
    ) async throws -> [SystemCalendarEventSnapshot] {
        guard interval.start <= interval.end else {
            throw SystemCalendarServiceError.invalidDateRange
        }
        if let eventError {
            throw eventError
        }
        return fixtureEvents
    }
}

@MainActor
private final class FixtureHolidayRepository: HolidayRepositoryProtocol {
    var result: Result<HolidayYearSnapshot, HolidayRepositoryError>

    init(result: Result<HolidayYearSnapshot, HolidayRepositoryError>) {
        self.result = result
    }

    func snapshot(for year: Int) async throws -> HolidayYearSnapshot {
        try result.get()
    }

    func refresh(year: Int) async throws -> HolidayYearSnapshot {
        try result.get()
    }

    func refreshWindow(referenceDate: Date?) async throws -> HolidayRefreshReport {
        throw HolidayRepositoryError.persistenceFailed
    }
}

@MainActor
private final class FixtureDateKnowledgeRepository: DateKnowledgeRepositoryProtocol {
    var result: Result<DateKnowledgeYearSnapshot, DateKnowledgeError>

    init(result: Result<DateKnowledgeYearSnapshot, DateKnowledgeError>) {
        self.result = result
    }

    func snapshot(for year: Int) async throws -> DateKnowledgeYearSnapshot {
        try result.get()
    }
}

final class CalendarAppTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        URLProtocolStub.lastRequest = nil
        URLProtocolStub.requestCount = 0
        super.tearDown()
    }

    func testPrimaryTabsAreStable() {
        XCTAssertEqual(
            AppTab.allCases.map(\.rawValue),
            ["calendar", "vacation", "settings"]
        )
    }

    @MainActor
    func testSystemCalendarAccessSeparatesReadPermissionFromWriteOnlyAccess() {
        XCTAssertTrue(SystemCalendarAccess.fullAccess.canRead)
        XCTAssertFalse(SystemCalendarAccess.writeOnly.canRead)
        XCTAssertFalse(SystemCalendarAccess.denied.canRead)
        XCTAssertEqual(SystemCalendarAccess.notDetermined.displayName, "尚未请求访问")
    }

    @MainActor
    func testSettingsFeatureRequestsReadAccessWithoutWritingLocalSchedules() async {
        let service = MockSystemCalendarService(
            access: .notDetermined,
            requestedAccess: .fullAccess
        )
        let model = SettingsFeatureModel(systemCalendarService: service)

        XCTAssertEqual(model.systemCalendarAccess, .notDetermined)
        await model.requestSystemCalendarReadAccess()

        XCTAssertEqual(model.systemCalendarAccess, .fullAccess)
        XCTAssertEqual(model.systemCalendarState, .ready)
        XCTAssertEqual(service.requestCount, 1)
    }

    func testSystemCalendarEventSnapshotUsesExternalIdentifierAndOccurrenceStartForIdentity() throws {
        let startDate = try makeShanghaiDate(year: 2026, month: 8, day: 6)
        let event = SystemCalendarEventSnapshot(
            externalIdentifier: "external-event",
            calendarItemIdentifier: "local-event",
            title: " 项目评审 ",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(3600),
            isAllDay: false,
            timeZoneIdentifier: DayID.defaultTimeZoneIdentifier,
            calendarIdentifier: "calendar-id",
            calendarTitle: "工作"
        )

        XCTAssertEqual(event.title, "项目评审")
        XCTAssertEqual(
            event.id,
            "external-event|\(Int64(startDate.timeIntervalSince1970 * 1_000))"
        )
        XCTAssertEqual(event.calendarTitle, "工作")
    }

    func testVacationPeriodRejectsEmptyTitleAndReversedRange() throws {
        let start = try XCTUnwrap(DayID(year: 2026, month: 7, day: 1))
        let end = try XCTUnwrap(DayID(year: 2026, month: 7, day: 5))

        XCTAssertThrowsError(
            try VacationPeriod(
                title: "   ",
                kind: .custom,
                startDay: start,
                endDay: end
            )
        ) { error in
            XCTAssertEqual(error as? VacationPeriodValidationError, .emptyTitle)
        }

        XCTAssertThrowsError(
            try VacationPeriod(
                title: "顺序错误",
                kind: .custom,
                startDay: end,
                endDay: start
            )
        ) { error in
            XCTAssertEqual(error as? VacationPeriodValidationError, .invalidRange)
        }
    }

    func testVacationPeriodCountsInclusiveDaysAndOverlapsYear() throws {
        let start = try XCTUnwrap(DayID(year: 2025, month: 12, day: 29))
        let end = try XCTUnwrap(DayID(year: 2026, month: 1, day: 3))
        let period = try VacationPeriod(
            title: "跨年假期",
            kind: .custom,
            startDay: start,
            endDay: end
        )

        XCTAssertEqual(period.dayCount, 6)
        XCTAssertTrue(period.overlaps(year: 2025))
        XCTAssertTrue(period.overlaps(year: 2026))
        XCTAssertTrue(period.contains(try XCTUnwrap(DayID(year: 2026, month: 1, day: 1))))
        XCTAssertFalse(period.contains(try XCTUnwrap(DayID(year: 2026, month: 1, day: 4))))
    }

    func testSpecialDayRejectsUnsupportedLunarRuleAndResolvesGregorianRule() throws {
        let anchor = try XCTUnwrap(DayID(year: 2000, month: 10, day: 18))

        XCTAssertThrowsError(
            try SpecialDay(
                title: "生日",
                anchorDay: anchor,
                recurrence: .yearlyLunar
            )
        ) { error in
            XCTAssertEqual(
                error as? SpecialDayValidationError,
                .unsupportedRecurrence(.yearlyLunar)
            )
        }

        let birthday = try SpecialDay(
            title: "生日",
            anchorDay: anchor,
            recurrence: .yearlyGregorian
        )
        XCTAssertEqual(birthday.resolvedDay(for: 2026)?.description, "2026-10-18")
        XCTAssertEqual(birthday.resolvedDay(for: 2025)?.description, "2025-10-18")
    }

    @MainActor
    func testVacationRepositorySeedsAndFiltersAnnualSnapshot() throws {
        let container = try makeModelContainer()
        let repository = VacationRepository(modelContext: ModelContext(container))

        try repository.seedIfEmpty(with: PersonalDateFixtures.sample)

        let current = try repository.snapshot(for: 2026)
        XCTAssertEqual(current.vacationPeriods.map(\.title), ["寒假", "四月年假"])
        XCTAssertEqual(current.specialDays.map(\.title), ["年度体检", "生日"])
        XCTAssertEqual(current.vacationPeriods.reduce(0) { $0 + $1.dayCount }, 33)

        let previous = try repository.snapshot(for: 2025)
        XCTAssertTrue(previous.vacationPeriods.isEmpty)
        XCTAssertEqual(previous.specialDays.map(\.title), ["生日"])
    }

    @MainActor
    func testVacationRepositoryCreatesUpdatesAndDeletesPersonalDates() throws {
        let container = try makeModelContainer()
        let repository = VacationRepository(modelContext: ModelContext(container))
        let start = try XCTUnwrap(DayID(year: 2026, month: 7, day: 1))
        let end = try XCTUnwrap(DayID(year: 2026, month: 7, day: 5))
        let id = UUID(uuidString: "C0000000-0000-0000-0000-000000000001")!

        var period = try VacationPeriod(
            id: id,
            title: "暑假",
            kind: .summer,
            startDay: start,
            endDay: end
        )
        try repository.save(period: period)

        XCTAssertEqual(try repository.snapshot(for: 2026).vacationPeriods.map(\.title), ["暑假"])

        period.title = "调整后的暑假"
        period.endDay = try XCTUnwrap(DayID(year: 2026, month: 7, day: 10))
        try repository.save(period: period)
        let updated = try repository.snapshot(for: 2026).vacationPeriods
        XCTAssertEqual(updated.first?.title, "调整后的暑假")
        XCTAssertEqual(updated.first?.dayCount, 10)

        try repository.deleteVacationPeriod(id: id)
        XCTAssertTrue(try repository.snapshot(for: 2026).vacationPeriods.isEmpty)

        let specialDay = try SpecialDay(
            id: UUID(uuidString: "C0000000-0000-0000-0000-000000000002")!,
            title: "纪念日",
            anchorDay: try XCTUnwrap(DayID(year: 2026, month: 8, day: 8)),
            recurrence: .yearlyGregorian
        )
        try repository.save(specialDay: specialDay)
        XCTAssertEqual(try repository.snapshot(for: 2027).specialDays.map(\.title), ["纪念日"])
        try repository.deleteSpecialDay(id: specialDay.id)
        XCTAssertTrue(try repository.snapshot(for: 2027).specialDays.isEmpty)
    }

    func testScheduleItemValidatesRangeAndMatchesRecurringDays() throws {
        let start = try makeShanghaiDate(year: 2026, month: 8, day: 6)
            .addingTimeInterval(9 * 60 * 60)
        let end = start.addingTimeInterval(60 * 60)

        XCTAssertThrowsError(
            try ScheduleItem(title: "   ", startDate: start, endDate: end)
        ) { error in
            XCTAssertEqual(error as? ScheduleItemValidationError, .emptyTitle)
        }

        XCTAssertThrowsError(
            try ScheduleItem(title: "时间错误", startDate: end, endDate: start)
        ) { error in
            XCTAssertEqual(error as? ScheduleItemValidationError, .invalidRange)
        }

        XCTAssertThrowsError(
            try ScheduleItem(
                title: "缺少结束日期",
                startDate: start,
                endDate: end,
                recurrence: .daily
            )
        ) { error in
            XCTAssertEqual(error as? ScheduleItemValidationError, .missingRepeatEnd)
        }

        let repeatUntil = try makeShanghaiDate(year: 2026, month: 8, day: 8)
            .addingTimeInterval(23 * 60 * 60 + 59 * 60)
        let daily = try ScheduleItem(
            title: "每日阅读",
            startDate: start,
            endDate: end,
            recurrence: .daily,
            repeatUntil: repeatUntil
        )
        XCTAssertTrue(daily.occurs(on: try XCTUnwrap(DayID(year: 2026, month: 8, day: 6))))
        XCTAssertTrue(daily.occurs(on: try XCTUnwrap(DayID(year: 2026, month: 8, day: 8))))
        XCTAssertFalse(daily.occurs(on: try XCTUnwrap(DayID(year: 2026, month: 8, day: 9))))

        let weekly = try ScheduleItem(
            title: "每周复盘",
            startDate: start,
            endDate: end,
            recurrence: .weekly,
            repeatUntil: try makeShanghaiDate(year: 2026, month: 8, day: 31)
                .addingTimeInterval(23 * 60 * 60 + 59 * 60)
        )
        XCTAssertTrue(weekly.occurs(on: try XCTUnwrap(DayID(year: 2026, month: 8, day: 13))))
        XCTAssertFalse(weekly.occurs(on: try XCTUnwrap(DayID(year: 2026, month: 8, day: 14))))

        let crossDayWeekly = try ScheduleItem(
            title: "跨日每周值班",
            startDate: start,
            endDate: try makeShanghaiDate(year: 2026, month: 8, day: 7)
                .addingTimeInterval(60 * 60),
            recurrence: .weekly,
            repeatUntil: try makeShanghaiDate(year: 2026, month: 8, day: 20)
                .addingTimeInterval(23 * 60 * 60 + 59 * 60)
        )
        XCTAssertTrue(crossDayWeekly.occurs(on: try XCTUnwrap(DayID(year: 2026, month: 8, day: 7))))
        XCTAssertTrue(crossDayWeekly.occurs(on: try XCTUnwrap(DayID(year: 2026, month: 8, day: 14))))
        XCTAssertFalse(crossDayWeekly.occurs(on: try XCTUnwrap(DayID(year: 2026, month: 8, day: 15))))
        XCTAssertEqual(crossDayWeekly.coverageEndDay.description, "2026-08-21")

        let nearMidnight = try ScheduleItem(
            title: "上海午夜日程",
            startDate: makeShanghaiDate(year: 2026, month: 8, day: 6)
                .addingTimeInterval(23 * 60 * 60 + 30 * 60),
            endDate: makeShanghaiDate(year: 2026, month: 8, day: 7)
                .addingTimeInterval(30 * 60),
            isAllDay: false
        )
        XCTAssertTrue(nearMidnight.occurs(on: try XCTUnwrap(DayID(year: 2026, month: 8, day: 6))))
        XCTAssertTrue(nearMidnight.occurs(on: try XCTUnwrap(DayID(year: 2026, month: 8, day: 7))))
        XCTAssertFalse(nearMidnight.occurs(on: try XCTUnwrap(DayID(year: 2026, month: 8, day: 8))))
    }

    func testScheduleQueryMatchesTextKindColorAndDateRange() throws {
        let day = try XCTUnwrap(DayID(year: 2026, month: 8, day: 6))
        let start = try makeShanghaiDate(year: 2026, month: 8, day: 6)
            .addingTimeInterval(20 * 60 * 60)
        let schedule = try ScheduleItem(
            title: "晚间阅读",
            startDate: start,
            endDate: start.addingTimeInterval(30 * 60),
            recurrence: .daily,
            repeatUntil: try XCTUnwrap(DayID(year: 2026, month: 8, day: 12)).date,
            color: .purple,
            note: "阅读项目管理章节"
        )

        var query = ScheduleQuery(text: "项目管理")
        query.kind = .timed
        query.color = .purple
        query.startDay = try XCTUnwrap(DayID(year: 2026, month: 8, day: 10))
        query.endDay = try XCTUnwrap(DayID(year: 2026, month: 8, day: 11))

        XCTAssertTrue(query.matches(schedule))
        XCTAssertTrue(schedule.occurs(on: day))

        query.text = "不存在"
        XCTAssertFalse(query.matches(schedule))

        query.text = "晚间阅读"
        query.kind = .allDay
        XCTAssertFalse(query.matches(schedule))
    }

    @MainActor
    func testScheduleRepositoryCreatesUpdatesDeletesAndFiltersYear() throws {
        let container = try makeModelContainer()
        let repository = ScheduleRepository(modelContext: ModelContext(container))
        let start = try makeShanghaiDate(year: 2026, month: 8, day: 6)
            .addingTimeInterval(9 * 60 * 60)
        let end = start.addingTimeInterval(60 * 60)
        let id = UUID(uuidString: "E0000000-0000-0000-0000-000000000001")!

        var schedule = try ScheduleItem(
            id: id,
            title: "项目评审",
            startDate: start,
            endDate: end
        )
        try repository.save(schedule)
        XCTAssertEqual(try repository.snapshot(for: 2026).items.map(\.title), ["项目评审"])
        XCTAssertEqual(
            try repository.search(ScheduleQuery(text: "项目"), in: 2026).map(\.title),
            ["项目评审"]
        )
        XCTAssertTrue(try repository.snapshot(for: 2025).items.isEmpty)

        schedule.title = "调整后的项目评审"
        try repository.save(schedule)
        XCTAssertEqual(try repository.snapshot(for: 2026).items.first?.title, "调整后的项目评审")

        try repository.delete(id: id)
        XCTAssertTrue(try repository.snapshot(for: 2026).items.isEmpty)
    }

    func testDayIDUsesStableShanghaiCalendarDayIdentity() throws {
        let day = try XCTUnwrap(DayID(year: 2026, month: 1, day: 1))

        XCTAssertEqual(day.description, "2026-01-01")
        XCTAssertEqual(day.calendarIdentifier, DayID.defaultCalendarIdentifier)
        XCTAssertEqual(day.timeZoneIdentifier, DayID.defaultTimeZoneIdentifier)
        XCTAssertEqual(day, DayID(day.date ?? Date.distantPast))
    }

    func testDayIDRejectsInvalidGregorianDate() {
        XCTAssertNil(DayID(year: 2025, month: 2, day: 29))
        XCTAssertNotNil(DayID(year: 2024, month: 2, day: 29))
    }

    func testDayIDAddsDaysAcrossLeapDayAndNewYear() throws {
        let leapDay = try XCTUnwrap(DayID(year: 2024, month: 2, day: 29))
        let nextDay = leapDay.adding(days: 1)
        XCTAssertEqual(nextDay.description, "2024-03-01")
        XCTAssertEqual(leapDay.days(to: nextDay), 1)

        let yearEnd = try XCTUnwrap(DayID(year: 2025, month: 12, day: 31))
        XCTAssertEqual(yearEnd.adding(days: 1).description, "2026-01-01")
    }

    func testDayIDConversionUsesRequestedTimeZone() throws {
        let date = Date(timeIntervalSince1970: 1_767_283_200) // 2026-01-01 16:00 UTC
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let shanghai = try XCTUnwrap(TimeZone(identifier: DayID.defaultTimeZoneIdentifier))

        XCTAssertEqual(DayID(date, timeZone: utc).description, "2026-01-01")
        XCTAssertEqual(DayID(date, timeZone: shanghai).description, "2026-01-02")
    }

    func testCalendarMonthGridUsesMondayStartAndStableSevenColumns() throws {
        let month = try XCTUnwrap(CalendarMonth(year: 2026, month: 1))
        let grid = CalendarMonthGrid(month: month)

        XCTAssertEqual(grid.firstWeekday, CalendarMonthGrid.defaultFirstWeekday)
        XCTAssertEqual(grid.rowCount, 5)
        XCTAssertEqual(grid.days.count, 35)
        XCTAssertEqual(grid.days.first?.dayID.description, "2025-12-29")
        XCTAssertEqual(grid.days.last?.dayID.description, "2026-02-01")
        XCTAssertEqual(
            grid.days.filter(\.isInDisplayedMonth).count,
            31
        )
        XCTAssertTrue(
            zip(grid.days, grid.days.dropFirst()).allSatisfy { current, next in
                current.dayID.adding(days: 1) == next.dayID
            }
        )
    }

    func testCalendarMonthAddsMonthsAcrossYearBoundary() throws {
        let december = try XCTUnwrap(CalendarMonth(year: 2025, month: 12))
        let january = try XCTUnwrap(december.adding(months: 1))
        let previous = try XCTUnwrap(january.adding(months: -1))

        XCTAssertEqual(january, CalendarMonth(year: 2026, month: 1))
        XCTAssertEqual(previous, december)
    }

    func testDayCompositionUsesOfficialHolidayBeforeWeekendRule() throws {
        let snapshot = try makeHolidaySnapshot()
        let dayID = try XCTUnwrap(DayID(year: 2026, month: 2, day: 14))
        let composition = DayCompositionService()

        let presentation = composition.compose(
            dayID: dayID,
            holidayState: .available(snapshot)
        )

        XCTAssertEqual(presentation.workStatus, .makeupWorkday)
        XCTAssertEqual(presentation.statusSource, .holidayProvider(providerID: "fixture"))
        XCTAssertEqual(presentation.holidayLabels, ["春节调休"])
    }

    func testDayAnnotationResolverUsesPriorityAndRetainsCandidates() throws {
        let dayID = try XCTUnwrap(DayID(year: 2026, month: 2, day: 14))
        let annotations = [
            DayAnnotation(
                dayID: dayID,
                title: "普通纪念日",
                kind: .observance,
                sourceID: "observance"
            ),
            DayAnnotation(
                dayID: dayID,
                title: "立春",
                kind: .solarTerm,
                sourceID: "solar"
            ),
            DayAnnotation(
                dayID: dayID,
                title: "重要传统节日",
                kind: .importantTraditionalFestival,
                sourceID: "festival"
            ),
            DayAnnotation(
                dayID: dayID,
                title: "官方节假日",
                kind: .publicHoliday,
                sourceID: "holiday"
            )
        ]
        let holiday = HolidayRecord(
            dayID: dayID,
            name: "官方调休补班",
            kind: .makeupWorkday
        )

        let result = DayAnnotationResolver().resolve(
            dayID: dayID,
            holidayRecord: holiday,
            knowledgeAnnotations: annotations
        )

        XCTAssertEqual(result.primary?.kind, .makeupWorkday)
        XCTAssertEqual(
            result.candidates.map(\.kind),
            [.makeupWorkday, .publicHoliday, .solarTerm, .importantTraditionalFestival, .observance]
        )
        XCTAssertEqual(result.candidates.count, 5)
    }

    func testDateKnowledgeSnapshotValidatesYearAndSortsDeterministically() throws {
        let janFirst = try XCTUnwrap(DayID(year: 2026, month: 1, day: 1))
        let janSecond = try XCTUnwrap(DayID(year: 2026, month: 1, day: 2))
        let snapshot = try DateKnowledgeYearSnapshot(
            year: 2026,
            providerID: "fixture",
            fetchedAt: Date(timeIntervalSince1970: 100),
            annotations: [
                DayAnnotation(
                    dayID: janSecond,
                    title: "大寒",
                    kind: .solarTerm,
                    sourceID: "fixture"
                ),
                DayAnnotation(
                    dayID: janFirst,
                    title: "元旦纪念",
                    kind: .observance,
                    sourceID: "fixture"
                )
            ]
        )

        XCTAssertEqual(snapshot.annotations.map(\.dayID), [janFirst, janSecond])
        XCTAssertEqual(snapshot.annotations(on: janSecond).map(\.title), ["大寒"])

        XCTAssertThrowsError(
            try DateKnowledgeYearSnapshot(
                year: 2026,
                providerID: "fixture",
                fetchedAt: Date(timeIntervalSince1970: 0),
                annotations: [
                    DayAnnotation(
                        dayID: try XCTUnwrap(DayID(year: 2025, month: 12, day: 31)),
                        title: "跨年记录",
                        kind: .observance,
                        sourceID: "fixture"
                    )
                ]
            )
        ) { error in
            guard case let .annotationYearMismatch(dayID, expectedYear) = error as? DateKnowledgeError else {
                return XCTFail("Expected an annotation year mismatch")
            }
            XCTAssertEqual(dayID.description, "2025-12-31")
            XCTAssertEqual(expectedYear, 2026)
        }
    }

    func testSolarTermsProviderUsesConfiguredEndpointAndDecodesTerms() async throws {
        URLProtocolStub.requestHandler = { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                      url: url,
                      statusCode: 200,
                      httpVersion: nil,
                      headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLProtocolStubError.missingURL
            }

            let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "name" })?.value ?? "节气"
            let body = """
            {"code":1,"data":[{"jq_name":"\(name)","jq_time":"2026年1月1日4时50分54秒"}]}
            """
            return (response, Data(body.utf8))
        }

        let baseURL = try XCTUnwrap(URL(string: "https://example.test/solar_terms"))
        let fetchedAt = Date(timeIntervalSince1970: 300)
        let provider = SolarTermsDateKnowledgeProvider(
            baseURL: baseURL,
            client: makeStubHTTPClient(),
            now: { fetchedAt }
        )

        let snapshot = try await provider.fetchYear(2026)

        XCTAssertEqual(snapshot.providerID, "solar-terms-xmwxxc")
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
        XCTAssertEqual(snapshot.sourceURL, baseURL)
        XCTAssertEqual(snapshot.annotations.count, 24)
        XCTAssertEqual(snapshot.annotations.first?.dayID.description, "2026-01-01")
        XCTAssertEqual(URLProtocolStub.requestCount, 24)
        let requestURL = try XCTUnwrap(URLProtocolStub.lastRequest?.url)
        let components = try XCTUnwrap(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "year" })?.value, "2026")
        XCTAssertNotNil(components.queryItems?.first(where: { $0.name == "name" })?.value)
    }

    @MainActor
    func testDateKnowledgeRepositoryReturnsFreshCacheAndFallsBackToStaleCache() async throws {
        let dayID = try XCTUnwrap(DayID(year: 2026, month: 1, day: 5))
        let snapshot = try DateKnowledgeYearSnapshot(
            year: 2026,
            providerID: "fixture",
            fetchedAt: Date(timeIntervalSince1970: 50),
            sourceURL: URL(string: "https://example.test/date-knowledge/2026.json"),
            annotations: [
                DayAnnotation(
                    dayID: dayID,
                    title: "小寒",
                    kind: .solarTerm,
                    sourceID: "fixture"
                )
            ]
        )
        let container = try makeModelContainer()
        let context = ModelContext(container)
        let seedProvider = RecordingDateKnowledgeProvider(
            id: "seed",
            outcome: .success(snapshot)
        )
        let seedRepository = DateKnowledgeRepository(
            modelContext: context,
            primaryProvider: seedProvider,
            now: { Date(timeIntervalSince1970: 100) }
        )

        let seededSnapshot = try await seedRepository.snapshot(for: 2026)
        XCTAssertEqual(seededSnapshot, snapshot)

        let freshProvider = RecordingDateKnowledgeProvider(
            id: "fresh-unavailable",
            outcome: .failure(.notAvailable)
        )
        let freshRepository = DateKnowledgeRepository(
            modelContext: context,
            primaryProvider: freshProvider,
            cacheMaxAge: 60,
            now: { Date(timeIntervalSince1970: 100) }
        )
        let freshSnapshot = try await freshRepository.snapshot(for: 2026)
        XCTAssertEqual(freshSnapshot, snapshot)
        let freshRequests = await freshProvider.requestedYearList()
        XCTAssertEqual(freshRequests, [])

        let staleProvider = RecordingDateKnowledgeProvider(
            id: "stale-unavailable",
            outcome: .failure(.notAvailable)
        )
        let staleRepository = DateKnowledgeRepository(
            modelContext: context,
            primaryProvider: staleProvider,
            cacheMaxAge: 60,
            now: { Date(timeIntervalSince1970: 200) }
        )
        let staleSnapshot = try await staleRepository.snapshot(for: 2026)
        XCTAssertEqual(staleSnapshot, snapshot)
        let staleRequests = await staleProvider.requestedYearList()
        XCTAssertEqual(staleRequests, [2026])
    }

    func testDayCompositionMarksUnpublishedDatesAsUnknown() throws {
        let dayID = try XCTUnwrap(DayID(year: 2027, month: 1, day: 4))
        let composition = DayCompositionService()

        let presentation = composition.compose(
            dayID: dayID,
            holidayState: .notPublished
        )

        XCTAssertEqual(presentation.workStatus, .unknown)
        XCTAssertEqual(presentation.statusSource, .unknown)
        XCTAssertEqual(presentation.statusReason, "官方节假日安排尚未发布")
    }

    func testDayCompositionAddsPersonalVacationAndSpecialDayLabels() throws {
        let winterStart = try XCTUnwrap(DayID(year: 2026, month: 1, day: 24))
        let winterEnd = try XCTUnwrap(DayID(year: 2026, month: 2, day: 20))
        let period = try VacationPeriod(
            title: "寒假",
            kind: .winter,
            startDay: winterStart,
            endDay: winterEnd
        )
        let specialDay = try SpecialDay(
            title: "生日",
            anchorDay: try XCTUnwrap(DayID(year: 2000, month: 10, day: 18)),
            recurrence: .yearlyGregorian
        )
        let composition = DayCompositionService()

        let vacationPresentation = composition.compose(
            dayID: try XCTUnwrap(DayID(year: 2026, month: 1, day: 30)),
            holidayState: .unavailable,
            vacationPeriods: [period],
            specialDays: [specialDay]
        )
        XCTAssertEqual(vacationPresentation.vacationLabels, ["寒假"])
        XCTAssertTrue(vacationPresentation.specialDayLabels.isEmpty)

        let specialPresentation = composition.compose(
            dayID: try XCTUnwrap(DayID(year: 2026, month: 10, day: 18)),
            holidayState: .unavailable,
            vacationPeriods: [period],
            specialDays: [specialDay]
        )
        XCTAssertEqual(specialPresentation.specialDayLabels, ["生日"])
    }

    func testDayCompositionAddsScheduleCount() throws {
        let start = try makeShanghaiDate(year: 2026, month: 8, day: 6)
            .addingTimeInterval(9 * 60 * 60)
        let schedule = try ScheduleItem(
            title: "项目评审",
            startDate: start,
            endDate: start.addingTimeInterval(60 * 60)
        )
        let presentation = DayCompositionService().compose(
            dayID: try XCTUnwrap(DayID(year: 2026, month: 8, day: 6)),
            holidayState: .unavailable,
            schedules: [schedule]
        )

        XCTAssertEqual(presentation.scheduleCount, 1)
    }

    @MainActor
    func testCalendarFeatureModelComposesPersonalDatesIntoMonth() async throws {
        let holidaySnapshot = try makeHolidaySnapshot()
        let holidayRepository = FixtureHolidayRepository(result: .success(holidaySnapshot))
        let container = try makeModelContainer()
        let vacationRepository = VacationRepository(modelContext: ModelContext(container))
        try vacationRepository.seedIfEmpty(with: PersonalDateFixtures.sample)
        let initialDate = try makeShanghaiDate(year: 2026, month: 1, day: 1)
        let model = CalendarFeatureModel(
            repository: holidayRepository,
            vacationRepository: vacationRepository,
            initialDate: initialDate
        )

        await model.load()

        let winterDay = try XCTUnwrap(DayID(year: 2026, month: 1, day: 30))
        XCTAssertEqual(model.presentation(for: winterDay).vacationLabels, ["寒假"])
    }

    @MainActor
    func testCalendarFeatureModelShowsPrimaryAnnotationAndUpcomingTimeline() async throws {
        let holidaySnapshot = try makeHolidaySnapshot()
        let holidayRepository = FixtureHolidayRepository(result: .success(holidaySnapshot))
        let solarTermDay = try XCTUnwrap(DayID(year: 2026, month: 1, day: 5))
        let festivalDay = try XCTUnwrap(DayID(year: 2026, month: 1, day: 18))
        let knowledgeSnapshot = try DateKnowledgeYearSnapshot(
            year: 2026,
            providerID: "fixture-date-knowledge",
            fetchedAt: Date(timeIntervalSince1970: 80),
            sourceURL: URL(string: "https://example.test/date-knowledge/2026.json"),
            annotations: [
                DayAnnotation(
                    dayID: solarTermDay,
                    title: "小寒",
                    kind: .solarTerm,
                    sourceID: "fixture"
                ),
                DayAnnotation(
                    dayID: festivalDay,
                    title: "传统节日示例",
                    kind: .importantTraditionalFestival,
                    sourceID: "fixture"
                )
            ]
        )
        let knowledgeRepository = FixtureDateKnowledgeRepository(result: .success(knowledgeSnapshot))
        let model = CalendarFeatureModel(
            repository: holidayRepository,
            dateKnowledgeRepository: knowledgeRepository,
            initialDate: try makeShanghaiDate(year: 2026, month: 1, day: 1)
        )

        await model.load()

        XCTAssertEqual(model.presentation(for: solarTermDay).primaryAnnotation?.title, "小寒")
        XCTAssertEqual(model.monthOverview.annotationCount, 3)
        XCTAssertEqual(model.upcomingDates.map(\.title), ["元旦", "小寒", "传统节日示例"])
    }

    @MainActor
    func testCalendarAndDayDetailModelsComposeLocalSchedules() async throws {
        let holidaySnapshot = try makeHolidaySnapshot()
        let holidayRepository = FixtureHolidayRepository(result: .success(holidaySnapshot))
        let container = try makeModelContainer()
        let scheduleRepository = ScheduleRepository(modelContext: ModelContext(container))
        let start = try makeShanghaiDate(year: 2026, month: 8, day: 6)
            .addingTimeInterval(9 * 60 * 60)
        let schedule = try ScheduleItem(
            title: "项目评审",
            startDate: start,
            endDate: start.addingTimeInterval(60 * 60)
        )
        try scheduleRepository.save(schedule)

        let calendarModel = CalendarFeatureModel(
            repository: holidayRepository,
            scheduleRepository: scheduleRepository,
            initialDate: try makeShanghaiDate(year: 2026, month: 8, day: 6)
        )
        await calendarModel.load()
        XCTAssertEqual(
            calendarModel.presentation(for: try XCTUnwrap(DayID(year: 2026, month: 8, day: 6))).scheduleCount,
            1
        )

        let detailModel = DayDetailFeatureModel(
            dayID: try XCTUnwrap(DayID(year: 2026, month: 8, day: 6)),
            repository: holidayRepository,
            scheduleRepository: scheduleRepository
        )
        await detailModel.load()
        XCTAssertEqual(detailModel.scheduleItems.map(\.title), ["项目评审"])
        XCTAssertEqual(detailModel.presentation.scheduleCount, 1)
    }

    @MainActor
    func testDayDetailFeatureModelLoadsReadOnlySystemCalendarEvents() async throws {
        let dayID = try XCTUnwrap(DayID(year: 2026, month: 8, day: 6))
        let startDate = try makeShanghaiDate(year: 2026, month: 8, day: 6)
            .addingTimeInterval(9 * 60 * 60)
        let event = SystemCalendarEventSnapshot(
            externalIdentifier: "system-event",
            calendarItemIdentifier: "system-item",
            title: "系统会议",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(60 * 60),
            isAllDay: false,
            timeZoneIdentifier: DayID.defaultTimeZoneIdentifier,
            calendarIdentifier: "work-calendar",
            calendarTitle: "工作",
            sourceTitle: "公司账号",
            recurrenceDescription: "每周",
            note: "只读事件"
        )
        let service = MockSystemCalendarService(
            access: .fullAccess,
            requestedAccess: .fullAccess
        )
        service.fixtureEvents = [event]
        let model = DayDetailFeatureModel(
            dayID: dayID,
            repository: FixtureHolidayRepository(result: .success(try makeHolidaySnapshot())),
            systemCalendarService: service
        )

        await model.load()

        XCTAssertEqual(model.systemCalendarState, .loaded)
        XCTAssertEqual(model.systemCalendarAccess, .fullAccess)
        XCTAssertEqual(model.systemCalendarEvents, [event])
        XCTAssertEqual(model.systemCalendarEvents.first?.sourceTitle, "公司账号")
    }

    @MainActor
    func testDayDetailFeatureModelDoesNotPromptWhenSystemCalendarPermissionIsUndetermined() async throws {
        let service = MockSystemCalendarService(
            access: .notDetermined,
            requestedAccess: .fullAccess
        )
        let model = DayDetailFeatureModel(
            dayID: try XCTUnwrap(DayID(year: 2026, month: 8, day: 6)),
            repository: nil,
            systemCalendarService: service
        )

        await model.load()

        XCTAssertEqual(model.systemCalendarState, .permissionRequired)
        XCTAssertEqual(model.systemCalendarAccess, .notDetermined)
        XCTAssertEqual(service.requestCount, 0)
        XCTAssertTrue(model.systemCalendarEvents.isEmpty)
    }

    @MainActor
    func testDayDetailFeatureModelSurfacesSystemCalendarReadFailure() async throws {
        let service = MockSystemCalendarService(
            access: .fullAccess,
            requestedAccess: .fullAccess
        )
        service.eventError = .readFailed
        let model = DayDetailFeatureModel(
            dayID: try XCTUnwrap(DayID(year: 2026, month: 8, day: 6)),
            repository: nil,
            systemCalendarService: service
        )

        await model.load()

        XCTAssertEqual(model.systemCalendarState, .failed)
        XCTAssertEqual(model.systemCalendarErrorMessage, "系统日历读取失败")
        XCTAssertTrue(model.systemCalendarEvents.isEmpty)
    }

    @MainActor
    func testDayDetailFeatureModelDisplaysHolidaySourceAndMetadata() async throws {
        let snapshot = try makeHolidaySnapshot()
        let dayID = try XCTUnwrap(DayID(year: 2026, month: 2, day: 14))
        let repository = FixtureHolidayRepository(result: .success(snapshot))
        let model = DayDetailFeatureModel(dayID: dayID, repository: repository)

        await model.load()

        XCTAssertEqual(model.dataState, .loaded)
        XCTAssertEqual(model.presentation.workStatus, .makeupWorkday)
        XCTAssertEqual(model.presentation.holidayLabels, ["春节调休"])
        XCTAssertEqual(model.presentation.statusSource, .holidayProvider(providerID: "fixture"))
        XCTAssertEqual(model.sourceURL, snapshot.sourceURL)
        XCTAssertEqual(model.fetchedAt, snapshot.fetchedAt)
    }

    @MainActor
    func testDayDetailFeatureModelKeepsDateKnowledgeCandidatesAndSource() async throws {
        let holidaySnapshot = try makeHolidaySnapshot()
        let dayID = try XCTUnwrap(DayID(year: 2026, month: 2, day: 14))
        let knowledgeSnapshot = try DateKnowledgeYearSnapshot(
            year: 2026,
            providerID: "fixture-date-knowledge",
            fetchedAt: Date(timeIntervalSince1970: 90),
            sourceURL: URL(string: "https://example.test/date-knowledge/2026.json"),
            annotations: [
                DayAnnotation(
                    dayID: dayID,
                    title: "节气示例",
                    kind: .solarTerm,
                    sourceID: "fixture-date-knowledge"
                )
            ]
        )
        let model = DayDetailFeatureModel(
            dayID: dayID,
            repository: FixtureHolidayRepository(result: .success(holidaySnapshot)),
            dateKnowledgeRepository: FixtureDateKnowledgeRepository(result: .success(knowledgeSnapshot))
        )

        await model.load()

        XCTAssertEqual(model.presentation.primaryAnnotation?.title, "春节调休")
        XCTAssertEqual(model.presentation.annotationCandidates.map(\.title), ["春节调休", "节气示例"])
        XCTAssertEqual(model.dateKnowledgeProviderID, knowledgeSnapshot.providerID)
        XCTAssertEqual(model.dateKnowledgeSourceURL, knowledgeSnapshot.sourceURL)
        XCTAssertEqual(model.dateKnowledgeFetchedAt, knowledgeSnapshot.fetchedAt)
    }

    @MainActor
    func testDayDetailFeatureModelMapsUnpublishedStateWithoutProviderErrorDetails() async throws {
        let dayID = try XCTUnwrap(DayID(year: 2027, month: 1, day: 4))
        let repository = FixtureHolidayRepository(result: .failure(.notPublished(2027)))
        let model = DayDetailFeatureModel(dayID: dayID, repository: repository)

        await model.load()

        XCTAssertEqual(model.dataState, .notPublished)
        XCTAssertEqual(model.presentation.workStatus, .unknown)
        XCTAssertEqual(model.presentation.statusSource, .unknown)
        XCTAssertEqual(model.presentation.statusReason, "官方节假日安排尚未发布")
        XCTAssertNil(model.sourceURL)
        XCTAssertNil(model.fetchedAt)
    }

    @MainActor
    func testCalendarFeatureModelKeepsVisibleContentWhenRefreshFails() async throws {
        let snapshot = try makeHolidaySnapshot()
        let repository = FixtureHolidayRepository(result: .success(snapshot))
        let initialDate = try makeShanghaiDate(year: 2026, month: 1, day: 1)
        let model = CalendarFeatureModel(
            repository: repository,
            initialDate: initialDate
        )

        await model.load()
        let newYear = try XCTUnwrap(DayID(year: 2026, month: 1, day: 1))
        let visiblePresentation = model.presentation(for: newYear)

        repository.result = .failure(.providersUnavailable(
            primary: .networkUnavailable,
            backup: nil
        ))
        await model.load()

        XCTAssertEqual(model.dataState, .refreshFailed)
        XCTAssertEqual(model.presentation(for: newYear), visiblePresentation)
        XCTAssertEqual(model.errorMessage, "刷新失败，继续显示上次有效数据")
    }

    @MainActor
    func testDayDetailFeatureModelKeepsVisibleContentWhenRefreshFails() async throws {
        let snapshot = try makeHolidaySnapshot()
        let dayID = try XCTUnwrap(DayID(year: 2026, month: 2, day: 14))
        let repository = FixtureHolidayRepository(result: .success(snapshot))
        let model = DayDetailFeatureModel(dayID: dayID, repository: repository)

        await model.load()
        let visiblePresentation = model.presentation
        let visibleSourceURL = model.sourceURL

        repository.result = .failure(.providersUnavailable(
            primary: .networkUnavailable,
            backup: nil
        ))
        await model.load()

        XCTAssertEqual(model.dataState, .refreshFailed)
        XCTAssertEqual(model.presentation, visiblePresentation)
        XCTAssertEqual(model.sourceURL, visibleSourceURL)
        XCTAssertEqual(model.errorMessage, "刷新失败，继续显示上次有效数据")
    }

    func testResolverUsesWeekRuleForDefaultStatus() throws {
        let resolver = DayStatusResolver()
        let weekday = try XCTUnwrap(DayID(year: 2026, month: 1, day: 2))
        let weekend = try XCTUnwrap(DayID(year: 2026, month: 1, day: 3))

        XCTAssertEqual(resolver.resolve(dayID: weekday).workStatus, .workday)
        XCTAssertEqual(resolver.resolve(dayID: weekend).workStatus, .weekend)
    }

    func testResolverUserOverrideTakesPriorityOverWeekendRule() throws {
        let resolver = DayStatusResolver()
        let weekend = try XCTUnwrap(DayID(year: 2026, month: 1, day: 3))
        let override = UserDayOverride(
            dayID: weekend,
            status: .makeupWorkday,
            reason: "个人补班"
        )

        let presentation = resolver.resolve(dayID: weekend, userOverride: override)

        XCTAssertEqual(presentation.workStatus, .makeupWorkday)
        XCTAssertEqual(presentation.statusSource, .userOverride)
        XCTAssertEqual(presentation.statusReason, "个人补班")
    }

    func testHolidayCNDTOMapsOffDayAndMakeupWorkday() throws {
        let payload = """
        {
          "year": 2026,
          "papers": ["https://example.com/holiday-plan-2026"],
          "days": [
            {"name": "元旦", "date": "2026-01-01", "isOffDay": true},
            {"name": "春节调休", "date": "2026-02-14", "isOffDay": false}
          ]
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode(HolidayCNYearDTO.self, from: payload)
        let sourceURL = try XCTUnwrap(URL(string: "https://raw.example.test/2026.json"))
        let snapshot = try dto.makeSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_754_000_000),
            sourceURL: sourceURL
        )

        XCTAssertEqual(snapshot.year, 2026)
        XCTAssertEqual(snapshot.providerID, "holiday-cn")
        XCTAssertEqual(snapshot.sourceURL, sourceURL)
        XCTAssertEqual(snapshot.records.map(\.dayID.description), ["2026-01-01", "2026-02-14"])
        XCTAssertEqual(snapshot.records[0].workStatus, .holiday)
        XCTAssertEqual(snapshot.records[1].workStatus, .makeupWorkday)
    }

    func testHolidayCNDTOAcceptsISO8601DateTimeWithoutChangingCalendarDay() throws {
        let dto = HolidayCNYearDTO(
            year: 2026,
            papers: [],
            days: [
                HolidayCNDayDTO(
                    name: "元旦",
                    date: "2026-01-01T00:00:00+08:00",
                    isOffDay: true
                )
            ]
        )

        let snapshot = try dto.makeSnapshot(fetchedAt: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(snapshot.records.first?.dayID.description, "2026-01-01")
    }

    func testHolidaySnapshotRejectsDuplicateDates() throws {
        let day = try XCTUnwrap(DayID(year: 2026, month: 1, day: 1))
        let records = [
            HolidayRecord(dayID: day, name: "元旦", kind: .holiday),
            HolidayRecord(dayID: day, name: "重复记录", kind: .makeupWorkday)
        ]

        XCTAssertThrowsError(
            try HolidayYearSnapshot(
                year: 2026,
                providerID: "fixture",
                fetchedAt: Date(timeIntervalSince1970: 0),
                records: records
            )
        ) { error in
            XCTAssertEqual(error as? HolidayDataError, .duplicateDate(day))
        }
    }

    func testHolidaySnapshotRejectsRecordFromAnotherYear() throws {
        let recordDay = try XCTUnwrap(DayID(year: 2025, month: 12, day: 31))
        let record = HolidayRecord(dayID: recordDay, name: "跨年错误记录", kind: .holiday)

        XCTAssertThrowsError(
            try HolidayYearSnapshot(
                year: 2026,
                providerID: "fixture",
                fetchedAt: Date(timeIntervalSince1970: 0),
                records: [record]
            )
        ) { error in
            XCTAssertEqual(
                error as? HolidayDataError,
                .recordYearMismatch(dayID: recordDay, expectedYear: 2026)
            )
        }
    }

    func testHolidayCNDTORejectsInvalidDate() throws {
        let dto = HolidayCNYearDTO(
            year: 2026,
            papers: [],
            days: [HolidayCNDayDTO(name: "无效日期", date: "2026-02-30", isOffDay: true)]
        )

        XCTAssertThrowsError(try dto.makeSnapshot(fetchedAt: Date(timeIntervalSince1970: 0))) { error in
            XCTAssertEqual(error as? HolidayDataError, .invalidDate("2026-02-30"))
        }
    }

    func testHolidayProviderCanBeReplacedByFixture() async throws {
        let day = try XCTUnwrap(DayID(year: 2026, month: 1, day: 1))
        let snapshot = try HolidayYearSnapshot(
            year: 2026,
            providerID: "fixture",
            fetchedAt: Date(timeIntervalSince1970: 0),
            records: [HolidayRecord(dayID: day, name: "元旦", kind: .holiday)]
        )
        let provider = FixtureHolidayProvider(snapshot: snapshot)

        let fetched = try await provider.fetchYear(2026)

        XCTAssertEqual(provider.id, "fixture")
        XCTAssertEqual(fetched, snapshot)
    }

    func testHTTPClientDecodesJSONAndAddsGETHeaders() async throws {
        URLProtocolStub.requestHandler = { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                      url: url,
                      statusCode: 200,
                      httpVersion: nil,
                      headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLProtocolStubError.missingURL
            }

            return (response, Data(#"{"value":"ok"}"#.utf8))
        }

        let client = makeStubHTTPClient()
        let endpoint = try XCTUnwrap(URL(string: "https://example.test/payload"))
        let payload = try await client.get(HTTPFixturePayload.self, from: endpoint)

        XCTAssertEqual(payload, HTTPFixturePayload(value: "ok"))
        XCTAssertEqual(URLProtocolStub.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(URLProtocolStub.lastRequest?.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(URLProtocolStub.lastRequest?.timeoutInterval ?? 0, 5, accuracy: 0.001)
    }

    func testHTTPClientClassifiesStatusAndDecodingFailures() async throws {
        URLProtocolStub.requestHandler = { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                      url: url,
                      statusCode: 503,
                      httpVersion: nil,
                      headerFields: nil
                  ) else {
                throw URLProtocolStubError.missingURL
            }

            return (response, Data())
        }

        let client = makeStubHTTPClient()
        let endpoint = try XCTUnwrap(URL(string: "https://example.test/status"))

        do {
            let _: HTTPFixturePayload = try await client.get(HTTPFixturePayload.self, from: endpoint)
            XCTFail("Expected an HTTP status error")
        } catch {
            XCTAssertEqual(error as? HTTPClientError, .invalidResponse(statusCode: 503))
        }

        URLProtocolStub.requestHandler = { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                      url: url,
                      statusCode: 200,
                      httpVersion: nil,
                      headerFields: nil
                  ) else {
                throw URLProtocolStubError.missingURL
            }

            return (response, Data("not-json".utf8))
        }

        do {
            let _: HTTPFixturePayload = try await client.get(HTTPFixturePayload.self, from: endpoint)
            XCTFail("Expected a decoding error")
        } catch {
            XCTAssertEqual(error as? HTTPClientError, .decodingFailed)
        }
    }

    func testHolidayCNProviderUsesConfiguredYearEndpoint() async throws {
        URLProtocolStub.requestHandler = { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                      url: url,
                      statusCode: 200,
                      httpVersion: nil,
                      headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLProtocolStubError.missingURL
            }

            let body = Data(
                """
                {
                  "year": 2026,
                  "papers": [],
                  "days": [
                    {"name": "元旦", "date": "2026-01-01", "isOffDay": true},
                    {"name": "春节调休", "date": "2026-02-14", "isOffDay": false}
                  ]
                }
                """.utf8
            )
            return (response, body)
        }

        let baseURL = try XCTUnwrap(URL(string: "https://mirror.example.test/holiday"))
        let fetchedAt = Date(timeIntervalSince1970: 42)
        let provider = HolidayCNProvider(
            baseURL: baseURL,
            client: makeStubHTTPClient(),
            id: "holiday-cn-test",
            now: { fetchedAt }
        )

        let snapshot = try await provider.fetchYear(2026)

        XCTAssertEqual(URLProtocolStub.lastRequest?.url?.absoluteString, "https://mirror.example.test/holiday/2026.json")
        XCTAssertEqual(snapshot.providerID, "holiday-cn-test")
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
        XCTAssertEqual(snapshot.sourceURL?.absoluteString, "https://mirror.example.test/holiday/2026.json")
        XCTAssertEqual(snapshot.records.count, 2)
    }

    func testHolidayCNProviderRejectsMismatchedYear() async throws {
        URLProtocolStub.requestHandler = { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                      url: url,
                      statusCode: 200,
                      httpVersion: nil,
                      headerFields: nil
                  ) else {
                throw URLProtocolStubError.missingURL
            }

            let body = Data(
                """
                {
                  "year": 2025,
                  "papers": [],
                  "days": [
                    {"name": "元旦", "date": "2025-01-01", "isOffDay": true}
                  ]
                }
                """.utf8
            )
            return (response, body)
        }

        let provider = HolidayCNProvider(client: makeStubHTTPClient())

        do {
            _ = try await provider.fetchYear(2026)
            XCTFail("Expected a data validation error")
        } catch {
            XCTAssertEqual(error as? HolidayProviderError, .dataValidationFailed)
        }
    }

    func testHolidayCNProviderClassifiesNotPublishedAndRateLimited() async throws {
        let endpoint = try XCTUnwrap(URL(string: "https://example.test/2026.json"))
        let client = makeStubHTTPClient()
        let provider = HolidayCNProvider(baseURL: endpoint.deletingLastPathComponent(), client: client)

        for (statusCode, expectedError) in [
            (404, HolidayProviderError.notPublished),
            (429, HolidayProviderError.rateLimited),
            (403, HolidayProviderError.permissionDenied)
        ] {
            URLProtocolStub.requestHandler = { request in
                guard let url = request.url,
                      let response = HTTPURLResponse(
                          url: url,
                          statusCode: statusCode,
                          httpVersion: nil,
                          headerFields: nil
                      ) else {
                    throw URLProtocolStubError.missingURL
                }

                return (response, Data())
            }

            do {
                _ = try await provider.fetchYear(2026)
                XCTFail("Expected HTTP \(statusCode) to be classified")
            } catch {
                XCTAssertEqual(error as? HolidayProviderError, expectedError)
            }
        }
    }

    func testHolidayCNProviderRejectsInvalidYearBeforeNetworkRequest() async throws {
        URLProtocolStub.requestHandler = { _ in
            XCTFail("An invalid year must not issue a request")
            throw URLProtocolStubError.missingURL
        }

        let provider = HolidayCNProvider(client: makeStubHTTPClient())

        do {
            _ = try await provider.fetchYear(0)
            XCTFail("Expected an invalid year error")
        } catch {
            XCTAssertEqual(error as? HolidayProviderError, .invalidYear(0))
        }

        XCTAssertNil(URLProtocolStub.lastRequest)
    }

    func testHolidayRefreshPolicyUsesThreeYearWindowAndNextYearProbe() throws {
        let policy = HolidayRefreshPolicy.standard
        let beforeProbe = try makeShanghaiDate(year: 2026, month: 9, day: 30)
        let afterProbe = try makeShanghaiDate(year: 2026, month: 10, day: 1)

        XCTAssertEqual(
            policy.window(for: beforeProbe).years,
            [2025, 2026, 2027]
        )
        XCTAssertEqual(
            policy.cacheMaxAge(for: 2027, referenceDate: beforeProbe),
            7 * 24 * 60 * 60
        )
        XCTAssertEqual(
            policy.cacheMaxAge(for: 2027, referenceDate: afterProbe),
            24 * 60 * 60
        )

        let cachedAt = afterProbe.addingTimeInterval(-2 * 24 * 60 * 60)
        XCTAssertTrue(
            policy.shouldRefresh(
                year: 2027,
                cachedAt: cachedAt,
                referenceDate: afterProbe
            )
        )
    }

    @MainActor
    func testHolidayRepositoryRefreshWindowQueriesPreviousCurrentAndNextYear() async throws {
        let snapshots = try Dictionary(
            uniqueKeysWithValues: [2025, 2026, 2027].map { year in
                (year, try makeHolidaySnapshot(year: year))
            }
        )
        let container = try makeModelContainer()
        let context = ModelContext(container)
        let provider = MultiYearHolidayProvider(id: "multi-year", snapshots: snapshots)
        let repository = HolidayRepository(
            modelContext: context,
            primaryProvider: provider,
            now: { Date(timeIntervalSince1970: 2_000) }
        )
        let referenceDate = try makeShanghaiDate(year: 2026, month: 10, day: 1)

        let report = try await repository.refreshWindow(referenceDate: referenceDate)

        XCTAssertEqual(report.window.referenceYear, 2026)
        XCTAssertEqual(report.window.years, [2025, 2026, 2027])
        XCTAssertTrue(
            report.states.values.allSatisfy { state in
                if case .available = state {
                    return true
                }
                return false
            }
        )
        let requestedYears = await provider.requestedYearList()
        XCTAssertEqual(requestedYears, [2025, 2026, 2027])
    }

    @MainActor
    func testHolidayRepositoryClassifiesUnpublishedYear() async throws {
        let container = try makeModelContainer()
        let context = ModelContext(container)
        let primaryProvider = RecordingHolidayProvider(
            id: "primary",
            outcome: .failure(.notPublished)
        )
        let backupProvider = RecordingHolidayProvider(
            id: "backup",
            outcome: .failure(.notPublished)
        )
        let repository = HolidayRepository(
            modelContext: context,
            primaryProvider: primaryProvider,
            backupProvider: backupProvider,
            now: { Date(timeIntervalSince1970: 100) }
        )

        do {
            _ = try await repository.refresh(year: 2027)
            XCTFail("Expected an unpublished-year error")
        } catch {
            XCTAssertEqual(error as? HolidayRepositoryError, .notPublished(2027))
        }
    }

    func testAILCCHolidayProviderMapsBatchHolidayAndMakeupWorkday() async throws {
        URLProtocolStub.requestHandler = { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                      url: url,
                      statusCode: 200,
                      httpVersion: nil,
                      headerFields: nil
                  ) else {
                throw URLProtocolStubError.missingURL
            }

            let body: String
            if URLProtocolStub.requestCount == 1 {
                body = """
                {
                  "code": 0,
                  "holiday": {
                    "2026-01-01": {"holiday": true, "name": "元旦", "date": "2026-01-01"},
                    "2026-02-14": {"holiday": false, "name": "春节调休", "date": "2026-02-14"}
                  },
                  "type": {
                    "2026-01-01": {"type": 2, "name": "元旦", "week": 4},
                    "2026-02-14": {"type": 4, "name": "春节调休", "week": 7}
                  }
                }
                """
            } else {
                body = "{\"code\": 0, \"holiday\": {}, \"type\": {}}"
            }

            return (response, Data(body.utf8))
        }

        let baseURL = try XCTUnwrap(URL(string: "https://example.test/api/holiday"))
        let provider = AILCCHolidayProvider(
            baseURL: baseURL,
            client: makeStubHTTPClient(),
            now: { Date(timeIntervalSince1970: 300) }
        )

        let snapshot = try await provider.fetchYear(2026)

        XCTAssertEqual(URLProtocolStub.requestCount, 8)
        XCTAssertEqual(snapshot.providerID, "ailcc")
        XCTAssertEqual(snapshot.fetchedAt, Date(timeIntervalSince1970: 300))
        XCTAssertEqual(
            snapshot.records.map(\.dayID.description),
            ["2026-01-01", "2026-02-14"]
        )
        XCTAssertEqual(snapshot.records[0].workStatus, .holiday)
        XCTAssertEqual(snapshot.records[1].workStatus, .makeupWorkday)

        let requestURL = try XCTUnwrap(URLProtocolStub.lastRequest?.url)
        let components = try XCTUnwrap(
            URLComponents(url: requestURL, resolvingAgainstBaseURL: false)
        )
        XCTAssertEqual(components.path, "/api/holiday/batch")
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "type" })?.value,
            "Y"
        )
    }

    @MainActor
    func testHolidaySnapshotModelRoundTripsDomainSnapshot() throws {
        let snapshot = try makeHolidaySnapshot()
        let container = try makeModelContainer()
        let context = ModelContext(container)
        let cachedAt = Date(timeIntervalSince1970: 100)
        let model = HolidaySnapshotModel(snapshot: snapshot, cachedAt: cachedAt)

        context.insert(model)
        model.records.forEach { context.insert($0) }
        try context.save()

        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<HolidaySnapshotModel>()).first)
        let roundTripped = try stored.makeDomainSnapshot()

        XCTAssertEqual(roundTripped, snapshot)
        XCTAssertEqual(stored.cachedAt, cachedAt)
        XCTAssertEqual(stored.providerID, "fixture")
        XCTAssertEqual(stored.records.count, 2)
    }

    @MainActor
    func testHolidayRepositoryReturnsFreshCacheWithoutCallingProvider() async throws {
        let snapshot = try makeHolidaySnapshot()
        let container = try makeModelContainer()
        let context = ModelContext(container)
        let seedProvider = RecordingHolidayProvider(
            id: "seed",
            outcome: .success(snapshot)
        )
        let seedRepository = HolidayRepository(
            modelContext: context,
            primaryProvider: seedProvider,
            now: { Date(timeIntervalSince1970: 100) }
        )
        _ = try await seedRepository.refresh(year: 2026)

        let unavailableProvider = RecordingHolidayProvider(
            id: "unavailable",
            outcome: .failure(.networkUnavailable)
        )
        let repository = HolidayRepository(
            modelContext: context,
            primaryProvider: unavailableProvider,
            cacheMaxAge: 60,
            now: { Date(timeIntervalSince1970: 100) }
        )

        let cached = try await repository.snapshot(for: 2026)

        XCTAssertEqual(cached, snapshot)
        let unavailableRequests = await unavailableProvider.requestedYearList()
        XCTAssertEqual(unavailableRequests, [])
    }

    @MainActor
    func testHolidayRepositoryFallsBackToBackupProvider() async throws {
        let snapshot = try makeHolidaySnapshot(providerID: "backup")
        let container = try makeModelContainer()
        let context = ModelContext(container)
        let primaryProvider = RecordingHolidayProvider(
            id: "primary",
            outcome: .failure(.networkUnavailable)
        )
        let backupProvider = RecordingHolidayProvider(
            id: "backup",
            outcome: .success(snapshot)
        )
        let repository = HolidayRepository(
            modelContext: context,
            primaryProvider: primaryProvider,
            backupProvider: backupProvider,
            now: { Date(timeIntervalSince1970: 200) }
        )

        let fetched = try await repository.refresh(year: 2026)

        XCTAssertEqual(fetched.providerID, "backup")
        let primaryRequests = await primaryProvider.requestedYearList()
        let backupRequests = await backupProvider.requestedYearList()
        XCTAssertEqual(primaryRequests, [2026])
        XCTAssertEqual(backupRequests, [2026])
        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<HolidaySnapshotModel>()).first)
        XCTAssertEqual(stored.providerID, "backup")
    }

    @MainActor
    func testHolidayRepositoryKeepsStaleCacheWhenProvidersFail() async throws {
        let snapshot = try makeHolidaySnapshot()
        let container = try makeModelContainer()
        let context = ModelContext(container)
        let seedProvider = RecordingHolidayProvider(
            id: "seed",
            outcome: .success(snapshot)
        )
        let seedRepository = HolidayRepository(
            modelContext: context,
            primaryProvider: seedProvider,
            now: { Date(timeIntervalSince1970: 0) }
        )
        _ = try await seedRepository.refresh(year: 2026)

        let primaryProvider = RecordingHolidayProvider(
            id: "primary",
            outcome: .failure(.networkUnavailable)
        )
        let backupProvider = RecordingHolidayProvider(
            id: "backup",
            outcome: .failure(.notPublished)
        )
        let repository = HolidayRepository(
            modelContext: context,
            primaryProvider: primaryProvider,
            backupProvider: backupProvider,
            cacheMaxAge: 1,
            now: { Date(timeIntervalSince1970: 100) }
        )

        let cached = try await repository.snapshot(for: 2026)

        XCTAssertEqual(cached, snapshot)
        let primaryRequests = await primaryProvider.requestedYearList()
        let backupRequests = await backupProvider.requestedYearList()
        XCTAssertEqual(primaryRequests, [2026])
        XCTAssertEqual(backupRequests, [2026])
    }

    @MainActor
    func testHolidayRepositoryReportsProviderFailuresWithoutCache() async throws {
        let container = try makeModelContainer()
        let context = ModelContext(container)
        let primaryProvider = RecordingHolidayProvider(
            id: "primary",
            outcome: .failure(.networkUnavailable)
        )
        let backupProvider = RecordingHolidayProvider(
            id: "backup",
            outcome: .failure(.notPublished)
        )
        let repository = HolidayRepository(
            modelContext: context,
            primaryProvider: primaryProvider,
            backupProvider: backupProvider,
            now: { Date(timeIntervalSince1970: 100) }
        )

        do {
            _ = try await repository.refresh(year: 2026)
            XCTFail("Expected provider failures when no cache exists")
        } catch {
            XCTAssertEqual(
                error as? HolidayRepositoryError,
                .providersUnavailable(
                    primary: .networkUnavailable,
                    backup: .notPublished
                )
            )
        }
    }

    private func makeStubHTTPClient() -> HTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        return HTTPClient(session: session, timeoutInterval: 5)
    }

    private func makeHolidaySnapshot(
        year: Int = 2026,
        providerID: String = "fixture"
    ) throws -> HolidayYearSnapshot {
        let newYear = try XCTUnwrap(DayID(year: year, month: 1, day: 1))
        let makeupWorkday = try XCTUnwrap(DayID(year: year, month: 2, day: 14))

        return try HolidayYearSnapshot(
            year: year,
            providerID: providerID,
            fetchedAt: Date(timeIntervalSince1970: 50),
            sourceURL: URL(string: "https://example.test/2026.json"),
            records: [
                HolidayRecord(dayID: newYear, name: "元旦", kind: .holiday),
                HolidayRecord(dayID: makeupWorkday, name: "春节调休", kind: .makeupWorkday)
            ]
        )
    }

    private func makeShanghaiDate(year: Int, month: Int, day: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DayID.defaultTimeZone
        return try XCTUnwrap(
            calendar.date(from: DateComponents(year: year, month: month, day: day))
        )
    }

    @MainActor
    private func makeModelContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: AppPreferenceModel.self,
            HolidaySnapshotModel.self,
            CachedHolidayRecordModel.self,
            VacationPeriodModel.self,
            SpecialDayModel.self,
            LocalScheduleItemModel.self,
            DateKnowledgeSnapshotModel.self,
            configurations: configuration
        )
    }
}
