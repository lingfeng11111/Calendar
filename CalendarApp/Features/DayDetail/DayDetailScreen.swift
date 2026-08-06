import SwiftUI

@MainActor
struct DayDetailScreen: View {
    @Environment(Theme.self) private var theme
    @Environment(AppRouter.self) private var router

    @State private var model: DayDetailFeatureModel
    @State private var scheduleEditorItem: ScheduleEditorItem?
    @State private var pendingScheduleDeletion: ScheduleItem?
    @State private var scheduleOperationError: String?

    init(
        dayID: DayID,
        repository: (any HolidayRepositoryProtocol)? = nil,
        vacationRepository: (any VacationRepositoryProtocol)? = nil,
        scheduleRepository: (any ScheduleRepositoryProtocol)? = nil,
        dateKnowledgeRepository: (any DateKnowledgeRepositoryProtocol)? = nil,
        systemCalendarService: (any SystemCalendarServiceProtocol)? = nil
    ) {
        _model = State(
            initialValue: DayDetailFeatureModel(
                dayID: dayID,
                repository: repository,
                vacationRepository: vacationRepository,
                scheduleRepository: scheduleRepository,
                dateKnowledgeRepository: dateKnowledgeRepository,
                systemCalendarService: systemCalendarService
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                dateHeader
                stateContent

                if !model.scheduleItems.isEmpty {
                    scheduleTimeline
                }

                if model.systemCalendarService != nil {
                    systemCalendarTimeline
                }

                if model.dataState != .loading, model.dataState != .idle {
                    sourceCard
                    additionalInformation
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(theme.backgroundPrimary)
        .safeAreaPadding(.bottom, 88)
        .navigationTitle("日期详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
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
        .accessibilityIdentifier("screen.dayDetail")
    }

    private var scheduleTimeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("本地日程", systemImage: "calendar.badge.clock")
                    .font(.headline)
                    .foregroundStyle(theme.labelPrimary)

                Spacer(minLength: 8)

                Text(verbatim: "\(model.scheduleItems.count)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.labelSecondary)
            }

            ForEach(model.scheduleItems) { schedule in
                Button {
                    scheduleEditorItem = .existing(schedule)
                } label: {
                    ScheduleTimelineRow(schedule: schedule, theme: theme)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingScheduleDeletion = schedule
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("day.detail.schedules")
    }

    @ViewBuilder
    private var systemCalendarTimeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("系统日历", systemImage: "calendar.badge.checkmark")
                    .font(.headline)
                    .foregroundStyle(theme.labelPrimary)

                Spacer(minLength: 8)

                Text(systemCalendarStateTitle)
                    .font(.caption)
                    .foregroundStyle(theme.labelSecondary)
            }

            switch model.systemCalendarState {
            case .idle, .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在读取系统日历")
                        .font(.subheadline)
                        .foregroundStyle(theme.labelSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            case .loaded:
                if model.systemCalendarEvents.isEmpty {
                    Label("当天没有系统日历事件", systemImage: "calendar.badge.minus")
                        .font(.subheadline)
                        .foregroundStyle(theme.labelSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    ForEach(model.systemCalendarEvents) { event in
                        SystemCalendarTimelineRow(event: event, theme: theme)
                    }
                }
            case .permissionRequired:
                systemCalendarMessage(
                    title: "需要读取权限",
                    message: "请在设置页允许读取系统日历，应用不会修改系统事件。",
                    actionTitle: "打开设置页"
                ) {
                    router.navigate(to: .settings)
                }
            case .accessDenied:
                systemCalendarMessage(
                    title: "系统日历访问已关闭",
                    message: "请在系统设置中重新开启完整读取权限。",
                    actionTitle: "重新检查"
                ) {
                    Task { await model.loadSystemCalendarEvents() }
                }
            case .accessRestricted:
                systemCalendarMessage(
                    title: "系统日历访问受限",
                    message: model.systemCalendarErrorMessage ?? "当前设备限制了系统日历访问。"
                )
            case .unavailable:
                systemCalendarMessage(
                    title: "系统日历不可用",
                    message: model.systemCalendarErrorMessage ?? "当前构建没有可用的系统日历服务。"
                )
            case .failed:
                systemCalendarMessage(
                    title: "系统日历读取失败",
                    message: model.systemCalendarErrorMessage ?? "请稍后重试。",
                    actionTitle: "重新读取"
                ) {
                    Task { await model.loadSystemCalendarEvents() }
                }
            }
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("day.detail.systemCalendar")
    }

    private func systemCalendarMessage(
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.labelPrimary)

            Text(message)
                .font(.footnote)
                .foregroundStyle(theme.labelSecondary)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.tint)
            }
        }
    }

    private var systemCalendarStateTitle: String {
        switch model.systemCalendarState {
        case .idle:
            "准备读取"
        case .loading:
            "读取中"
        case .loaded:
            model.systemCalendarEvents.isEmpty ? "无事件" : "(model.systemCalendarEvents.count) 项"
        case .permissionRequired:
            "需要授权"
        case .accessDenied:
            "访问关闭"
        case .accessRestricted:
            "访问受限"
        case .unavailable:
            "不可用"
        case .failed:
            "读取失败"
        }
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

    private var dateHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "\(model.dayID.year)年\(model.dayID.month)月\(model.dayID.day)日")
                .font(.title2.weight(.semibold))
                .foregroundStyle(theme.labelPrimary)
                .accessibilityIdentifier("day.detail.date")

            Text(weekdayText)
                .font(.subheadline)
                .foregroundStyle(theme.labelSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.dayID.year)年\(model.dayID.month)月\(model.dayID.day)日，\(weekdayText)")
        .accessibilityIdentifier("day.detail.date")
    }

    @ViewBuilder
    private var stateContent: some View {
        switch model.dataState {
        case .idle:
            HStack(spacing: 10) {
                ProgressView()
                Text("正在读取日期状态")
                    .font(.subheadline)
                    .foregroundStyle(theme.labelSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("正在读取日期状态")
            .accessibilityIdentifier("day.detail.loading")
        case .loading:
            VStack(alignment: .leading, spacing: 8) {
                statusCard

                Label("正在读取日期状态，先显示本地规则", systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote)
                    .foregroundStyle(theme.labelSecondary)
                    .accessibilityIdentifier("day.detail.loading")
            }
        case .loaded, .refreshing, .refreshFailed, .notPublished, .unavailable:
            statusCard
        }
    }

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusSymbol)
                .font(.title2)
                .foregroundStyle(statusColor)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(statusTitle)
                    .font(.headline)
                    .foregroundStyle(theme.labelPrimary)
                    .accessibilityAddTraits(.isHeader)

                if let reason = model.presentation.statusReason, !reason.isEmpty {
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(theme.labelSecondary)
                }

                if model.dataState == .refreshing {
                    Label("正在刷新，当前状态仍可查看", systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                        .foregroundStyle(theme.labelSecondary)
                        .accessibilityIdentifier("day.detail.refreshing")
                }

                if model.dataState == .refreshFailed,
                   let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(theme.statusUnknown)
                }

                if model.dataState == .refreshFailed
                    || model.dataState == .notPublished
                    || model.dataState == .unavailable {
                    Button("重新检查") {
                        Task { await model.load() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.tint)
                    .accessibilityLabel("重新检查节假日数据")
                    .accessibilityIdentifier("day.detail.retry")
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(statusColor.opacity(0.25), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(statusAccessibilityText)
        .accessibilityIdentifier("day.detail.status")
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("数据来源", systemImage: "arrow.triangle.branch")
                .font(.headline)
                .foregroundStyle(theme.labelPrimary)

            detailRow(title: "来源类型", value: sourceTitle)

            if let providerID {
                detailRow(title: "来源标识", value: providerID)
            }

            if let sourceURL = model.sourceURL {
                detailRow(
                    title: "来源地址",
                    value: sourceURL.host ?? sourceURL.absoluteString
                )
            }

            if let fetchedAt = model.fetchedAt {
                detailRow(
                    title: "更新时间",
                    value: fetchedAt.formatted(date: .abbreviated, time: .shortened)
                )
            }

            if let providerID = model.dateKnowledgeProviderID {
                detailRow(title: "日期知识来源", value: providerID)
            }

            if let sourceURL = model.dateKnowledgeSourceURL {
                detailRow(
                    title: "日期知识地址",
                    value: sourceURL.host ?? sourceURL.absoluteString
                )
            }

            if let fetchedAt = model.dateKnowledgeFetchedAt {
                detailRow(
                    title: "日期知识更新时间",
                    value: fetchedAt.formatted(date: .abbreviated, time: .shortened)
                )
            }
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("day.detail.source")
    }

    @ViewBuilder
    private var additionalInformation: some View {
        let hasAdditionalInformation = !model.presentation.holidayLabels.isEmpty
            || !model.presentation.vacationLabels.isEmpty
            || !model.presentation.specialDayLabels.isEmpty
            || !model.presentation.annotationCandidates.isEmpty
            || model.presentation.scheduleCount > 0

        if hasAdditionalInformation {
            VStack(alignment: .leading, spacing: 12) {
                Label("日期信息", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                    .foregroundStyle(theme.labelPrimary)

                ForEach(additionalRows, id: \.title) { row in
                    detailRow(title: row.title, value: row.value)
                }
            }
            .padding(16)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityIdentifier("day.detail.information")
        }
    }

    private var additionalRows: [(title: String, value: String)] {
        var rows: [(title: String, value: String)] = []

        if !model.presentation.holidayLabels.isEmpty {
            rows.append(("节假日标签", model.presentation.holidayLabels.joined(separator: "、")))
        }

        if !model.presentation.vacationLabels.isEmpty {
            rows.append(("个人假期", model.presentation.vacationLabels.joined(separator: "、")))
        }

        if !model.presentation.specialDayLabels.isEmpty {
            rows.append(("特殊日期", model.presentation.specialDayLabels.joined(separator: "、")))
        }

        if let primaryAnnotation = model.presentation.primaryAnnotation {
            rows.append(
                (
                    "主要日期标注",
                    "\(primaryAnnotation.title)（\(primaryAnnotation.kind.displayName)）"
                )
            )

            let otherAnnotations = model.presentation.annotationCandidates
                .dropFirst()
                .map { "\($0.title)（\($0.kind.displayName)）" }
            if !otherAnnotations.isEmpty {
                rows.append(("其他日期标注", otherAnnotations.joined(separator: "、")))
            }
        }

        if model.presentation.scheduleCount > 0 {
            rows.append(("本地日程", "\(model.presentation.scheduleCount) 项"))
        }

        return rows
    }

    private func detailRow(title: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .foregroundStyle(theme.labelSecondary)

                Spacer(minLength: 12)

                Text(value)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(theme.labelPrimary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(theme.labelSecondary)

                Text(value)
                    .foregroundStyle(theme.labelPrimary)
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(value)")
    }

    private var cardBackground: some ShapeStyle {
        theme.backgroundSecondary
    }

    private var weekdayText: String {
        let labels = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
        let index = model.dayID.weekday() - 1
        return labels.indices.contains(index) ? labels[index] : ""
    }

    private var statusTitle: String {
        switch model.presentation.workStatus {
        case .workday:
            "工作日"
        case .weekend:
            "周末休息"
        case .holiday:
            "法定休息日"
        case .makeupWorkday:
            "调休补班"
        case .unknown:
            "状态待确认"
        }
    }

    private var statusSymbol: String {
        switch model.presentation.workStatus {
        case .workday:
            "checkmark.circle.fill"
        case .weekend:
            "bed.double.fill"
        case .holiday:
            "party.popper.fill"
        case .makeupWorkday:
            "briefcase.fill"
        case .unknown:
            "questionmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch model.presentation.workStatus {
        case .workday:
            theme.labelPrimary
        case .weekend:
            theme.labelSecondary
        case .holiday:
            theme.statusHoliday
        case .makeupWorkday:
            theme.statusMakeupWorkday
        case .unknown:
            theme.statusUnknown
        }
    }

    private var sourceTitle: String {
        switch model.presentation.statusSource {
        case .defaultWeekRule:
            "普通星期规则"
        case .userOverride:
            "个人覆盖"
        case let .holidayProvider(providerID):
            "节假日数据源（\(providerID)）"
        case let .schoolOrCompany(name):
            "学校或公司规则（\(name)）"
        case .unknown:
            "暂未确定"
        }
    }

    private var providerID: String? {
        guard case let .holidayProvider(providerID) = model.presentation.statusSource else {
            return nil
        }

        return providerID
    }

    private var statusAccessibilityText: String {
        var parts = [statusTitle]

        if let reason = model.presentation.statusReason, !reason.isEmpty {
            parts.append(reason)
        }

        if model.dataState == .refreshing {
            parts.append("正在刷新，当前状态仍可查看")
        } else if model.dataState == .loading {
            parts.append("正在读取，先显示本地规则")
        } else if model.dataState == .refreshFailed,
                  let errorMessage = model.errorMessage {
            parts.append(errorMessage)
        }

        parts.append("来源：\(sourceTitle)")
        return parts.joined(separator: "，")
    }
}

@MainActor
private struct ScheduleTimelineRow: View {
    let schedule: ScheduleItem
    let theme: Theme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: schedule.isAllDay ? "calendar" : "clock")
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.14), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(schedule.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.labelPrimary)

                Text(schedule.recurrence == .none ? timeText : "\(timeText)，\(schedule.recurrence.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(theme.labelSecondary)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(schedule.title)，\(timeText)")
        .accessibilityIdentifier("day.detail.schedule.\(schedule.id.uuidString)")
    }

    private var color: Color {
        switch schedule.color {
        case .blue:
            theme.tint
        case .teal:
            theme.statusVacation
        case .purple:
            Color(uiColor: .systemPurple)
        case .orange:
            theme.statusMakeupWorkday
        }
    }

    private var timeText: String {
        if schedule.isAllDay {
            if schedule.startDay == schedule.endDay {
                return "全天，\(schedule.startDay.month)月\(schedule.startDay.day)日"
            }
            return "全天，\(schedule.startDay.month)月\(schedule.startDay.day)日—\(schedule.endDay.month)月\(schedule.endDay.day)日"
        }

        if schedule.startDay == schedule.endDay {
            return "\(schedule.startDate.formatted(date: .omitted, time: .shortened))—\(schedule.endDate.formatted(date: .omitted, time: .shortened))"
        }
        return "\(schedule.startDate.formatted(date: .abbreviated, time: .shortened))—\(schedule.endDate.formatted(date: .abbreviated, time: .shortened))"
    }
}

@MainActor
private struct SystemCalendarTimelineRow: View {
    let event: SystemCalendarEventSnapshot
    let theme: Theme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.isAllDay ? "calendar" : "clock")
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.statusVacation)
                .frame(width: 36, height: 36)
                .background(theme.statusVacation.opacity(0.14), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.labelPrimary)

                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(theme.labelSecondary)

                Text(event.sourceTitle ?? event.calendarTitle)
                    .font(.caption)
                    .foregroundStyle(theme.labelSecondary)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("(event.title)，(detailText)，来源：(event.sourceTitle ?? event.calendarTitle)")
        .accessibilityIdentifier("day.detail.systemCalendar.\(event.id)")
    }

    private var detailText: String {
        let timeText: String
        if event.isAllDay {
            let start = DayID(event.startDate)
            let end = DayID(event.endDate.addingTimeInterval(-1))
            timeText = start == end
                ? "全天，(start.month)月(start.day)日"
                : "全天，(start.month)月(start.day)日—(end.month)月(end.day)日"
        } else {
            timeText = event.startDate == event.endDate
                ? event.startDate.formatted(date: .omitted, time: .shortened)
                : "(event.startDate.formatted(date: .omitted, time: .shortened))—(event.endDate.formatted(date: .omitted, time: .shortened))"
        }

        if let recurrence = event.recurrenceDescription, !recurrence.isEmpty {
            return "(timeText)，(recurrence)"
        }
        return timeText
    }
}

#Preview("法定休息日") {
    NavigationStack {
        DayDetailScreen(
            dayID: DayID(year: 2026, month: 1, day: 1)!,
            repository: nil
        )
    }
    .environment(AppRouter())
    .environment(Theme())
}

#Preview("普通工作日") {
    NavigationStack {
        DayDetailScreen(
            dayID: DayID(year: 2026, month: 1, day: 2)!,
            repository: nil
        )
    }
    .environment(AppRouter())
    .environment(Theme())
}

#Preview("系统日历未授权") {
    NavigationStack {
        DayDetailScreen(
            dayID: DayID(year: 2026, month: 1, day: 2)!,
            repository: nil,
            systemCalendarService: PreviewSystemCalendarService()
        )
    }
    .environment(AppRouter())
    .environment(Theme())
}

@MainActor
private final class PreviewSystemCalendarService: SystemCalendarServiceProtocol {
    let access: SystemCalendarAccess = .notDetermined

    func requestReadAccess() async -> SystemCalendarAccess {
        access
    }

    func events(
        in interval: DateInterval,
        calendarIDs: Set<String>?
    ) async throws -> [SystemCalendarEventSnapshot] {
        []
    }
}
