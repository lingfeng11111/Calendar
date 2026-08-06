import SwiftUI

@MainActor
struct VacationScreen: View {
    @Environment(Theme.self) private var theme
    @State private var model: VacationFeatureModel
    @State private var editorItem: PersonalDateEditorItem?
    @State private var pendingDeletion: PersonalDateDeletion?
    @State private var operationError: String?
    private let autoPresentEditor: Bool

    init(
        repository: (any VacationRepositoryProtocol)? = nil,
        initialYear: Int = DayID(Date()).year
    ) {
        autoPresentEditor = ProcessInfo.processInfo.arguments.contains("-ui-testing-editor")
        _model = State(
            initialValue: VacationFeatureModel(
                repository: repository,
                initialYear: initialYear
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                yearHeader
                overviewCard

                if model.dataState == .failed {
                    errorCard
                } else if model.isEmpty && model.dataState == .loaded {
                    emptyState
                } else {
                    if !model.vacationPeriods.isEmpty {
                        vacationSection
                    }

                    if !model.specialDays.isEmpty {
                        specialDaySection
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(theme.backgroundPrimary)
        .safeAreaPadding(.bottom, 88)
        .navigationTitle("假期")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        editorItem = .new(.vacationPeriod)
                    } label: {
                        Label("添加假期区间", systemImage: "calendar.badge.plus")
                    }

                    Button {
                        editorItem = .new(.specialDay)
                    } label: {
                        Label("添加特殊日期", systemImage: "sparkles")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加个人日期")
                .accessibilityIdentifier("vacation.add")
            }
        }
        .accessibilityIdentifier("screen.vacation")
        .task {
            if model.dataState == .idle {
                model.load()
            }
            if autoPresentEditor, editorItem == nil {
                editorItem = .new(.vacationPeriod)
            }
        }
        .refreshable {
            model.load()
        }
        .sheet(item: $editorItem) { item in
            PersonalDateEditorSheet(
                item: item,
                onSave: save,
                onDelete: item.isEditing ? {
                    pendingDeletion = deletion(for: item)
                } : nil
            )
        }
        .confirmationDialog(
            "删除个人日期",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                confirmDelete()
            }
            Button("取消", role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text(pendingDeletion?.message ?? "此操作无法撤销")
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { operationError != nil },
                set: { isPresented in
                    if !isPresented {
                        operationError = nil
                    }
                }
            )
        ) {
            Button("知道了", role: .cancel) {
                operationError = nil
            }
        } message: {
            Text(operationError ?? "个人日期暂不可用")
        }
    }

    private var yearHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("个人日期")
                .font(.title2.weight(.semibold))
                .foregroundStyle(theme.labelPrimary)
                .accessibilityAddTraits(.isHeader)

            Text(verbatim: "\(model.year) 年")
                .font(.subheadline)
                .foregroundStyle(theme.labelSecondary)
                .accessibilityIdentifier("vacation.year")
        }
    }

    private var overviewCard: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                overviewMetric(
                    value: "\(model.vacationPeriods.count)",
                    title: "假期区间"
                )
                overviewDivider
                overviewMetric(
                    value: "\(model.specialDays.count)",
                    title: "特殊日期"
                )
                overviewDivider
                overviewMetric(
                    value: "\(totalVacationDays)",
                    title: "总天数"
                )
            }
            .padding(16)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    overviewMetric(
                        value: "\(model.vacationPeriods.count)",
                        title: "假期区间"
                    )
                    Spacer()
                    overviewMetric(
                        value: "\(model.specialDays.count)",
                        title: "特殊日期"
                    )
                }
                overviewMetric(
                    value: "\(totalVacationDays)",
                    title: "总天数"
                )
            }
            .padding(16)
        }
        .background(theme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "年度概览，\(model.vacationPeriods.count) 个假期区间，\(model.specialDays.count) 个特殊日期，共 \(totalVacationDays) 天"
        )
        .accessibilityIdentifier("vacation.overview")
    }

    private var vacationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "假期区间", count: model.vacationPeriods.count)

            ForEach(model.vacationPeriods) { period in
                Button {
                    editorItem = .period(period)
                } label: {
                    VacationPeriodRow(period: period, theme: theme)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDeletion = .period(period)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var specialDaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "特殊日期", count: model.specialDays.count)

            ForEach(model.specialDays) { specialDay in
                Button {
                    editorItem = .specialDay(specialDay)
                } label: {
                    SpecialDayRow(
                        specialDay: specialDay,
                        year: model.year,
                        theme: theme
                    )
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDeletion = .specialDay(specialDay)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "还没有个人日期",
            systemImage: "calendar.badge.plus",
            description: Text("寒假、暑假、年假和纪念日会显示在这里。")
        )
        .frame(maxWidth: .infinity, minHeight: 240)
        .foregroundStyle(theme.labelSecondary)
        .accessibilityIdentifier("vacation.empty")
    }

    private var errorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("暂时无法读取个人日期", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(theme.statusHoliday)

            Text(model.errorMessage ?? "个人日期暂不可用")
                .font(.subheadline)
                .foregroundStyle(theme.labelSecondary)

            Button("重新检查") {
                model.retry()
            }
            .buttonStyle(.bordered)
            .tint(theme.tint)
            .accessibilityIdentifier("vacation.retry")
            .accessibilityLabel("重新检查个人日期")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vacation.error")
    }

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(theme.labelPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            Text(verbatim: "\(count)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.labelSecondary)
        }
    }

    private func overviewMetric(value: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.labelPrimary)

            Text(title)
                .font(.caption)
                .foregroundStyle(theme.labelSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var overviewDivider: some View {
        Divider()
            .frame(height: 34)
            .padding(.horizontal, 12)
    }

    private var totalVacationDays: Int {
        model.vacationPeriods.reduce(0) { $0 + daysInDisplayedYear(of: $1) }
    }

    private func daysInDisplayedYear(of period: VacationPeriod) -> Int {
        let firstDay = max(period.startDay, DayID(year: model.year, month: 1, day: 1)!)
        let lastDay = min(period.endDay, DayID(year: model.year, month: 12, day: 31)!)
        guard firstDay <= lastDay else {
            return 0
        }
        return firstDay.days(to: lastDay) + 1
    }

    private func save(_ value: PersonalDateEditorValue) -> String? {
        do {
            switch value {
            case let .period(period):
                try model.save(period: period)
            case let .specialDay(specialDay):
                try model.save(specialDay: specialDay)
            }
            return nil
        } catch let error as LocalizedError {
            return error.errorDescription ?? "个人日期暂不可用"
        } catch {
            return "个人日期暂不可用"
        }
    }

    private func deletion(for item: PersonalDateEditorItem) -> PersonalDateDeletion? {
        switch item {
        case .new:
            nil
        case let .period(period):
            .period(period)
        case let .specialDay(specialDay):
            .specialDay(specialDay)
        }
    }

    private func confirmDelete() {
        guard let deletion = pendingDeletion else {
            return
        }
        pendingDeletion = nil

        do {
            switch deletion {
            case let .period(period):
                try model.delete(period: period)
            case let .specialDay(specialDay):
                try model.delete(specialDay: specialDay)
            }
        } catch let error as LocalizedError {
            operationError = error.errorDescription ?? "个人日期暂不可用"
        } catch {
            operationError = "个人日期暂不可用"
        }
    }
}

private enum PersonalDateDeletion {
    case period(VacationPeriod)
    case specialDay(SpecialDay)

    var message: String {
        switch self {
        case let .period(period):
            "确定删除“\(period.title)”吗？"
        case let .specialDay(specialDay):
            "确定删除“\(specialDay.title)”吗？"
        }
    }
}

private struct VacationPeriodRow: View {
    let period: VacationPeriod
    let theme: Theme

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalRow
            verticalRow
        }
        .padding(16)
        .background(theme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(period.title)，\(period.kind.displayName)，\(dateRangeText)，\(period.dayCount) 天"
        )
        .accessibilityIdentifier("vacation.period.\(period.id.uuidString)")
    }

    private var horizontalRow: some View {
        HStack(alignment: .center, spacing: 12) {
            icon

            VStack(alignment: .leading, spacing: 4) {
                Text(period.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.labelPrimary)

                Text(period.kind.displayName)
                    .font(.caption)
                    .foregroundStyle(theme.labelSecondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(dateRangeText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.labelPrimary)
                    .multilineTextAlignment(.trailing)

                Text("\(period.dayCount) 天")
                    .font(.caption)
                    .foregroundStyle(theme.labelSecondary)
            }
        }
    }

    private var verticalRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                icon

                VStack(alignment: .leading, spacing: 4) {
                    Text(period.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.labelPrimary)

                    Text(period.kind.displayName)
                        .font(.caption)
                        .foregroundStyle(theme.labelSecondary)
                }

                Spacer(minLength: 8)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(dateRangeText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.labelPrimary)

                Spacer(minLength: 8)

                Text("\(period.dayCount) 天")
                    .font(.caption)
                    .foregroundStyle(theme.labelSecondary)
            }
        }
    }

    private var icon: some View {
        Image(systemName: period.kind.systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(theme.statusVacation)
            .frame(width: 36, height: 36)
            .background(theme.statusVacation.opacity(0.14), in: Circle())
            .accessibilityHidden(true)
    }

    private var dateRangeText: String {
        if period.startDay.year == period.endDay.year {
            return "\(period.startDay.month)月\(period.startDay.day)日—\(period.endDay.month)月\(period.endDay.day)日"
        }
        return "\(period.startDay.year)/\(period.startDay.month)/\(period.startDay.day)—\(period.endDay.year)/\(period.endDay.month)/\(period.endDay.day)"
    }
}

private struct SpecialDayRow: View {
    let specialDay: SpecialDay
    let year: Int
    let theme: Theme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.14), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(specialDay.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.labelPrimary)

                Text(specialDay.recurrence.displayName)
                    .font(.caption)
                    .foregroundStyle(theme.labelSecondary)
            }

            Spacer(minLength: 8)

            Text(dateText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.labelPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(16)
        .background(theme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(specialDay.title)，\(specialDay.recurrence.displayName)，\(dateText)")
        .accessibilityIdentifier("vacation.special.\(specialDay.id.uuidString)")
    }

    private var color: Color {
        switch specialDay.color {
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

    private var dateText: String {
        guard let day = specialDay.resolvedDay(for: year) else {
            return "日期待完善"
        }

        switch specialDay.recurrence {
        case .none:
            return "\(day.month)月\(day.day)日"
        case .yearlyGregorian:
            return "每年 \(day.month)月\(day.day)日"
        case .yearlyLunar:
            return "农历日期待接入"
        }
    }
}

@MainActor
private struct EmptyVacationRepository: VacationRepositoryProtocol {
    func snapshot(for year: Int) throws -> PersonalDateSnapshot {
        PersonalDateSnapshot(year: year, vacationPeriods: [], specialDays: [])
    }
}

@MainActor
private struct FailedVacationRepository: VacationRepositoryProtocol {
    func snapshot(for year: Int) throws -> PersonalDateSnapshot {
        throw VacationRepositoryError.persistenceFailed
    }
}

#Preview("假期 · 示例") {
    NavigationStack {
        VacationScreen(initialYear: 2026)
    }
    .environment(Theme())
}

#Preview("假期 · 空状态") {
    NavigationStack {
        VacationScreen(repository: EmptyVacationRepository(), initialYear: 2026)
    }
    .environment(Theme())
}

#Preview("假期 · 错误") {
    NavigationStack {
        VacationScreen(repository: FailedVacationRepository(), initialYear: 2026)
    }
    .environment(Theme())
}
