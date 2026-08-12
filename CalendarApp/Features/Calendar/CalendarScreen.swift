import SwiftUI

@MainActor
struct CalendarScreen: View {
    @Environment(Theme.self) private var theme
    @Environment(AppRouter.self) private var router

    @State private var model: CalendarFeatureModel
    @State private var isScheduleListPresented = false
    @State private var scheduleEditorItem: ScheduleEditorItem?
    @State private var pendingScheduleDeletion: ScheduleItem?
    @State private var scheduleOperationError: String?
    @State private var isYearViewPresented = false

    init(
        repository: (any HolidayRepositoryProtocol)? = nil,
        vacationRepository: (any VacationRepositoryProtocol)? = nil,
        scheduleRepository: (any ScheduleRepositoryProtocol)? = nil,
        dateKnowledgeRepository: (any DateKnowledgeRepositoryProtocol)? = nil,
        initialDate: Date = .now
    ) {
        _model = State(
            initialValue: CalendarFeatureModel(
                repository: repository,
                vacationRepository: vacationRepository,
                scheduleRepository: scheduleRepository,
                dateKnowledgeRepository: dateKnowledgeRepository,
                initialDate: initialDate
            )
        )
    }

    var body: some View {
        Group {
            if isYearViewPresented {
                yearOverview
            } else {
                monthContent
            }
        }
        .background(theme.backgroundPrimary)
        .safeAreaPadding(.bottom, 88)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: model.displayedMonth.id) {
            await model.load()
        }
        .sheet(item: $scheduleEditorItem) { item in
            ScheduleEditorSheet(
                item: item,
                onSave: saveSchedule,
                onDelete: item.isEditing ? {
                    if case let .existing(schedule) = item {
                        pendingScheduleDeletion = schedule
                    }
                } : nil
            )
        }
        .sheet(isPresented: $isScheduleListPresented) {
            ScheduleListScreen(
                repository: model.scheduleRepository,
                initialDate: model.displayedMonth.firstDay.date ?? .now
            )
        }
        .confirmationDialog(
            "删除本地日程",
            isPresented: Binding(
                get: { pendingScheduleDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingScheduleDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                confirmScheduleDelete()
            }
            Button("取消", role: .cancel) {
                pendingScheduleDeletion = nil
            }
        } message: {
            Text(pendingScheduleDeletion.map { "确定删除“\($0.title)”吗？" } ?? "此操作无法撤销")
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { scheduleOperationError != nil },
                set: { isPresented in
                    if !isPresented {
                        scheduleOperationError = nil
                    }
                }
            )
        ) {
            Button("知道了", role: .cancel) {
                scheduleOperationError = nil
            }
        } message: {
            Text(scheduleOperationError ?? "本地日程暂不可用")
        }
        .accessibilityIdentifier("screen.calendar")
    }

    private var monthContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                calendarNavigationBar
                WeekdayHeader(theme: theme)
                monthGrid
                selectedDaySummary
                monthOverviewCard
                upcomingDatesSection
                statusMessage
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .refreshable {
            await model.load()
        }
    }

    private var calendarNavigationBar: some View {
        HStack(spacing: 8) {
            navigationArrow(
                systemImage: "chevron.left",
                label: "上个月",
                identifier: "calendar.month.previous"
            ) {
                model.moveMonth(by: -1)
            }

            HStack(spacing: 0) {
                Button {
                    isScheduleListPresented = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("搜索本地日程")
                .accessibilityIdentifier("calendar.scheduleSearch")

                Button {
                    isYearViewPresented = true
                } label: {
                    VStack(spacing: 1) {
                        Text(verbatim: contextTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(verbatim: model.displayedMonth.title)
                            .font(.caption2)
                            .foregroundStyle(theme.labelSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .foregroundStyle(theme.labelPrimary)
                .accessibilityLabel("打开 \(model.displayedMonth.year) 年月视图")
                .accessibilityValue(model.displayedMonth.title)
                .accessibilityIdentifier("calendar.month.title")

                Button {
                    scheduleEditorItem = .new
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("添加日程")
                .accessibilityIdentifier("calendar.addSchedule")
            }
            .frame(maxWidth: .infinity)
            .background(theme.surfaceElevated, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(theme.separatorSubtle.opacity(0.55), lineWidth: 0.75)
            }

            navigationArrow(
                systemImage: "chevron.right",
                label: "下个月",
                identifier: "calendar.month.next"
            ) {
                model.moveMonth(by: 1)
            }
        }
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) {
            if model.selectedDayID != model.today {
                Button("今天") {
                    model.goToToday()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.tint)
                .accessibilityLabel("回到今天")
                .accessibilityIdentifier("calendar.today")
                .offset(y: 22)
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("calendar.today")
            }
        }
        .padding(.bottom, model.selectedDayID == model.today ? 0 : 14)
    }

    private func navigationArrow(
        systemImage: String,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 40, height: 40)
                .background(theme.surfaceElevated, in: Circle())
        }
        .foregroundStyle(theme.labelPrimary)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private var contextTitle: String {
        guard let selectedDayID = model.selectedDayID else {
            let isCurrentMonth = model.displayedMonth.year == model.today.year
                && model.displayedMonth.month == model.today.month
            return isCurrentMonth ? "今天" : "\(model.displayedMonth.month)月"
        }
        if selectedDayID == model.today {
            return "今天"
        }
        return "\(selectedDayID.month)月\(selectedDayID.day)日"
    }

    private var yearOverview: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 12) {
                    Button {
                        model.moveYear(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 40, height: 40)
                    }
                    .foregroundStyle(theme.labelPrimary)
                    .accessibilityLabel("上一年")
                    .accessibilityIdentifier("calendar.year.previous")

                    Button {
                        isYearViewPresented = false
                    } label: {
                        VStack(spacing: 2) {
                            Text(verbatim: "\(model.displayedMonth.year)年")
                                .font(.title3.weight(.semibold))
                            Text("点击月份返回月视图")
                                .font(.caption)
                                .foregroundStyle(theme.labelSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .foregroundStyle(theme.labelPrimary)
                    .accessibilityLabel("返回月视图")
                    .accessibilityIdentifier("calendar.year.title")

                    Button {
                        model.moveYear(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 40, height: 40)
                    }
                    .foregroundStyle(theme.labelPrimary)
                    .accessibilityLabel("下一年")
                    .accessibilityIdentifier("calendar.year.next")
                }
                .padding(.horizontal, 4)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                    spacing: 14
                ) {
                    ForEach(1...12, id: \.self) { monthNumber in
                        if let month = CalendarMonth(
                            year: model.displayedMonth.year,
                            month: monthNumber
                        ) {
                            YearMiniMonthCard(
                                month: month,
                                isSelected: month == model.displayedMonth,
                                today: model.today,
                                model: model,
                                theme: theme
                            ) {
                                model.jump(to: month)
                                isYearViewPresented = false
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height),
                          abs(value.translation.width) > 70 else {
                        return
                    }
                    model.moveYear(by: value.translation.width < 0 ? 1 : -1)
                }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onEnded { scale in
                    if scale > 1.08 {
                        isYearViewPresented = false
                    }
                }
        )
        .accessibilityIdentifier("calendar.yearOverview")
    }

    private func saveSchedule(_ schedule: ScheduleItem) -> String? {
        guard let scheduleRepository = model.scheduleRepository else {
            return "本地日程服务尚未准备好"
        }

        do {
            try scheduleRepository.save(schedule)
            Task { await model.load() }
            return nil
        } catch let error as LocalizedError {
            return error.errorDescription ?? "本地日程暂不可用"
        } catch {
            return "本地日程暂不可用"
        }
    }

    private func confirmScheduleDelete() {
        guard let schedule = pendingScheduleDeletion,
              let scheduleRepository = model.scheduleRepository else {
            pendingScheduleDeletion = nil
            return
        }
        pendingScheduleDeletion = nil

        do {
            try scheduleRepository.delete(id: schedule.id)
            Task { await model.load() }
        } catch let error as LocalizedError {
            scheduleOperationError = error.errorDescription ?? "本地日程暂不可用"
        } catch {
            scheduleOperationError = "本地日程暂不可用"
        }
    }

    private var monthHeader: some View {
        HStack {
            Text(model.displayedMonth.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(theme.labelPrimary)
                .accessibilityIdentifier("calendar.month.title")
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 12)

            if model.selectedDayID == model.today {
                Text("今天")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.tint)
            }
        }
        .frame(minHeight: 36)
    }

    private var monthGrid: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 4),
            count: 7
        )

        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(model.grid.days) { day in
                CalendarDayCell(
                    day: day,
                    presentation: model.presentation(for: day.dayID),
                    isToday: model.isToday(day.dayID),
                    isSelected: model.selectedDayID == day.dayID,
                    theme: theme
                ) {
                    if model.select(dayID: day.dayID) {
                        router.navigate(to: .dayDetail(dayID: day.dayID))
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height),
                          abs(value.translation.width) > 70 else {
                        return
                    }
                    model.moveMonth(by: value.translation.width < 0 ? 1 : -1)
                }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onEnded { scale in
                    if scale < 0.86 {
                        isYearViewPresented = true
                    }
                }
        )
    }

    @ViewBuilder
    private var selectedDaySummary: some View {
        if let selectedDayID = model.selectedDayID {
            let presentation = model.presentation(for: selectedDayID)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedDayID == model.today ? "今天" : "已选日期")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.tint)
                        Text(verbatim: "\(selectedDayID.year)年\(selectedDayID.month)月\(selectedDayID.day)日")
                            .font(.headline)
                            .foregroundStyle(theme.labelPrimary)
                    }

                    Spacer(minLength: 8)

                    Button("查看详情") {
                        router.navigate(to: .dayDetail(dayID: selectedDayID))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.tint)
                }

                HStack(spacing: 8) {
                    summaryPill(
                        title: presentation.workStatus.displayName,
                        color: workStatusColor(presentation.workStatus)
                    )

                    if let annotation = presentation.primaryAnnotation {
                        summaryPill(
                            title: annotation.title,
                            color: annotationColor(annotation.kind)
                        )
                    }

                    ForEach(presentation.vacationLabels, id: \.self) { label in
                        summaryPill(title: label, color: theme.statusVacation)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if presentation.annotationCandidates.count > 1 {
                    Text("还有 \(presentation.annotationCandidates.count - 1) 个日期标注可在详情中查看")
                        .font(.caption)
                        .foregroundStyle(theme.labelSecondary)
                } else if !presentation.specialDayLabels.isEmpty {
                    Text(presentation.specialDayLabels.joined(separator: "、"))
                        .font(.caption)
                        .foregroundStyle(theme.labelSecondary)
                } else if presentation.scheduleCount > 0 {
                    Text("本地日程 \(presentation.scheduleCount) 项")
                        .font(.caption)
                        .foregroundStyle(theme.labelSecondary)
                }
            }
            .padding(16)
            .background(theme.surfaceTinted, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(theme.separatorSubtle.opacity(0.45), lineWidth: 0.75)
            }
            .accessibilityIdentifier("calendar.selectedDaySummary")
        }
    }

    private func summaryPill(title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
            .lineLimit(1)
    }

    private func workStatusColor(_ status: WorkStatus) -> Color {
        switch status {
        case .holiday: theme.statusHoliday
        case .makeupWorkday: theme.statusMakeupWorkday
        case .unknown: theme.statusUnknown
        case .weekend, .workday: theme.labelSecondary
        }
    }

    private func annotationColor(_ kind: DayAnnotationKind) -> Color {
        switch kind {
        case .makeupWorkday: theme.statusMakeupWorkday
        case .publicHoliday: theme.statusHoliday
        case .solarTerm: theme.annotationSolarTerm
        case .importantTraditionalFestival, .observance: theme.annotationFestival
        }
    }

    private var monthOverviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("本月概览", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                    .foregroundStyle(theme.labelPrimary)

                Spacer(minLength: 8)

                Text("\(model.monthOverview.month.month)月")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.labelSecondary)
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                MonthOverviewMetric(
                    title: "休息日",
                    value: model.monthOverview.restDayCount,
                    systemImage: "moon.zzz.fill",
                    color: theme.statusHoliday,
                    theme: theme
                )
                MonthOverviewMetric(
                    title: "调休补班",
                    value: model.monthOverview.makeupWorkdayCount,
                    systemImage: "arrow.triangle.2.circlepath",
                    color: theme.statusMakeupWorkday,
                    theme: theme
                )
                MonthOverviewMetric(
                    title: "个人假期",
                    value: model.monthOverview.vacationDayCount,
                    systemImage: "figure.walk",
                    color: theme.statusVacation,
                    theme: theme
                )
                MonthOverviewMetric(
                    title: "本地日程",
                    value: model.monthOverview.scheduleCount,
                    systemImage: "calendar.badge.clock",
                    color: theme.tint,
                    theme: theme
                )
            }
        }
        .padding(16)
        .background(theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.separatorSubtle.opacity(0.55), lineWidth: 0.75)
        }
        .accessibilityIdentifier("calendar.monthOverview")
    }

    @ViewBuilder
    private var upcomingDatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("近期日期", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                    .foregroundStyle(theme.labelPrimary)

                Spacer(minLength: 8)

                Text("接下来")
                    .font(.caption)
                    .foregroundStyle(theme.labelSecondary)
            }

            if model.upcomingDates.isEmpty {
                Label("当前月份暂时没有可展示的日期摘要", systemImage: "calendar.badge.exclamationmark")
                    .font(.subheadline)
                    .foregroundStyle(theme.labelSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(model.upcomingDates) { summary in
                    Button {
                        model.selectedDayID = summary.dayID
                        router.navigate(to: .dayDetail(dayID: summary.dayID))
                    } label: {
                        UpcomingDateRow(summary: summary, theme: theme)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(theme.surfaceTinted)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.separatorSubtle.opacity(0.45), lineWidth: 0.75)
        }
        .accessibilityIdentifier("calendar.upcoming")
    }

    @ViewBuilder
    private var statusMessage: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch model.dataState {
            case .loading where model.presentations.isEmpty:
                Label("正在读取节假日数据", systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote)
                    .foregroundStyle(theme.labelSecondary)
                    .accessibilityIdentifier("calendar.status.loading")
            case .refreshing:
                Label("正在刷新节假日数据，当前内容仍可使用", systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote)
                    .foregroundStyle(theme.labelSecondary)
                    .accessibilityIdentifier("calendar.status.refreshing")
            case .refreshFailed:
                Label(
                    model.errorMessage ?? "刷新失败，继续显示上次有效数据",
                    systemImage: "exclamationmark.triangle"
                )
                    .font(.footnote)
                    .foregroundStyle(theme.statusUnknown)
                    .accessibilityIdentifier("calendar.status.refreshFailed")
            case .notPublished:
                Label("官方节假日安排尚未发布", systemImage: "questionmark.circle")
                    .font(.footnote)
                    .foregroundStyle(theme.statusUnknown)
                    .accessibilityIdentifier("calendar.status.notPublished")
            case .unavailable:
                Label("节假日数据暂不可用，日期状态待确认", systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundStyle(theme.statusUnknown)
                    .accessibilityIdentifier("calendar.status.unavailable")
            default:
                EmptyView()
            }

            if let dateKnowledgeText = model.dateKnowledgeState.displayText {
                Label(
                    dateKnowledgeText,
                    systemImage: model.dateKnowledgeState == .loading
                        ? "arrow.triangle.2.circlepath"
                        : "info.circle"
                )
                    .font(.footnote)
                    .foregroundStyle(
                        model.dateKnowledgeState == .unavailable
                            ? theme.statusUnknown
                            : theme.labelSecondary
                    )
                    .accessibilityIdentifier("calendar.status.dateKnowledge")
            }
        }
    }
}

@MainActor
private struct YearMiniMonthCard: View {
    let month: CalendarMonth
    let isSelected: Bool
    let today: DayID
    let model: CalendarFeatureModel
    let theme: Theme
    let action: () -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 1),
        count: 7
    )

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(month.title)
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 0)
                    if isSelected {
                        Circle()
                            .fill(theme.tint)
                            .frame(width: 6, height: 6)
                    }
                }
                .foregroundStyle(theme.labelPrimary)

                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(CalendarMonthGrid(month: month).days) { day in
                        let annotation = model.presentations[day.dayID]?.primaryAnnotation
                        Text(verbatim: "\(day.dayID.day)")
                            .font(.system(size: 9, weight: day.dayID == today ? .bold : .regular))
                            .foregroundStyle(day.isInDisplayedMonth ? theme.labelPrimary : theme.labelSecondary)
                            .frame(maxWidth: .infinity, minHeight: 13)
                            .background(
                                day.dayID == today
                                    ? theme.tint.opacity(0.16)
                                    : .clear,
                                in: Circle()
                            )
                            .overlay(alignment: .bottom) {
                                if annotation != nil {
                                    Circle()
                                        .fill(theme.annotationSolarTerm)
                                        .frame(width: 2.5, height: 2.5)
                                        .offset(y: 2)
                                }
                            }
                            .opacity(day.isInDisplayedMonth ? 1 : 0.24)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? theme.surfaceTinted : theme.surfaceElevated,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? theme.tint : theme.separatorSubtle.opacity(0.45),
                        lineWidth: isSelected ? 1.25 : 0.75
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(month.title)，点击查看月视图")
        .accessibilityIdentifier("calendar.year.month.\(month.id)")
    }
}

@MainActor
private struct MonthOverviewMetric: View {
    let title: String
    let value: Int
    let systemImage: String
    let color: Color
    let theme: Theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(theme.labelSecondary)
                Text(verbatim: "\(value)")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.labelPrimary)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(value)")
    }
}

@MainActor
private struct UpcomingDateRow: View {
    let summary: UpcomingDateSummary
    let theme: Theme

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(verbatim: "\(summary.dayID.month)月")
                    .font(.caption2.weight(.semibold))
                Text(verbatim: "\(summary.dayID.day)")
                    .font(.title3.weight(.semibold))
            }
            .foregroundStyle(theme.labelPrimary)
            .frame(width: 42)

            Capsule()
                .fill(indicatorColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(summary.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.labelPrimary)
                    .lineLimit(1)

                if let subtitle = summary.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(theme.labelSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if summary.scheduleCount > 0 {
                Image(systemName: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(theme.tint)
                    .accessibilityLabel("包含本地日程")
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.labelSecondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.dayID.year)年\(summary.dayID.month)月\(summary.dayID.day)日，\(summary.title)")
    }

    private var indicatorColor: Color {
        switch summary.kind {
        case .makeupWorkday:
            theme.statusMakeupWorkday
        case .publicHoliday:
            theme.statusHoliday
        case .solarTerm:
            theme.annotationSolarTerm
        case .importantTraditionalFestival, .observance:
            theme.annotationFestival
        case nil:
            theme.tint
        }
    }
}

@MainActor
private struct WeekdayHeader: View {
    let theme: Theme

    private let labels = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.labelSecondary)
                    .frame(maxWidth: .infinity, minHeight: 24)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("星期一至星期日")
    }
}

@MainActor
private struct CalendarDayCell: View {
    let day: CalendarMonthDay
    let presentation: DayPresentation
    let isToday: Bool
    let isSelected: Bool
    let theme: Theme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(day.dayID.day)")
                    .font(.body.weight(isToday ? .bold : .regular))
                    .foregroundStyle(numberColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)

                if let annotation = presentation.primaryAnnotation {
                    Text(annotation.title)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(annotationColor(annotation.kind))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity, minHeight: 14)
                } else {
                    Color.clear.frame(height: 14)
                }

                HStack(spacing: 4) {
                    if let badge = statusBadge {
                        Text(badge.label)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(badge.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }

                    if presentation.scheduleCount > 0 {
                        Text("\(min(presentation.scheduleCount, 9))")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(theme.tint)
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: 14)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? theme.backgroundSecondary : .clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isToday || isSelected ? theme.tint : .clear,
                        lineWidth: isToday || isSelected ? 1.5 : 0
                    )
            }
        }
        .buttonStyle(.plain)
        .opacity(day.isInDisplayedMonth ? 1 : 0.35)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("第一次点击选中日期，再次点击打开详情")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("calendar.day.\(day.dayID.description)")
    }

    private var numberColor: Color {
        switch presentation.workStatus {
        case .holiday:
            theme.statusHoliday
        case .makeupWorkday:
            theme.statusMakeupWorkday
        case .unknown:
            theme.statusUnknown
        case .weekend:
            theme.labelSecondary
        case .workday:
            theme.labelPrimary
        }
    }

    private var statusBadge: (label: String, color: Color)? {
        switch presentation.workStatus {
        case .holiday:
            ("休", theme.statusHoliday)
        case .makeupWorkday:
            ("班", theme.statusMakeupWorkday)
        case .unknown:
            ("待", theme.statusUnknown)
        case .workday, .weekend:
            nil
        }
    }

    private func annotationColor(_ kind: DayAnnotationKind) -> Color {
        switch kind {
        case .makeupWorkday:
            theme.statusMakeupWorkday
        case .publicHoliday:
            theme.statusHoliday
        case .solarTerm:
            theme.annotationSolarTerm
        case .importantTraditionalFestival, .observance:
            theme.annotationFestival
        }
    }

    private var accessibilityText: String {
        var parts = [
            "\(day.dayID.year)年\(day.dayID.month)月\(day.dayID.day)日"
        ]

        switch presentation.workStatus {
        case .holiday:
            parts.append("休息日")
        case .makeupWorkday:
            parts.append("补班")
        case .weekend:
            parts.append("周末")
        case .unknown:
            parts.append("状态待确认")
        case .workday:
            parts.append("工作日")
        }

        if let reason = presentation.statusReason, !reason.isEmpty {
            parts.append(reason)
        }

        if let annotation = presentation.primaryAnnotation {
            parts.append("日期标注：\(annotation.title)")
        }

        if !presentation.vacationLabels.isEmpty {
            parts.append("个人假期：\(presentation.vacationLabels.joined(separator: "、"))")
        }

        if !presentation.specialDayLabels.isEmpty {
            parts.append("特殊日期：\(presentation.specialDayLabels.joined(separator: "、"))")
        }

        if presentation.scheduleCount > 0 {
            parts.append("本地日程：\(presentation.scheduleCount) 项")
        }

        if isToday {
            parts.append("今天")
        }

        if isSelected {
            parts.append("已选中")
        }

        return parts.joined(separator: "，")
    }
}

#Preview("日历") {
    NavigationStack {
        CalendarScreen(
            repository: nil,
            initialDate: CalendarMonth(year: 2026, month: 1)?.firstDay.date ?? .now
        )
    }
    .environment(AppRouter())
    .environment(Theme())
}
