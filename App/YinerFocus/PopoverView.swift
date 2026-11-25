import SwiftUI
import YinerFocusCore

struct PopoverView: View {
    @EnvironmentObject private var model: AppModel
    @State private var titleDraft = ""

    var body: some View {
        let engine = model.snapshot.engine
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                TextField("专注", text: $titleDraft)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .onSubmit { model.setTitle(titleDraft) }
                tagPicker
            }
            VStack(spacing: 4) {
                Text(formatClock(engine.remaining(at: model.now)))
                    .font(.system(size: 52, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(engine.phase == .focus ? Theme.focus : Theme.rest)
                    .frame(maxWidth: .infinity)
                Text(engine.phaseName)
                    .font(.title3)
                Text(engine.runStateName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(engine.progressText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button(engine.primaryButtonTitle) { model.toggleTimer() }
                    .buttonStyle(.borderedProminent)
                    .tint(engine.phase == .focus ? Theme.focus : Theme.rest)
                    .frame(maxWidth: .infinity)
                Button("跳过休息") { model.skipBreak() }
                    .disabled(!engine.canSkipBreak)
                    .frame(maxWidth: .infinity)
            }
            Button("重置周期") { model.resetCycle() }
                .disabled(!engine.canReset)
                .frame(maxWidth: .infinity)
            if let message = model.hideBurstMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("统计") { model.showStats() }
                Spacer()
                Button("设置") { model.showSettings() }
            }
            .buttonStyle(.borderless)
            Text("空格开始或暂停 · Esc 关闭")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(width: 320)
        .onAppear { titleDraft = engine.title }
        .onChange(of: titleDraft) { _, newValue in
            model.setTitle(newValue)
        }
        .onChange(of: engine.phase) { _, _ in
            titleDraft = model.snapshot.engine.title
        }
        .onChange(of: engine.activeID) { _, _ in
            titleDraft = model.snapshot.engine.title
        }
    }

    private var tagPicker: some View {
        Picker("标签", selection: Binding(
            get: { model.snapshot.engine.tag ?? "" },
            set: { model.setTag($0.isEmpty ? nil : $0) }
        )) {
            Text("无").tag("")
            ForEach(TagLibrary.sorted(model.snapshot.tags)) { tag in
                Text(tag.name).tag(tag.name)
            }
        }
        .labelsHidden()
        .frame(width: 96)
    }
}
