import XCTest

final class CalendarAppUITests: XCTestCase {
    @MainActor
    func testPrimaryTabsAreVisible() {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars
        XCTAssertTrue(tabBar.buttons["日历"].waitForExistence(timeout: 3))
        XCTAssertTrue(tabBar.buttons["假期"].exists)
        XCTAssertTrue(tabBar.buttons["设置"].exists)
    }

    @MainActor
    func testSettingsShowsSystemCalendarAccessState() {
        let app = XCUIApplication()
        app.launch()

        let settingsTab = app.tabBars.buttons["设置"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10))
        settingsTab.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["settings.systemCalendar"].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testSettingsAllowsNotificationAuthorizationInFixture() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-fixture"]
        app.launch()

        let settingsTab = app.tabBars.buttons["设置"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10))
        settingsTab.tap()

        let status = app.descendants(matching: .any)["settings.notifications.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("尚未请求"))

        let requestButton = app.buttons["settings.notifications.request"]
        XCTAssertTrue(requestButton.waitForExistence(timeout: 5))
        requestButton.tap()

        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("通知已允许"))
    }

    @MainActor
    func testSettingsReconcilesFixtureNotificationPlan() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-fixture"]
        app.launch()

        let settingsTab = app.tabBars.buttons["设置"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10))
        settingsTab.tap()

        let requestButton = app.buttons["settings.notifications.request"]
        XCTAssertTrue(requestButton.waitForExistence(timeout: 5))
        requestButton.tap()

        let scheduleToggle = app.switches["settings.notifications.kind.schedule"]
        XCTAssertTrue(scheduleToggle.waitForExistence(timeout: 5))
        scheduleToggle.tap()

        // The notification rules are rendered in a lazy Form section. Scroll
        // the section into the accessibility hierarchy before querying its
        // action button so this test does not depend on the initial viewport.
        app.swipeUp()
        let reconcileButton = app.buttons["settings.notifications.reconcile"]
        XCTAssertTrue(reconcileButton.waitForExistence(timeout: 5))
        reconcileButton.tap()

        let summary = app.descendants(matching: .any)["settings.notifications.planSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertTrue(summary.label.contains("条待发送提醒"))
    }

    @MainActor
    func testSettingsAllowsSelectingSystemCalendarSources() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-system-calendar"]
        app.launch()

        let settingsTab = app.tabBars.buttons["设置"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10))
        settingsTab.tap()

        let sourceSummary = app.descendants(matching: .any)["settings.systemCalendar.selectionSummary"]
        XCTAssertTrue(sourceSummary.waitForExistence(timeout: 5))
        XCTAssertTrue(sourceSummary.label.contains("2"))

        let workCalendar = app.descendants(matching: .any)["settings.systemCalendar.calendar.fixture-work"]
        XCTAssertTrue(workCalendar.waitForExistence(timeout: 5))

        workCalendar.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let updatedSummary = app.descendants(matching: .any)["settings.systemCalendar.selectionSummary"]
        XCTAssertTrue(updatedSummary.waitForExistence(timeout: 3))
        XCTAssertTrue(updatedSummary.label.contains("已选择 1 个日历来源"))
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.systemCalendar.selectAll"].waitForExistence(timeout: 3)
        )
    }

    @MainActor
    func testVacationTabShowsPersonalDateList() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-fixture"]
        app.launch()

        app.tabBars.buttons["假期"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["screen.vacation"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["vacation.year"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["vacation.overview"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "vacation.period."))
                .firstMatch
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "vacation.special."))
                .firstMatch
                .waitForExistence(timeout: 3)
        )
    }

    @MainActor
    func testVacationAddOpensEditorAndSavesPeriod() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-fixture"]
        app.launch()

        app.tabBars.buttons["假期"].tap()
        let addButton = app.buttons["vacation.add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 3))
        addButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["添加假期区间"].waitForExistence(timeout: 3)
        )
        app.buttons["添加假期区间"].tap()

        let editor = app.descendants(matching: .any)["vacation.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        let titleField = app.textFields["vacation.editor.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.tap()
        titleField.typeText("测试假期")
        app.buttons["vacation.editor.save"].tap()

        XCTAssertTrue(app.staticTexts["测试假期"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testCalendarAddScheduleOpensEditorAndShowsDetailTimeline() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-fixture"]
        app.launch()

        let addButton = app.buttons["calendar.addSchedule"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10))
        addButton.tap()

        let editor = app.descendants(matching: .any)["schedule.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        let titleField = app.textFields["schedule.editor.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.tap()
        titleField.typeText("测试日程")
        app.buttons["schedule.editor.save"].tap()

        let todayCell = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "calendar.day.", "今天")
        ).firstMatch
        XCTAssertTrue(todayCell.waitForExistence(timeout: 10))
        todayCell.tap()
        todayCell.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["day.detail.schedules"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["测试日程"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testScheduleSearchFiltersFixtureByTitle() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-fixture"]
        app.launch()

        let searchButton = app.buttons["calendar.scheduleSearch"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 10))
        searchButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["screen.scheduleList"].waitForExistence(timeout: 5)
        )

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("项目评审")

        XCTAssertTrue(app.staticTexts["项目评审"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["晚间阅读"].exists)
    }

    @MainActor
    func testCalendarMonthGridControlsAreVisibleAndNavigable() {
        let app = XCUIApplication()
        app.launch()

        let monthTitle = app.descendants(matching: .any)["calendar.month.title"]
        XCTAssertTrue(monthTitle.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["calendar.month.previous"].exists)
        XCTAssertTrue(app.buttons["calendar.month.next"].exists)
        XCTAssertTrue(app.buttons["calendar.today"].exists)

        app.buttons["calendar.month.next"].tap()
        XCTAssertTrue(monthTitle.waitForExistence(timeout: 3))
        app.buttons["calendar.today"].tap()
    }

    @MainActor
    func testCalendarYearOverviewOpensAndReturnsToSelectedMonth() {
        let app = XCUIApplication()
        app.launch()

        let monthTitle = app.descendants(matching: .any)["calendar.month.title"]
        XCTAssertTrue(monthTitle.waitForExistence(timeout: 10))
        monthTitle.tap()

        let yearTitle = app.buttons["calendar.year.title"]
        XCTAssertTrue(yearTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["calendar.year.month.2026-08"].exists)

        app.buttons["calendar.year.month.2026-08"].tap()
        XCTAssertTrue(monthTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["calendar.month.next"].exists)
    }

    @MainActor
    func testCalendarSingleTapShowsSelectionSummaryBeforeDetailNavigation() {
        let app = XCUIApplication()
        app.launch()

        let dayCell = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "calendar.day.")
        ).firstMatch
        XCTAssertTrue(dayCell.waitForExistence(timeout: 10))
        dayCell.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["calendar.selectedDaySummary"].waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.descendants(matching: .any)["screen.dayDetail"].exists)
    }

    @MainActor
    func testCalendarHomeShowsOverviewAndUpcomingSections() {
        let app = XCUIApplication()
        app.launch()

        let monthTitle = app.descendants(matching: .any)["calendar.month.title"]
        XCTAssertTrue(monthTitle.waitForExistence(timeout: 10))
        app.swipeUp()

        XCTAssertTrue(
            app.descendants(matching: .any)["calendar.monthOverview"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["calendar.upcoming"].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testCalendarDateOpensDetailScreen() {
        let app = XCUIApplication()
        app.launch()

        let monthTitle = app.descendants(matching: .any)["calendar.month.title"]
        XCTAssertTrue(monthTitle.waitForExistence(timeout: 10))

        let dayCell = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "calendar.day.")
        ).firstMatch
        XCTAssertTrue(dayCell.waitForExistence(timeout: 10))

        dayCell.tap()
        dayCell.tap()

        let detailScreen = app.descendants(matching: .any)["screen.dayDetail"]
        XCTAssertTrue(detailScreen.waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.descendants(matching: .any)["day.detail.date"].waitForExistence(timeout: 3)
        )
        let status = app.descendants(matching: .any)["day.detail.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        XCTAssertFalse(status.label.isEmpty)
        XCTAssertTrue(
            app.descendants(matching: .any)["day.detail.systemCalendar"].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testDayDetailCreatesSystemCalendarEventFromExplicitEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-fixture", "-ui-testing-system-calendar"]
        app.launch()

        let monthTitle = app.descendants(matching: .any)["calendar.month.title"]
        XCTAssertTrue(monthTitle.waitForExistence(timeout: 10))

        let dayCell = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "calendar.day.")
        ).firstMatch
        XCTAssertTrue(dayCell.waitForExistence(timeout: 10))
        dayCell.tap()
        dayCell.tap()

        let addButton = app.buttons["day.detail.systemCalendar.add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let editor = app.descendants(matching: .any)["system.calendar.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let titleField = app.textFields["system.calendar.editor.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("测试系统事件")
        app.buttons["system.calendar.editor.save"].tap()

        XCTAssertTrue(app.staticTexts["测试系统事件"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCalendarDateAccessibilityLabelContainsDateAndStatus() {
        let app = XCUIApplication()
        app.launch()

        let monthTitle = app.descendants(matching: .any)["calendar.month.title"]
        XCTAssertTrue(monthTitle.waitForExistence(timeout: 10))

        let dayCell = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "calendar.day.")
        ).firstMatch
        XCTAssertTrue(dayCell.waitForExistence(timeout: 10))
        XCTAssertTrue(dayCell.label.contains("年"))
        XCTAssertTrue(dayCell.label.contains("日"))
        XCTAssertTrue(
            ["工作日", "周末", "休息日", "补班", "状态待确认"].contains {
                dayCell.label.contains($0)
            }
        )
    }

    @MainActor
    func testCalendarScrollKeepsMonthControlsAvailable() {
        let app = XCUIApplication()
        app.launch()

        let monthTitle = app.descendants(matching: .any)["calendar.month.title"]
        XCTAssertTrue(monthTitle.waitForExistence(timeout: 3))

        app.swipeUp()
        app.swipeDown()

        XCTAssertTrue(monthTitle.exists)
        XCTAssertTrue(app.buttons["calendar.today"].exists)
    }
}
