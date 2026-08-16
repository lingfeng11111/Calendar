import SwiftUI

@MainActor
struct SettingsScreen: View {
    @State private var model: SettingsFeatureModel

    init(
        systemCalendarService: (any SystemCalendarServiceProtocol)? = nil,
        systemCalendarSelectionStore: (any SystemCalendarSelectionStoreProtocol)? = nil,
        notificationService: (any NotificationServiceProtocol)? = nil,
        holidayRepository: (any HolidayRepositoryProtocol)? = nil,
        vacationRepository: (any VacationRepositoryProtocol)? = nil,
        scheduleRepository: (any ScheduleRepositoryProtocol)? = nil,
        dateKnowledgeRepository: (any DateKnowledgeRepositoryProtocol)? = nil,
        notificationPreferencesStore: (any NotificationPreferencesStoreProtocol)? = nil
    ) {
        _model = State(
            initialValue: SettingsFeatureModel(
                systemCalendarService: systemCalendarService,
                systemCalendarSelectionStore: systemCalendarSelectionStore,
                notificationService: notificationService,
                holidayRepository: holidayRepository,
                vacationRepository: vacationRepository,
                scheduleRepository: scheduleRepository,
                dateKnowledgeRepository: dateKnowledgeRepository,
                notificationPreferencesStore: notificationPreferencesStore
            )
        )
    }

    var body: some View {
        let dateKnowledgeDiagnostics = model.dateKnowledgeDiagnostics

        Form {
            Section("项目状态") {
                LabeledContent("阶段", value: "阶段 7.5：日期知识来源诊断")
                LabeledContent("最低系统", value: "iOS 17")
            }

            Section("系统日历") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("访问状态")
                        Spacer(minLength: 12)
                        Text(model.systemCalendarAccess.displayName)
                            .multilineTextAlignment(.trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("访问状态，\(model.systemCalendarAccess.displayName)")
                    .accessibilityIdentifier("settings.systemCalendar.status")

                    Text(systemCalendarDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if model.systemCalendarAccess == .notDetermined {
                        Button {
                            Task { await model.requestSystemCalendarReadAccess() }
                        } label: {
                            if model.systemCalendarState == .requesting {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("允许读取系统日历")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.systemCalendarState == .requesting)
                        .accessibilityIdentifier("settings.systemCalendar.request")
                    }

                    if model.systemCalendarState == .failed {
                        Text(model.errorMessage ?? "系统日历来源读取失败")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button("重新读取日历来源") {
                            Task { await model.loadSystemCalendarConfiguration() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("settings.systemCalendar.retry")
                    } else if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("settings.systemCalendar")
            }

            if model.systemCalendarAccess == .fullAccess {
                Section("系统日历来源") {
                    LabeledContent("当前筛选", value: model.systemCalendarSelectionSummary)
                        .accessibilityIdentifier("settings.systemCalendar.selectionSummary")

                    if model.systemCalendarState == .loading {
                        ProgressView("正在读取日历来源")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if model.systemCalendarCalendars.isEmpty {
                        Text("没有可用的系统日历来源。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.systemCalendarCalendars) { calendar in
                            Toggle(
                                isOn: Binding(
                                    get: { model.isSystemCalendarSelected(calendar.identifier) },
                                    set: { model.setSystemCalendarSelected($0, for: calendar.identifier) }
                                )
                            ) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(calendar.title)
                                    Text(calendar.displaySourceTitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityIdentifier("settings.systemCalendar.calendar.\(calendar.identifier)")
                        }

                        Button("显示全部日历") {
                            model.selectAllSystemCalendars()
                        }
                        .accessibilityIdentifier("settings.systemCalendar.selectAll")
                    }
                }
            }

            Section("通知") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("授权状态")
                        Spacer(minLength: 12)
                        Text(model.notificationAuthorization.displayName)
                            .multilineTextAlignment(.trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("授权状态，\(model.notificationAuthorization.displayName)")
                    .accessibilityIdentifier("settings.notifications.status")

                    Text(notificationDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if model.notificationAuthorization == .notDetermined {
                        Button {
                            Task { await model.requestNotificationAuthorization() }
                        } label: {
                            if model.notificationState == .requesting {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("允许发送通知")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.notificationState == .requesting)
                        .accessibilityIdentifier("settings.notifications.request")
                    }

                    if let notificationErrorMessage = model.notificationErrorMessage {
                        Text(notificationErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings.notifications.error")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("settings.notifications")
            }

            Section("提醒规则") {
                ForEach(CalendarNotificationKind.allCases) { kind in
                    Toggle(
                        isOn: Binding(
                            get: { model.notificationPreferences.isEnabled(kind) },
                            set: { model.setNotificationKindEnabled($0, for: kind) }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.displayName)
                            Text(notificationKindDescription(for: kind))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("settings.notifications.kind.\(kind.rawValue)")
                }

                LabeledContent("当前计划", value: model.notificationPlanSummary)
                    .accessibilityIdentifier("settings.notifications.planSummary")

                Button {
                    Task { await model.reconcileNotificationPlan() }
                } label: {
                    if model.notificationPlanState == .loading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("同步提醒计划")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(
                    !model.notificationAuthorization.canSchedule
                        || model.notificationPlanState == .loading
                )
                .accessibilityIdentifier("settings.notifications.reconcile")
            }

            Section("日期知识来源") {
                LabeledContent("读取年份", value: "\(model.dateKnowledgeYear)")

                if model.dateKnowledgeState == .loading {
                    ProgressView("正在读取来源状态")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if dateKnowledgeDiagnostics.isEmpty {
                    Text(model.dateKnowledgeErrorMessage ?? "尚未读取日期知识来源。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(dateKnowledgeDiagnostics, id: \.id) { (source: DateKnowledgeSourceDiagnostic) in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(source.displayName)
                                    .font(.body.weight(.medium))
                                Spacer(minLength: 12)
                                Text(source.state.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(source.state.isHealthy ? Color.secondary : Color.red)
                            }

                            Text("\(source.annotationCount) 条日期知识")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let fetchedAt = source.fetchedAt {
                                Text("最近获取：\(fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let sourceURL = source.sourceURL {
                                Text("来源：\(sourceURL.host ?? sourceURL.absoluteString)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let errorDescription = source.errorDescription {
                                Text(errorDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("settings.dateKnowledge.source.\(source.sourceID)")
                    }
                }

                if let dateKnowledgeErrorMessage = model.dateKnowledgeErrorMessage,
                   !dateKnowledgeDiagnostics.contains(where: { $0.errorDescription == dateKnowledgeErrorMessage }) {
                    Text(dateKnowledgeErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await model.loadDateKnowledgeDiagnostics() }
                } label: {
                    if model.dateKnowledgeState == .loading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("重新读取日期知识")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(model.dateKnowledgeState == .loading)
                .accessibilityIdentifier("settings.dateKnowledge.retry")
            }

            Section("后续能力") {
                LabeledContent("节假日数据", value: "已接入远程与缓存")
                LabeledContent("系统事件写入", value: "日期详情支持主动创建")
                LabeledContent("本地通知", value: "已接入授权与协调边界")
                LabeledContent("Widget", value: "已接入，正式签名待复验")
            }
        }
        .navigationTitle("设置")
        .accessibilityIdentifier("screen.settings")
        .task {
            await model.loadSystemCalendarConfiguration()
            await model.loadNotificationAuthorization()
            model.loadNotificationPreferences()
            Task { await model.loadDateKnowledgeDiagnostics() }
            await model.observeSystemCalendarChanges()
        }
    }

    private var systemCalendarDescription: String {
        switch model.systemCalendarAccess {
        case .unavailable:
            "当前构建没有可用的系统日历服务。"
        case .notDetermined:
            "授权后可读取已有系统事件，也可以在日期详情中主动创建系统事件。"
        case .restricted:
            "系统限制了日历访问，无法在此设备上更改。"
        case .denied:
            "访问已关闭，可在系统设置中重新开启。"
        case .writeOnly:
            "当前授权只允许写入，创建事件时使用系统默认新建日历。读取事件需要完整访问权限。"
        case .fullAccess:
            "已获得完整读取权限，可选择来源，也可以在日期详情中主动创建系统事件。"
        }
    }

    private var dateKnowledgeDiagnostics: [DateKnowledgeSourceDiagnostic] {
        model.dateKnowledgeDiagnostics
    }

    private var notificationDescription: String {
        switch model.notificationAuthorization {
        case .unavailable:
            "当前构建没有可用的通知服务。"
        case .notDetermined:
            "授权后才能安排重要日期提醒；应用不会在未开启规则时自动为所有日程排队。"
        case .denied:
            "通知已关闭，可在系统设置中重新开启。"
        case .authorized, .provisional, .ephemeral:
            "通知授权已就绪，后续提醒将由统一服务按稳定标识协调，避免重复安排。"
        }
    }

    private func notificationKindDescription(for kind: CalendarNotificationKind) -> String {
        switch kind {
        case .schedule:
            "按本地日程开始时间提醒"
        case .holiday:
            "在法定节假日开始当天提醒"
        case .makeupWorkday:
            "在调休补班当天提醒"
        case .specialDay:
            "在生日和纪念日当天提醒"
        }
    }
}

#Preview("设置") {
    NavigationStack {
        SettingsScreen()
    }
}
