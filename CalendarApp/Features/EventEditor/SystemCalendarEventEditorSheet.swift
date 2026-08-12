import Observation
import SwiftUI

enum SystemCalendarEventEditorState: Equatable, Sendable {
    case idle
    case requestingAccess
    case loadingCalendars
    case ready
    case saving
    case unavailable
    case failed
}

@MainActor
@Observable
final class SystemCalendarEventEditorFeatureModel {
    @ObservationIgnored let service: (any SystemCalendarServiceProtocol)?

    var access: SystemCalendarAccess
    var state: SystemCalendarEventEditorState = .idle
    var calendars: [SystemCalendarDescriptor] = []
    var selectedCalendarID: String?
    var errorMessage: String?

    init(service: (any SystemCalendarServiceProtocol)?) {
        self.service = service
        self.access = service?.access ?? .unavailable
    }

    func load() async {
        guard let service else {
            access = .unavailable
            state = .unavailable
            errorMessage = SystemCalendarWriteError.unavailable.localizedDescription
            return
        }

        access = service.access
        guard access == .fullAccess || access == .writeOnly else {
            state = access == .unavailable ? .unavailable : .idle
            errorMessage = nil
            calendars = []
            selectedCalendarID = nil
            return
        }

        state = .loadingCalendars
        errorMessage = nil

        do {
            calendars = try await service.writableCalendars()
            selectedCalendarID = selectedCalendarID.flatMap { selectedID in
                calendars.contains { $0.identifier == selectedID } ? selectedID : nil
            } ?? calendars.first?.identifier
            state = calendars.isEmpty ? .failed : .ready
            if calendars.isEmpty {
                errorMessage = SystemCalendarWriteError.noWritableCalendar.localizedDescription
            }
        } catch is CancellationError {
            return
        } catch let error as LocalizedError {
            calendars = []
            selectedCalendarID = nil
            state = .failed
            errorMessage = error.errorDescription ?? SystemCalendarWriteError.saveFailed.localizedDescription
        } catch {
            calendars = []
            selectedCalendarID = nil
            state = .failed
            errorMessage = SystemCalendarWriteError.saveFailed.localizedDescription
        }
    }

    func requestWriteAccess() async {
        guard let service else {
            access = .unavailable
            state = .unavailable
            errorMessage = SystemCalendarWriteError.unavailable.localizedDescription
            return
        }

        state = .requestingAccess
        errorMessage = nil
        access = await service.requestWriteAccess()

        if access == .fullAccess || access == .writeOnly {
            await load()
        } else if access == .unavailable {
            state = .unavailable
        } else {
            state = .failed
            errorMessage = writeAccessMessage
        }
    }

    func save(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        note: String
    ) async -> Bool {
        guard let service else {
            state = .unavailable
            errorMessage = SystemCalendarWriteError.unavailable.localizedDescription
            return false
        }
        guard let selectedCalendarID else {
            state = .failed
            errorMessage = SystemCalendarWriteError.noWritableCalendar.localizedDescription
            return false
        }

        do {
            let draft = try SystemCalendarEventDraft(
                title: title,
                startDate: startDate,
                endDate: endDate,
                isAllDay: isAllDay,
                note: note
            )
            state = .saving
            errorMessage = nil
            try await service.createEvent(draft, calendarID: selectedCalendarID)
            state = .ready
            return true
        } catch is CancellationError {
            return false
        } catch let error as LocalizedError {
            state = .ready
            errorMessage = error.errorDescription ?? SystemCalendarWriteError.saveFailed.localizedDescription
            return false
        } catch {
            state = .ready
            errorMessage = SystemCalendarWriteError.saveFailed.localizedDescription
            return false
        }
    }

    var canRequestWriteAccess: Bool {
        access == .notDetermined || access == .denied
    }

    private var writeAccessMessage: String {
        switch access {
        case .denied:
            "系统日历写入权限已关闭，请在系统设置中重新开启。"
        case .restricted:
            SystemCalendarWriteError.accessRestricted.localizedDescription
        case .notDetermined:
            "尚未获得系统日历写入权限。"
        case .unavailable:
            SystemCalendarWriteError.unavailable.localizedDescription
        case .writeOnly, .fullAccess:
            "系统日历写入权限不可用。"
        }
    }
}

@MainActor
struct SystemCalendarEventEditorSheet: View {
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss

    private let dayID: DayID
    @State private var model: SystemCalendarEventEditorFeatureModel
    @State private var title: String = ""
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isAllDay = false
    @State private var note = ""

    init(
        dayID: DayID,
        systemCalendarService: (any SystemCalendarServiceProtocol)?
    ) {
        self.dayID = dayID
        _model = State(
            initialValue: SystemCalendarEventEditorFeatureModel(
                service: systemCalendarService
            )
        )

        let dayStart = dayID.date ?? .now
        _startDate = State(initialValue: dayStart.addingTimeInterval(9 * 60 * 60))
        _endDate = State(initialValue: dayStart.addingTimeInterval(10 * 60 * 60))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.state == .ready || model.state == .saving {
                        eventCard
                        calendarCard
                    } else {
                        accessCard
                    }

                    if let errorMessage = model.errorMessage,
                       model.state == .ready || model.state == .failed {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(theme.labelSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("system.calendar.editor.error")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(theme.backgroundPrimary)
            .safeAreaPadding(.bottom, 16)
            .navigationTitle("新建系统事件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .accessibilityIdentifier("system.calendar.editor.cancel")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("写入") {
                        Task {
                            let didSave = await model.save(
                                title: title,
                                startDate: normalizedStartDate,
                                endDate: normalizedEndDate,
                                isAllDay: isAllDay,
                                note: note
                            )
                            if didSave {
                                dismiss()
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(model.state != .ready || model.selectedCalendarID == nil)
                    .accessibilityIdentifier("system.calendar.editor.save")
                }
            }
            .task {
                await model.load()
            }
            .accessibilityIdentifier("system.calendar.editor")
        }
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .environment(\.calendar, displayCalendar)
    }

    private var accessCard: some View {
        editorCard(title: "系统日历权限", systemImage: "calendar.badge.checkmark") {
            switch model.state {
            case .loadingCalendars:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在读取可写入的日历")
                        .foregroundStyle(theme.labelSecondary)
                }
            case .requestingAccess:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在请求写入权限")
                        .foregroundStyle(theme.labelSecondary)
                }
            case .unavailable:
                Text("当前构建没有可用的系统日历服务。")
                    .foregroundStyle(theme.labelSecondary)
            case .failed:
                Text(model.errorMessage ?? "系统日历写入准备失败")
                    .foregroundStyle(theme.labelSecondary)

                Button("重新读取可写日历") {
                    Task { await model.load() }
                }
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("system.calendar.editor.retry")
            default:
                Text("写入前需要获得系统日历权限。应用只会创建你提交的事件，不会修改本地日程。")
                    .font(.subheadline)
                    .foregroundStyle(theme.labelSecondary)

                Button("允许写入系统日历") {
                    Task { await model.requestWriteAccess() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canRequestWriteAccess)
                .accessibilityIdentifier("system.calendar.editor.permission")
            }
        }
    }

    private var eventCard: some View {
        editorCard(title: "事件信息", systemImage: "calendar.badge.plus") {
            TextField("标题，例如项目评审", text: $title)
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("system.calendar.editor.title")

            Toggle("全天事件", isOn: $isAllDay)
                .onChange(of: isAllDay) { _, newValue in
                    guard newValue else { return }
                    startDate = displayCalendar.startOfDay(for: startDate)
                    endDate = displayCalendar.startOfDay(for: endDate)
                    if endDate < startDate {
                        endDate = startDate
                    }
                }
                .accessibilityIdentifier("system.calendar.editor.allDay")

            DatePicker(
                "开始\(isAllDay ? "日期" : "时间")",
                selection: $startDate,
                displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
            )
            .onChange(of: startDate) { _, newValue in
                if endDate < newValue {
                    endDate = newValue.addingTimeInterval(60 * 60)
                }
            }
            .accessibilityIdentifier("system.calendar.editor.start")

            DatePicker(
                "结束\(isAllDay ? "日期" : "时间")",
                selection: Binding(
                    get: { endDate },
                    set: { endDate = max($0, startDate) }
                ),
                in: startDate...,
                displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("system.calendar.editor.end")

            TextField("备注（可选）", text: $note, axis: .vertical)
                .lineLimit(2...5)
                .accessibilityIdentifier("system.calendar.editor.note")
        }
    }

    private var calendarCard: some View {
        editorCard(title: "目标日历", systemImage: "calendar") {
            Picker(
                "写入到",
                selection: Binding(
                    get: { model.selectedCalendarID ?? "" },
                    set: { model.selectedCalendarID = $0 }
                )
            ) {
                ForEach(model.calendars) { calendar in
                    Text("\(calendar.title) · \(calendar.displaySourceTitle)")
                        .tag(calendar.identifier)
                }
            }
            .accessibilityIdentifier("system.calendar.editor.calendar")

            Text(
                model.access == .writeOnly
                    ? "当前使用系统默认新建日历，应用不会读取已有事件。"
                    : "事件只会写入你选择的可写日历。"
            )
            .font(.footnote)
            .foregroundStyle(theme.labelSecondary)
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

    private var normalizedStartDate: Date {
        isAllDay ? displayCalendar.startOfDay(for: startDate) : startDate
    }

    private var normalizedEndDate: Date {
        isAllDay ? displayCalendar.startOfDay(for: endDate) : endDate
    }

    private var displayCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = DayID.defaultTimeZone
        return calendar
    }
}

#Preview("系统事件创建") {
    SystemCalendarEventEditorSheet(
        dayID: DayID(year: 2026, month: 1, day: 2)!,
        systemCalendarService: FixtureSystemCalendarService()
    )
    .environment(Theme())
}
