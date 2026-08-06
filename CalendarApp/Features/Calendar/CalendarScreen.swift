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
        ScrollView {
            VStack(spacing: 16) {
                monthHeader
                WeekdayHeader(theme: theme)
                monthGrid
                monthOverviewCard
                upcomingDatesSection
                statusMessage
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(theme.backgroundPrimary)
        .safeAreaPadding(.bottom, 88)
        .navigationTitle("日历")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    model.moveMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("上个月")
                .accessibilityIdentifier("calendar.month.previous")
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("今天") {
                    model.goToToday()
                }
                .accessibilityLabel("回到今天")
                .accessibilityIdentifier("calendar.today")

                Button {
                    model.moveMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("下个月")
                .accessibilityIdentifier("calendar.month.next")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isScheduleListPresented = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("搜索本地日程")
                .accessibilityIdentifier("calendar.scheduleSearch")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    scheduleEditorItem = .new
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加日程")
                .accessibilityIdentifier("calendar.addSchedule")
            }
        }
        .task(id: model.displayedMonth.id) {
            await model.load()
        }
        .refreshable {
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
                    model.selectedDayID = day.dayID
                    router.navigate(to: .dayDetail(dayID: day.dayID))
                }
            }
        }
        .padding(.vertical, 2)
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
        .accessibilityHint("打开日期详情")
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
