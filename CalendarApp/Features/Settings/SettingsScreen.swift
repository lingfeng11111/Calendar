import SwiftUI

@MainActor
struct SettingsScreen: View {
    @State private var model: SettingsFeatureModel

    init(systemCalendarService: (any SystemCalendarServiceProtocol)? = nil) {
        _model = State(
            initialValue: SettingsFeatureModel(systemCalendarService: systemCalendarService)
        )
    }

    var body: some View {
        Form {
            Section("项目状态") {
                LabeledContent("阶段", value: "阶段 6：系统日历只读同步")
                LabeledContent("最低系统", value: "iOS 18")
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
                }
                .accessibilityIdentifier("settings.systemCalendar")
            }

            Section("后续能力") {
                LabeledContent("节假日数据", value: "已接入远程与缓存")
                LabeledContent("系统事件写入", value: "后续阶段接入")
            }
        }
        .navigationTitle("设置")
        .accessibilityIdentifier("screen.settings")
        .task {
            model.refreshSystemCalendarAccess()
        }
    }

    private var systemCalendarDescription: String {
        switch model.systemCalendarAccess {
        case .unavailable:
            "当前构建没有可用的系统日历服务。"
        case .notDetermined:
            "授权后仅读取已有系统事件，不会修改本地日程。"
        case .restricted:
            "系统限制了日历访问，无法在此设备上更改。"
        case .denied:
            "访问已关闭，可在系统设置中重新开启。"
        case .writeOnly:
            "当前授权只允许写入，读取事件需要完整访问权限。"
        case .fullAccess:
            "已获得完整读取权限，系统事件将保持只读来源。"
        }
    }
}

#Preview("设置") {
    NavigationStack {
        SettingsScreen()
    }
}
