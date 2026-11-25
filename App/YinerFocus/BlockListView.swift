import SwiftUI
import YinerFocusCore

struct BlockListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 1
    @State private var draft = ""
    @State private var selectedWeb: String?
    @State private var selectedApp: String?
    @State private var showHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("返回") { dismiss() }
                    .buttonStyle(.borderless)
                Spacer()
                Picker("名单", selection: $tab) {
                    Text("应用").tag(0)
                    Text("网页").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                Spacer()
                Color.clear.frame(width: 44)
            }
            if tab == 0 {
                appPage
            } else {
                webPage
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .navigationTitle("应用与网页屏蔽")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showHelp) {
            ScrollView {
                Text(BlockListHelp.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            }
            .frame(width: 460, height: 520)
        }
    }

    private var webPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("输入要拦截的网站", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addRule)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if model.snapshot.webRules.isEmpty {
                        Text("名单还是空的。")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                    ForEach(model.snapshot.webRules) { rule in
                        selectableRow(title: rule.pattern, subtitle: nil, selected: selectedWeb == rule.id) {
                            selectedWeb = rule.id
                        }
                    }
                }
            }
            .frame(minHeight: 180)
            HStack {
                Button("添加", action: addRule)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("删除") {
                    if let selectedWeb {
                        model.removeWebRules(ids: [selectedWeb])
                        self.selectedWeb = nil
                    }
                }
                .disabled(selectedWeb == nil)
                Spacer()
                Picker("模式", selection: model.binding(\.webMode)) {
                    Text("阻止").tag(WebListMode.block)
                    Text("允许").tag(WebListMode.allow)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                Text(browserSelectionSummary(selected: model.settings.enabledBrowsers))
                    .foregroundStyle(.secondary)
                Button("说明") { showHelp = true }
            }
            Text(model.settings.webMode == .block
                 ? "阻止：名单里的网站会被换成拦截页。"
                 : "允许：不在名单里的网站会被换成拦截页。两种模式共用这一份名单。")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(KnownBrowser.allCases) { browser in
                    Toggle(browser.displayName, isOn: Binding(
                        get: { model.settings.enabledBrowsers.contains(browser) },
                        set: { model.setBrowser(browser, enabled: $0) }
                    ))
                    if let message = model.browserMessages[browser.rawValue], !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Toggle(YinerDefaults.pendingBrowserTitle, isOn: .constant(false))
                    .disabled(true)
                Text("这一项还没确认，不会去控制它。也不支持 Firefox。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("专注进行中，点开下面的应用会立刻退到后台，进程不会被结束。这里只有阻止名单，没有「只允许这些应用」。")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if model.snapshot.appRules.isEmpty {
                        Text("还没有应用。")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                    ForEach(model.snapshot.appRules) { rule in
                        selectableRow(
                            title: rule.displayName,
                            subtitle: rule.bundleID,
                            selected: selectedApp == rule.bundleID
                        ) {
                            selectedApp = rule.bundleID
                        }
                    }
                }
            }
            .frame(minHeight: 180)
            HStack {
                Button("从本机应用添加") { model.pickApplications() }
                Button("删除") {
                    if let selectedApp {
                        model.removeApps(ids: [selectedApp])
                        self.selectedApp = nil
                    }
                }
                .disabled(selectedApp == nil)
            }
            Text("未选中时不能删除。请不要加入系统关键应用。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let message = model.hideBurstMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func selectableRow(
        title: String,
        subtitle: String?,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selected {
                    Text("已选")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.primary.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addRule() {
        let created = model.addWebRule(draft)
        if created { draft = "" }
    }
}

enum BlockListHelp {
    static let text = """
    规则
    普通条目按「包含」匹配，不区分大小写，不必写 http 或 www。例如 x.com 会拦下地址里含有这段文字的网页。
    以 * 开头表示精确地址。比较时会去掉这一个星号，再和完整网址对照；末尾多一个斜线也算同一个地址。相近的子域、更长的路径或查询串都不会被算进去。

    只在专注倒计时进行中生效。暂停、待开始和休息时，新打开的页面不会再被替换。已经显示拦截页的标签不会自动改回去。

    局限
    需要你在系统设置里允许本应用控制每一个选中的浏览器。拒绝的浏览器不会被拦截，上面会写出原因。
    打开被拦网页时，原页面可能闪一下。
    浏览器或系统升级后，需要再确认拦截是否还有效。
    无痕窗口或特殊配置文件有时读不到。
    点返回若回到被拦地址，会再次被换成这一页。
    没被选中、没授权的浏览器，以及别的应用里内嵌的网页，拦不住。
    名为 Cra 的浏览器还没确认，目前不会对它生效。
    这不是系统级网络拦截，浏览器以外的地方访问同一网站不会被拦住。
    """
}
