import Observation
import SwiftUI

enum ScheduleListDataState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed
}

@MainActor
@Observable
final class ScheduleListFeatureModel {
    @ObservationIgnored let repository: (any ScheduleRepositoryProtocol)?

    let year: Int
    var allItems: [ScheduleItem] = []
    var query = ScheduleQuery()
    var dataState: ScheduleListDataState = .idle
    var errorMessage: String?

    init(
        repository: (any ScheduleRepositoryProtocol)?,
        year: Int
    ) {
        self.repository = repository
        self.year = year
    }

    var filteredItems: [ScheduleItem] {
        allItems
            .filter(query.matches)
            .sorted {
                if $0.startDate != $1.startDate {
                    return $0.startDate < $1.startDate
                }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    func load() async {
        guard let repository else {
            allItems = []
            dataState = .loaded
            return
        }

        dataState = allItems.isEmpty ? .loading : .loaded
        errorMessage = nil

        do {
            allItems = try repository.search(ScheduleQuery(), in: year)
            dataState = .loaded
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "本地日程暂不可用"
            dataState = .failed
        } catch {
            errorMessage = "本地日程暂不可用"
            dataState = .failed
        }
    }

    func save(_ schedule: ScheduleItem) -> String? {
        guard let repository else {
            return "本地日程服务尚未准备好"
        }

        do {
            try repository.save(schedule)
            Task { await load() }
            return nil
        } catch let error as LocalizedError {
            return error.errorDescription ?? "本地日程暂不可用"
        } catch {
            return "本地日程暂不可用"
        }
    }

    func delete(_ schedule: ScheduleItem) -> String? {
        guard let repository else {
            return "本地日程服务尚未准备好"
        }

        do {
            try repository.delete(id: schedule.id)
            allItems.removeAll { $0.id == schedule.id }
            return nil
        } catch let error as LocalizedError {
            return error.errorDescription ?? "本地日程暂不可用"
        } catch {
            return "本地日程暂不可用"
        }
    }
}

@MainActor
struct ScheduleListScreen: View {
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var model: ScheduleListFeatureModel
    @State private var editorItem: ScheduleEditorItem?
    @State private var pendingDeletion: ScheduleItem?
    @State private var operationError: String?

    init(
        repository: (any ScheduleRepositoryProtocol)?,
        initialDate: Date = .now
    ) {
        _model = State(
            initialValue: ScheduleListFeatureModel(
                repository: repository,
                year: DayID(initialDate).year
            )
        )
    }

    var body: some View {
        @Bindable var model = model

        return NavigationStack {
            listContent
                .background(theme.backgroundPrimary)
                .navigationTitle("本地日程")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $model.query.text, prompt: "搜索标题或备注")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("完成") {
                            dismiss()
                        }
                        .accessibilityIdentifier("schedule.list.done")
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        filterMenu
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            editorItem = .new
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("添加日程")
                        .accessibilityIdentifier("schedule.list.add")
                    }
                }
                .task {
                    await model.load()
                }
                .sheet(item: $editorItem) { item in
                    ScheduleEditorSheet(
                        item: item,
                        onSave: model.save,
                        onDelete: item.isEditing ? {
                            if case let .existing(schedule) = item {
                                pendingDeletion = schedule
                            }
                        } : nil
                    )
                }
                .confirmationDialog(
                    "删除本地日程",
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
                        confirmDeletion()
                    }
                    Button("取消", role: .cancel) {
                        pendingDeletion = nil
                    }
                } message: {
                    Text(pendingDeletion.map { "确定删除“\($0.title)”吗？" } ?? "此操作无法撤销")
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
                    Text(operationError ?? "本地日程暂不可用")
                }
                .accessibilityIdentifier("screen.scheduleList")
        }
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .environment(\.calendar, displayCalendar)
    }

    @ViewBuilder
    private var listContent: some View {
        switch model.dataState {
        case .idle:
            ProgressView("正在读取本地日程")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("schedule.list.loading")
        case .loading where model.allItems.isEmpty:
            ProgressView("正在读取本地日程")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("schedule.list.loading")
        case .failed where model.allItems.isEmpty:
            ContentUnavailableView(
                "本地日程暂不可用",
                systemImage: "exclamationmark.triangle",
                description: Text(model.errorMessage ?? "请稍后重试")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("schedule.list.error")
        default:
            if model.allItems.isEmpty {
                ContentUnavailableView(
                    "还没有本地日程",
                    systemImage: "calendar.badge.plus",
                    description: Text("点击右上角加号创建第一条日程")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("schedule.list.empty")
            } else if model.filteredItems.isEmpty {
                ContentUnavailableView(
                    "没有匹配日程",
                    systemImage: "magnifyingglass",
                    description: Text("尝试修改搜索词或过滤条件")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("schedule.list.noResults")
            } else {
                List {
                    Section {
                        ForEach(model.filteredItems) { schedule in
                            Button {
                                editorItem = .existing(schedule)
                            } label: {
                                ScheduleListRow(schedule: schedule, theme: theme)
                    }
                    .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDeletion = schedule
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    .accessibilityIdentifier("schedule.list.item.\(schedule.id.uuidString)")
                        }
                    } header: {
                        Text(verbatim: "\(model.year)年 · \(model.filteredItems.count) 项")
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("类型", selection: Binding(
                get: { model.query.kind },
                set: { model.query.kind = $0 }
            )) {
                ForEach(ScheduleKindFilter.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }

            Picker("颜色", selection: Binding(
                get: { model.query.color?.rawValue ?? "all" },
                set: { rawValue in
                    model.query.color = rawValue == "all" ? nil : ScheduleColor(rawValue: rawValue)
                }
            )) {
                Text("全部颜色").tag("all")
                ForEach(ScheduleColor.allCases) { color in
                    Text(color.displayName).tag(color.rawValue)
                }
            }
        } label: {
            Image(systemName: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("过滤日程")
        .accessibilityIdentifier("schedule.list.filter")
    }

    private var isFiltering: Bool {
        model.query.kind != .all || model.query.color != nil
    }

    private func confirmDeletion() {
        guard let pendingDeletion else {
            return
        }

        self.pendingDeletion = nil
        if let message = model.delete(pendingDeletion) {
            operationError = message
        }
    }

    private var displayCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = DayID.defaultTimeZone
        return calendar
    }
}

@MainActor
private struct ScheduleListRow: View {
    let schedule: ScheduleItem
    let theme: Theme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .padding(.top, 6)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(schedule.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.labelPrimary)

                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(theme.labelSecondary)

                if let note = schedule.note, !note.isEmpty {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(theme.labelSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(schedule.title)，\(detailText)")
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

    private var detailText: String {
        let dateText: String
        if schedule.isAllDay {
            if schedule.startDay == schedule.endDay {
                dateText = "全天 · \(schedule.startDay.month)月\(schedule.startDay.day)日"
            } else {
                dateText = "全天 · \(schedule.startDay.month)月\(schedule.startDay.day)日—\(schedule.endDay.month)月\(schedule.endDay.day)日"
            }
        } else {
            dateText = "\(schedule.startDate.formatted(date: .abbreviated, time: .shortened))—\(schedule.endDate.formatted(date: .omitted, time: .shortened))"
        }

        if let repeatUntil = schedule.repeatUntilDay {
            return "\(dateText) · \(schedule.recurrence.displayName)至\(repeatUntil.month)月\(repeatUntil.day)日"
        }
        return dateText
    }
}

#Preview("本地日程") {
    ScheduleListScreen(repository: nil, initialDate: DayID(year: 2026, month: 8, day: 6)!.date!)
        .environment(Theme())
}
