import Charts
import SwiftUI
import YinerFocusCore

struct StatsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var scope: StatsScope = .day
    @State private var metric: StatsMetric = .count
    @State private var anchor = Date()
    @State private var tag = ""
    @State private var includeIncomplete = false
    @State private var selected: FocusSession?
    @State private var showingManual = false
    @State private var pendingDelete: FocusSession?

    var body: some View {
        let zone = TimeZone.current
        let query = SessionQuery(tag: tag.isEmpty ? nil : tag, includeIncomplete: includeIncomplete)
        let active = includeIncomplete ? model.snapshot.engine.activeSession(at: model.now) : nil
        let matched = focusSessionsForStats(
            stored: model.snapshot.sessions,
            active: active,
            query: query,
            range: nil
        )
        let summary = aggregate(sessions: matched, scope: scope, anchor: anchor, timeZone: zone)
        let range = periodRange(scope: scope, anchor: anchor, timeZone: zone)
        let listed = matched.filter { range.contains(statsDate(of: $0)) }
        let preserved = preservedSessions(model.snapshot.sessions)

        VStack(alignment: .leading, spacing: 12) {
            controls(zone: zone)
            Chart(summary.buckets) { bucket in
                BarMark(
                    x: .value("时段", bucket.label),
                    y: .value(
                        metric.name,
                        metric == .count ? Double(bucket.count) : Double(bucket.durationNetSeconds) / 60
                    )
                )
                .foregroundStyle(Theme.focus)
            }
            .frame(height: 180)
            Text("本页合计 \(summary.totalCount) 次 · \(formatHMS(summary.totalDurationSeconds))")
                .font(.headline)
            List {
                if listed.isEmpty {
                    Text("这一段还没有专注记录。")
                        .foregroundStyle(.secondary)
                }
                ForEach(listed) { session in
                    Button {
                        selected = session
                    } label: {
                        SessionRow(session: session)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !preserved.isEmpty {
                Text("另有 \(preserved.count) 条导入记录的类型不是专注，没有算进上面的图。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("补记") { showingManual = true }
                Button("导入 CSV") { model.importWithPanel() }
                Button("导出 CSV") { model.exportWithPanel() }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $selected) { session in
            SessionDetail(session: session) {
                pendingDelete = session
            }
            .environmentObject(model)
        }
        .sheet(isPresented: $showingManual) {
            ManualEntrySheet()
                .environmentObject(model)
        }
        .confirmationDialog(
            "删除这场会话？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let pendingDelete {
                    model.deleteSession(id: pendingDelete.id)
                }
                selected = nil
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        }
        .alert("结果", isPresented: Binding(
            get: { model.importSummary != nil },
            set: { if !$0 { model.importSummary = nil } }
        )) {
            Button("好", role: .cancel) { model.importSummary = nil }
        } message: {
            Text(model.importSummary ?? "")
        }
    }

    private func controls(zone: TimeZone) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("范围", selection: $scope) {
                    ForEach(StatsScope.allCases, id: \.self) { item in
                        Text(item.name).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                Picker("指标", selection: $metric) {
                    ForEach(StatsMetric.allCases, id: \.self) { item in
                        Text(item.name).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }
            HStack {
                Button("上一页") {
                    anchor = shifting(anchor: anchor, scope: scope, by: -1, timeZone: zone)
                }
                Button("下一页") {
                    anchor = shifting(anchor: anchor, scope: scope, by: 1, timeZone: zone)
                }
                if !isCurrentPeriod(scope: scope, anchor: anchor, now: model.now, timeZone: zone) {
                    Button("回到今天") { anchor = Date() }
                }
                Spacer()
                Picker("标签", selection: $tag) {
                    Text("全部").tag("")
                    ForEach(TagLibrary.sorted(model.snapshot.tags)) { item in
                        Text(item.name).tag(item.name)
                    }
                }
                .frame(width: 160)
                Toggle("显示未完成", isOn: $includeIncomplete)
            }
        }
    }
}

private struct SessionRow: View {
    let session: FocusSession

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title.isEmpty ? "专注" : session.title)
                Text(timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !session.tag.isEmpty {
                Text(session.tag)
                    .font(.caption)
            }
            if !session.status.isComplete {
                Text(session.status.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(formatHMS(session.durationNetSeconds))
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private var timeText: String {
        let zone = TimeZone.current
        let start = WallTime.format(date: session.startedAt, timeZone: zone)
        guard let end = session.completedAt else { return start }
        return "\(start) – \(WallTime.format(date: end, timeZone: zone))"
    }
}

private struct SessionDetail: View {
    @Environment(\.dismiss) private var dismiss
    let session: FocusSession
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.title.isEmpty ? "专注" : session.title)
                .font(.title2)
            labeled("状态", session.status.name)
            labeled("类型", session.kind.name)
            labeled("标签", session.tag.isEmpty ? "无" : session.tag)
            labeled("净时长", formatHMS(session.durationNetSeconds))
            labeled("含中断", formatHMS(session.durationGrossSeconds))
            labeled("开始", WallTime.format(date: session.startedAt, timeZone: .current))
            if let end = session.completedAt {
                labeled("完成", WallTime.format(date: end, timeZone: .current))
            }
            Text(session.id)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                Button("删除", role: .destructive, action: onDelete)
                Spacer()
                Button("关闭") { dismiss() }
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }
}

private struct ManualEntrySheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var tag = ""
    @State private var started = Date().addingTimeInterval(-25 * 60)
    @State private var ended = Date()
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("补记一场已完成的专注")
                .font(.title3)
            TextField("标题，可以空着", text: $title)
            Picker("标签", selection: $tag) {
                Text("无").tag("")
                ForEach(TagLibrary.sorted(model.snapshot.tags)) { item in
                    Text(item.name).tag(item.name)
                }
            }
            DatePicker("开始", selection: $started)
            DatePicker("结束", selection: $ended)
            Text("补记按墙钟计算，净时长和含中断时长相同。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("保存") {
                    if let message = model.addManual(
                        title: title,
                        tag: tag,
                        startedAt: started,
                        completedAt: ended
                    ) {
                        error = message
                    } else {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.focus)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            ended = Date()
            started = ended.addingTimeInterval(-25 * 60)
        }
    }
}
