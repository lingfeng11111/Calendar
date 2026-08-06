import SwiftUI

enum PersonalDateEditorKind: String, CaseIterable, Identifiable {
    case vacationPeriod
    case specialDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vacationPeriod:
            "假期区间"
        case .specialDay:
            "特殊日期"
        }
    }
}

enum PersonalDateEditorItem: Identifiable {
    case new(PersonalDateEditorKind)
    case period(VacationPeriod)
    case specialDay(SpecialDay)

    var id: String {
        switch self {
        case let .new(kind):
            "new-\(kind.rawValue)"
        case let .period(period):
            "period-\(period.id.uuidString)"
        case let .specialDay(specialDay):
            "special-\(specialDay.id.uuidString)"
        }
    }

    var kind: PersonalDateEditorKind {
        switch self {
        case let .new(kind):
            kind
        case .period:
            .vacationPeriod
        case .specialDay:
            .specialDay
        }
    }

    var isEditing: Bool {
        switch self {
        case .new:
            false
        case .period, .specialDay:
            true
        }
    }
}

enum PersonalDateEditorValue {
    case period(VacationPeriod)
    case specialDay(SpecialDay)
}

@MainActor
struct PersonalDateEditorSheet: View {
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss

    private let item: PersonalDateEditorItem
    private let onSave: (PersonalDateEditorValue) -> String?
    private let onDelete: (() -> Void)?

    @State private var kind: PersonalDateEditorKind
    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var anchorDate: Date
    @State private var recurrence: SpecialDayRecurrence
    @State private var color: PersonalDateColor
    @State private var note: String
    @State private var validationMessage: String?

    init(
        item: PersonalDateEditorItem,
        onSave: @escaping (PersonalDateEditorValue) -> String?,
        onDelete: (() -> Void)? = nil
    ) {
        self.item = item
        self.onSave = onSave
        self.onDelete = onDelete

        let values = Self.initialValues(for: item)
        _kind = State(initialValue: item.kind)
        _title = State(initialValue: values.title)
        _startDate = State(initialValue: values.startDate)
        _endDate = State(initialValue: values.endDate)
        _anchorDate = State(initialValue: values.anchorDate)
        _recurrence = State(initialValue: values.recurrence)
        _color = State(initialValue: values.color)
        _note = State(initialValue: values.note)
        _periodKind = State(initialValue: values.periodKind)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !item.isEditing {
                        typeCard
                    }

                    commonCard

                    if kind == .vacationPeriod {
                        periodCard
                    } else {
                        specialDayCard
                    }

                    noteCard

                    if let onDelete {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Label("删除此日期", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("vacation.editor.delete")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(theme.backgroundPrimary)
            .safeAreaPadding(.bottom, 16)
            .navigationTitle(item.isEditing ? "编辑\(item.kind.title)" : "新建\(kind.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .accessibilityIdentifier("vacation.editor.cancel")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("vacation.editor.save")
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
            .accessibilityIdentifier("vacation.editor")
        }
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .environment(\.calendar, displayCalendar)
    }

    private var typeCard: some View {
        editorCard(title: "日期类型", systemImage: "square.grid.2x2") {
            Picker("日期类型", selection: $kind) {
                ForEach(PersonalDateEditorKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("vacation.editor.kind")
        }
    }

    private var commonCard: some View {
        editorCard(title: "基本信息", systemImage: "pencil") {
            TextField("名称，例如寒假或生日", text: $title)
                .textInputAutocapitalization(.never)
                .submitLabel(.next)
                .accessibilityIdentifier("vacation.editor.title")

            Divider()

            Picker("颜色", selection: $color) {
                ForEach(PersonalDateColor.allCases) { color in
                    Text(color.displayName).tag(color)
                }
            }
            .accessibilityIdentifier("vacation.editor.color")
        }
    }

    private var periodCard: some View {
        editorCard(title: "假期安排", systemImage: "calendar") {
            Picker("假期类型", selection: periodKindBinding) {
                ForEach(VacationKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .accessibilityIdentifier("vacation.editor.period.kind")

            DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                .onChange(of: startDate) { _, newValue in
                    if endDate < newValue {
                        endDate = newValue
                    }
                }
                .accessibilityIdentifier("vacation.editor.period.start")

            DatePicker("结束日期", selection: $endDate, in: startDate..., displayedComponents: .date)
                .accessibilityIdentifier("vacation.editor.period.end")
        }
    }

    private var specialDayCard: some View {
        editorCard(title: "日期安排", systemImage: "sparkles") {
            DatePicker("日期", selection: $anchorDate, displayedComponents: .date)
                .accessibilityIdentifier("vacation.editor.special.date")

            Picker("重复", selection: $recurrence) {
                Text(SpecialDayRecurrence.none.displayName)
                    .tag(SpecialDayRecurrence.none)
                Text(SpecialDayRecurrence.yearlyGregorian.displayName)
                    .tag(SpecialDayRecurrence.yearlyGregorian)
            }
            .accessibilityIdentifier("vacation.editor.special.recurrence")
        }
    }

    private var noteCard: some View {
        editorCard(title: "备注", systemImage: "note.text") {
            TextField("可选", text: $note, axis: .vertical)
                .lineLimit(2...5)
                .accessibilityIdentifier("vacation.editor.note")
        }
    }

    private var periodKindBinding: Binding<VacationKind> {
        Binding(
            get: { periodKind },
            set: { periodKind = $0 }
        )
    }

    @State private var periodKind: VacationKind = .custom

    private func save() {
        validationMessage = nil

        do {
            switch kind {
            case .vacationPeriod:
                let startDay = DayID(startDate, timeZone: DayID.defaultTimeZone)
                let endDay = DayID(endDate, timeZone: DayID.defaultTimeZone)

                let existingID: UUID
                if case let .period(period) = item {
                    existingID = period.id
                } else {
                    existingID = UUID()
                }

                let period = try VacationPeriod(
                    id: existingID,
                    title: title,
                    kind: periodKind,
                    startDay: startDay,
                    endDay: endDay,
                    color: color,
                    note: note
                )

                if let message = onSave(.period(period)) {
                    validationMessage = message
                } else {
                    dismiss()
                }
            case .specialDay:
                let anchorDay = DayID(anchorDate, timeZone: DayID.defaultTimeZone)

                let existingID: UUID
                if case let .specialDay(specialDay) = item {
                    existingID = specialDay.id
                } else {
                    existingID = UUID()
                }

                let specialDay = try SpecialDay(
                    id: existingID,
                    title: title,
                    anchorDay: anchorDay,
                    recurrence: recurrence,
                    color: color,
                    note: note
                )

                if let message = onSave(.specialDay(specialDay)) {
                    validationMessage = message
                } else {
                    dismiss()
                }
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

    private static func initialValues(for item: PersonalDateEditorItem) -> (
        title: String,
        startDate: Date,
        endDate: Date,
        anchorDate: Date,
        recurrence: SpecialDayRecurrence,
        color: PersonalDateColor,
        note: String,
        periodKind: VacationKind
    ) {
        let now = Date.now
        switch item {
        case let .new(kind):
            return (
                title: "",
                startDate: now,
                endDate: now,
                anchorDate: now,
                recurrence: kind == .specialDay ? .none : .none,
                color: kind == .specialDay ? .purple : .teal,
                note: "",
                periodKind: .custom
            )
        case let .period(period):
            return (
                title: period.title,
                startDate: period.startDay.date ?? now,
                endDate: period.endDay.date ?? now,
                anchorDate: period.startDay.date ?? now,
                recurrence: .none,
                color: period.color,
                note: period.note ?? "",
                periodKind: period.kind
            )
        case let .specialDay(specialDay):
            return (
                title: specialDay.title,
                startDate: specialDay.anchorDay.date ?? now,
                endDate: specialDay.anchorDay.date ?? now,
                anchorDate: specialDay.anchorDay.date ?? now,
                recurrence: specialDay.recurrence,
                color: specialDay.color,
                note: specialDay.note ?? "",
                periodKind: .custom
            )
        }
    }
}

#Preview("新建假期") {
    PersonalDateEditorSheet(item: .new(.vacationPeriod), onSave: { _ in nil })
        .environment(Theme())
}
