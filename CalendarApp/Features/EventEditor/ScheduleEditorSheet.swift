import SwiftUI

enum ScheduleEditorItem: Identifiable {
    case new
    case existing(ScheduleItem)

    var id: String {
        switch self {
        case .new:
            "new-schedule"
        case let .existing(schedule):
            "schedule-\(schedule.id.uuidString)"
        }
    }

    var isEditing: Bool {
        switch self {
        case .new:
            false
        case .existing:
            true
        }
    }
}

@MainActor
struct ScheduleEditorSheet: View {
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss

    private let item: ScheduleEditorItem
    private let onSave: (ScheduleItem) -> String?
    private let onDelete: (() -> Void)?

    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isAllDay: Bool
    @State private var recurrence: ScheduleRecurrence
    @State private var repeatUntil: Date
    @State private var color: ScheduleColor
    @State private var note: String
    @State private var validationMessage: String?

    init(
        item: ScheduleEditorItem,
        onSave: @escaping (ScheduleItem) -> String?,
        onDelete: (() -> Void)? = nil
    ) {
        self.item = item
        self.onSave = onSave
        self.onDelete = onDelete

        let values = Self.initialValues(for: item)
        _title = State(initialValue: values.title)
        _startDate = State(initialValue: values.startDate)
        _endDate = State(initialValue: values.endDate)
        _isAllDay = State(initialValue: values.isAllDay)
        _recurrence = State(initialValue: values.recurrence)
        _repeatUntil = State(initialValue: values.repeatUntil)
        _color = State(initialValue: values.color)
        _note = State(initialValue: values.note)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    detailsCard

                    recurrenceCard

                    noteCard

                    if let onDelete {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Label("删除此日程", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("schedule.editor.delete")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(theme.backgroundPrimary)
            .safeAreaPadding(.bottom, 16)
            .navigationTitle(item.isEditing ? "编辑日程" : "新建日程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .accessibilityIdentifier("schedule.editor.cancel")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("schedule.editor.save")
                }
            }
            .alert(
                "无法保存",
                isPresented: Binding(
                    get: { validationMessage != nil },
                    set: { if !$0 { validationMessage = nil } }
                )
            ) {
                Button("知道了", role: .cancel) {
                    validationMessage = nil
                }
            } message: {
                Text(validationMessage ?? "请检查输入")
            }
            .accessibilityIdentifier("schedule.editor")
        }
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .environment(\.calendar, displayCalendar)
    }

    private var detailsCard: some View {
        editorCard(title: "日程信息", systemImage: "calendar.badge.clock") {
            TextField("标题，例如项目评审", text: $title)
                .textInputAutocapitalization(.never)
                .submitLabel(.next)
                .accessibilityIdentifier("schedule.editor.title")

            Toggle("全天日程", isOn: $isAllDay)
                .onChange(of: isAllDay) { _, newValue in
                    guard newValue else { return }
                    startDate = displayCalendar.startOfDay(for: startDate)
                    endDate = displayCalendar.startOfDay(for: endDate)
                }
                .accessibilityIdentifier("schedule.editor.allDay")

            DatePicker(
                "开始\(isAllDay ? "日期" : "时间")",
                selection: $startDate,
                displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("schedule.editor.start")

            DatePicker(
                "结束\(isAllDay ? "日期" : "时间")",
                selection: $endDate,
                in: startDate...,
                displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("schedule.editor.end")

            Picker("颜色", selection: $color) {
                ForEach(ScheduleColor.allCases) { color in
                    Text(color.displayName).tag(color)
                }
            }
            .accessibilityIdentifier("schedule.editor.color")
        }
    }

    private var recurrenceCard: some View {
        editorCard(title: "重复规则", systemImage: "repeat") {
            Picker("重复", selection: $recurrence) {
                ForEach(ScheduleRecurrence.allCases) { recurrence in
                    Text(recurrence.displayName).tag(recurrence)
                }
            }
            .accessibilityIdentifier("schedule.editor.recurrence")

            if recurrence != .none {
                DatePicker(
                    "重复至",
                    selection: $repeatUntil,
                    in: startDate...,
                    displayedComponents: .date
                )
                .accessibilityIdentifier("schedule.editor.repeatUntil")
            }
        }
    }

    private var noteCard: some View {
        editorCard(title: "备注", systemImage: "note.text") {
            TextField("可选", text: $note, axis: .vertical)
                .lineLimit(2...5)
                .accessibilityIdentifier("schedule.editor.note")
        }
    }

    private func save() {
        validationMessage = nil

        let normalizedRepeatUntil: Date? = recurrence == .none
            ? nil
            : endOfDay(repeatUntil)

        do {
            let id: UUID
            if case let .existing(schedule) = item {
                id = schedule.id
            } else {
                id = UUID()
            }

            let schedule = try ScheduleItem(
                id: id,
                title: title,
                startDate: startDate,
                endDate: endDate,
                isAllDay: isAllDay,
                recurrence: recurrence,
                repeatUntil: normalizedRepeatUntil,
                color: color,
                note: note
            )

            if let message = onSave(schedule) {
                validationMessage = message
            } else {
                dismiss()
            }
        } catch let error as LocalizedError {
            validationMessage = error.errorDescription ?? "请检查输入"
        } catch {
            validationMessage = "请检查输入"
        }
    }

    private func editorCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(theme.labelPrimary)

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var displayCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = DayID.defaultTimeZone
        return calendar
    }

    private func endOfDay(_ date: Date) -> Date {
        let start = displayCalendar.startOfDay(for: date)
        return displayCalendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }

    private static func initialValues(for item: ScheduleEditorItem) -> (
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        recurrence: ScheduleRecurrence,
        repeatUntil: Date,
        color: ScheduleColor,
        note: String
    ) {
        let now = Date.now
        switch item {
        case .new:
            return (
                title: "",
                startDate: now,
                endDate: now.addingTimeInterval(60 * 60),
                isAllDay: false,
                recurrence: .none,
                repeatUntil: now.addingTimeInterval(30 * 24 * 60 * 60),
                color: .blue,
                note: ""
            )
        case let .existing(schedule):
            return (
                title: schedule.title,
                startDate: schedule.startDate,
                endDate: schedule.endDate,
                isAllDay: schedule.isAllDay,
                recurrence: schedule.recurrence,
                repeatUntil: schedule.repeatUntil ?? schedule.endDate,
                color: schedule.color,
                note: schedule.note ?? ""
            )
        }
    }
}

#Preview("新建日程") {
    ScheduleEditorSheet(item: .new, onSave: { _ in nil })
        .environment(Theme())
}
