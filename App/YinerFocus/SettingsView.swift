import SwiftUI
import YinerFocusCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showBlocklist = false
    @State private var confirmReset = false
    @State private var confirmResetAgain = false
    @State private var newTagName = ""

    var body: some View {
        NavigationStack {
            Form {
                durationSection
                autoSection
                notifySection
                launchSection
                windowSection
                appearanceSection
                tagSection
                blockSection
                calendarSection
                dataSection
                hotkeySection
                aboutSection
            }
            .formStyle(.grouped)
            .navigationTitle("设置")
            .navigationDestination(isPresented: $showBlocklist) {
                BlockListView()
            }
        }
        .frame(minWidth: 520, minHeight: 640)
        .alert("结果", isPresented: summaryPresented) {
            Button("好", role: .cancel) { model.importSummary = nil }
        } message: {
            Text(model.importSummary ?? "")
        }
        .alert("删除全部会话？", isPresented: $confirmReset) {
            Button("取消", role: .cancel) {}
            Button("继续") { confirmResetAgain = true }
        } message: {
            Text("统计里的会话会被删掉，而且不能撤销。设置、标签和屏蔽名单会留下。")
        }
        .alert("再确认一次", isPresented: $confirmResetAgain) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { model.resetStatistics() }
        } message: {
            Text("删除后无法恢复。")
        }
    }

    private var summaryPresented: Binding<Bool> {
        Binding(
            get: { model.importSummary != nil },
            set: { if !$0 { model.importSummary = nil } }
        )
    }

    private var durationSection: some View {
        Section("时长") {
            durationRow("专注", presets: YinerDefaults.focusPresetMinutes, keyPath: \.focusMinutes)
            durationRow("短休息", presets: YinerDefaults.shortBreakPresetMinutes, keyPath: \.shortBreakMinutes)
            durationRow("长休息", presets: YinerDefaults.longBreakPresetMinutes, keyPath: \.longBreakMinutes)
            Stepper(value: model.binding(\.cycleLength), in: YinerDefaults.cycleLengthRange) {
                Text("周期长度 \(model.settings.cycleLength) 次专注后进入长休息")
            }
            Text("预设之外，也可以把时长调到 1 至 90 分钟。正在计时的这一段不会中途改长度，下一场待开始的阶段才会用新时长。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var autoSection: some View {
        Section("自动开始") {
            Toggle("专注结束后自动开始休息", isOn: model.binding(\.autoStartBreak))
            Toggle("休息结束后自动开始专注", isOn: model.binding(\.autoStartFocus))
        }
    }

    private var notifySection: some View {
        Section("通知") {
            Toggle("专注结束时通知", isOn: Binding(
                get: { model.settings.notifyFocusEnd },
                set: { model.setNotifyFocus($0) }
            ))
            Toggle("休息结束时通知", isOn: Binding(
                get: { model.settings.notifyBreakEnd },
                set: { model.setNotifyBreak($0) }
            ))
            if model.notificationDenied {
                Text("通知权限已被拒绝。请到系统设置 › 通知，允许银耳专注。")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var launchSection: some View {
        Section("启动") {
            Toggle("登录时启动", isOn: model.binding(\.launchAtLogin))
            Toggle("启动时显示主弹窗", isOn: model.binding(\.showPopoverAtLaunch))
            Toggle("启动时重置周期", isOn: model.binding(\.resetCycleAtLaunch))
            Toggle("启动时开始专注", isOn: model.binding(\.startFocusAtLaunch))
            if let message = model.loginItemMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var windowSection: some View {
        Section("窗口") {
            Toggle("计时开始后隐藏主弹窗", isOn: model.binding(\.hidePopoverWhenRunning))
            Toggle("窗口置顶", isOn: model.binding(\.windowAlwaysOnTop))
        }
    }

    private var appearanceSection: some View {
        Section("外观") {
            Picker("外观", selection: model.binding(\.appearance)) {
                ForEach(Appearance.allCases, id: \.self) { item in
                    Text(item.name).tag(item)
                }
            }
        }
    }

    private var tagSection: some View {
        Section("标签") {
            ForEach(TagLibrary.sorted(model.snapshot.tags)) { tag in
                HStack {
                    Circle()
                        .fill(TagColor.color(hex: tag.colorHex))
                        .frame(width: 12, height: 12)
                    TagNameField(tag: tag)
                    ColorPicker(
                        "颜色",
                        selection: Binding(
                            get: { TagColor.color(hex: tag.colorHex) },
                            set: { model.setTagColor(id: tag.id, hex: TagColor.hex(from: $0)) }
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    Button("上移") { model.moveTag(id: tag.id, direction: -1) }
                    Button("下移") { model.moveTag(id: tag.id, direction: 1) }
                    Button("删除") { model.deleteTag(id: tag.id) }
                }
            }
            HStack {
                TextField("新标签", text: $newTagName)
                Button("添加") {
                    let name = newTagName
                    model.addTag(name: name, colorHex: "#7A6A58")
                    if model.tagError == nil { newTagName = "" }
                }
                .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let tagError = model.tagError {
                Text(tagError).font(.caption).foregroundStyle(.red)
            }
            Text("一场专注最多选一个标签，也可以不选。改名会带到已有记录上。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var blockSection: some View {
        Section("屏蔽") {
            Button("应用与网页屏蔽") { showBlocklist = true }
            Text("只在专注进行中生效。暂停、待开始和休息时不拦截。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var calendarSection: some View {
        Section("日历") {
            Toggle("把已完成的专注写入日历", isOn: Binding(
                get: { model.settings.calendarSyncEnabled },
                set: { model.setCalendarSync($0) }
            ))
            if model.settings.calendarSyncEnabled {
                if model.calendarDenied {
                    Text("没有日历权限。请到系统设置 › 隐私与安全性 › 日历，允许银耳专注。")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Picker("日历", selection: Binding(
                        get: { model.settings.calendarIdentifier ?? "" },
                        set: { model.setCalendarIdentifier($0.isEmpty ? nil : $0) }
                    )) {
                        Text("请选择").tag("")
                        ForEach(model.calendars) { calendar in
                            Text(calendar.title).tag(calendar.id)
                        }
                    }
                }
                if let error = model.calendarWriteError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Text("事件从这场专注的开始记到完成。有标签且没有标题时，标题是「专注 · 标签」。休息不写入。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dataSection: some View {
        Section("数据") {
            Button("导入 CSV") { model.importWithPanel() }
            Button("导出 CSV") { model.exportWithPanel() }
            Button("重置全部统计") { confirmReset = true }
            Text("重置只删除会话记录。相同 ID 再次导入会跳过，不会覆盖已经改过的记录。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var hotkeySection: some View {
        Section("全局快捷键") {
            Toggle("全局快捷键", isOn: .constant(false))
                .disabled(true)
            Text("入口先留着。具体按键还没定，所以现在不能打开。主弹窗获得焦点时，空格开始或暂停，Esc 关闭。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            LabeledContent("应用", value: YinerDefaults.appName)
            LabeledContent(
                "版本",
                value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                    ?? YinerDefaults.marketingVersion
            )
            Text("只在这台 Mac 上运行，不连接服务器，也不做多设备同步。")
            Text("数据在「~/Library/Application Support/YinerFocus/store.json」。复制备份这个文件即可。")
            Text("源码归银耳所有。仓库公开后再补地址。")
            Text("今日统计小组件读取 App Group「\(YinerDefaults.appGroupIdentifier)」。签名描述文件里要包含这个组，桌面上的数字才会跟着变。应用里的统计不依赖它。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let loadError = model.loadError {
                Text(loadError).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func durationRow(
        _ title: String,
        presets: [Int],
        keyPath: WritableKeyPath<FocusSettings, Int>
    ) -> some View {
        let minutes = model.settings[keyPath: keyPath]
        return LabeledContent(title) {
            HStack {
                Picker(title, selection: model.binding(keyPath)) {
                    if !presets.contains(minutes) {
                        Text("自定义 \(minutes) 分钟").tag(minutes)
                    }
                    ForEach(presets, id: \.self) { value in
                        Text("\(value) 分钟").tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                Stepper(value: model.binding(keyPath), in: YinerDefaults.durationMinuteRange) {
                    Text("\(minutes) 分钟")
                }
                .frame(width: 130)
            }
        }
    }
}

private struct TagNameField: View {
    @EnvironmentObject private var model: AppModel
    let tag: FocusTag
    @State private var draft: String

    init(tag: FocusTag) {
        self.tag = tag
        _draft = State(initialValue: tag.name)
    }

    var body: some View {
        TextField("名称", text: $draft)
            .onSubmit {
                model.renameTag(id: tag.id, to: draft)
                if model.tagError != nil {
                    draft = tag.name
                }
            }
    }
}
