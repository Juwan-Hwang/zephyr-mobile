// LogsView —— 设置 › 诊断 › 日志（REVIEW-Q2 P2“无日志/诊断 UI”）。
// 订阅 engine.logs(minLevel:)（真引擎每秒向扩展拉一次，Mock 有回放），最多保留最近 500 行；
// 级别分段切换时重新订阅；暂停只停止追加；“分享”导出纯文本（时间 级别 消息），不含任何凭据（日志由核心脱敏）。

import SwiftUI
import ZephyrDesign
import ZephyrKit
#if DEBUG
import ZephyrMock
#endif

@MainActor @Observable
final class LogsModel {
    static let capacity = 500

    let engine: any ZephyrEngine
    private(set) var lines: [LogLine] = []
    var isPaused = false
    var level: LogLevel = .info {
        didSet { if oldValue != level, task != nil { subscribe() } }
    }
    @ObservationIgnored private var task: Task<Void, Never>?

    init(engine: any ZephyrEngine) { self.engine = engine }

    func start() { if task == nil { subscribe() } }

    func stop() {
        task?.cancel()
        task = nil
    }

    func clear() { lines = [] }

    func append(_ line: LogLine) {
        guard !isPaused else { return }
        lines.append(line)
        if lines.count > Self.capacity { lines.removeFirst(lines.count - Self.capacity) }
    }

    private func subscribe() {
        task?.cancel()
        lines = []
        let stream = engine.logs(minLevel: level)
        task = Task { [weak self] in
            for await line in stream {
                guard let self, !Task.isCancelled else { return }
                self.append(line)
            }
        }
    }

    /// 导出文本：每行“HH:mm:ss.SSS W 消息”。
    func exportText(timeZone: TimeZone = .current) -> String {
        lines.map { Self.format($0, timeZone: timeZone) }.joined(separator: "\n")
    }

    nonisolated static func format(_ line: LogLine, timeZone: TimeZone = .current) -> String {
        "\(time(line.at, timeZone: timeZone)) \(badge(line.level)) \(line.message)"
    }

    nonisolated static func time(_ ms: Int64, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        let millis = Int(((ms % 1000) + 1000) % 1000)
        return String(format: "%02d:%02d:%02d.%03d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0, millis)
    }

    nonisolated static func badge(_ level: LogLevel) -> String {
        switch level {
        case .debug: "D"
        case .info: "I"
        case .warning: "W"
        case .error: "E"
        }
    }
}

@MainActor
struct LogsView: View {
    @State private var model: LogsModel

    init(engine: any ZephyrEngine) {
        _model = State(initialValue: LogsModel(engine: engine))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZSegmented([
                ZSegment(LogLevel.debug, title: "调试"),
                ZSegment(LogLevel.info, title: "信息"),
                ZSegment(LogLevel.warning, title: "警告"),
                ZSegment(LogLevel.error, title: "错误"),
            ], selection: $model.level, label: "最低级别")
            .padding(.horizontal, PageMetrics.margin)
            .padding(.vertical, ZTokens.Space.n3)

            if model.lines.isEmpty {
                Text("暂无日志")
                    .zType(.body)
                    .foregroundStyle(ZColor.t3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: ZTokens.Space.n2) {
                            ForEach(Array(model.lines.enumerated()), id: \.offset) { i, line in
                                row(line).id(i)
                            }
                        }
                        .padding(.horizontal, PageMetrics.margin)
                        .padding(.bottom, PageMetrics.bottomInset)
                    }
                    .onChange(of: model.lines.count) { _, n in
                        guard n > 0, !model.isPaused else { return }
                        proxy.scrollTo(n - 1, anchor: .bottom)
                    }
                }
            }
        }
        .zPageBackground()
        .navigationTitle(Text("日志"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.isPaused.toggle() } label: {
                    Label { Text(model.isPaused ? "继续" : "暂停") } icon: {
                        Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                    }
                }
                Button { model.clear() } label: {
                    Label { Text("清空") } icon: { Image(systemName: "trash") }
                }
                .disabled(model.lines.isEmpty)
                ShareLink(item: model.exportText()) {
                    Label { Text("分享") } icon: { Image(systemName: "square.and.arrow.up") }
                }
                .disabled(model.lines.isEmpty)
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private func row(_ line: LogLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ZTokens.Space.n2) {
            Text(verbatim: LogsModel.time(line.at))
                .zMono(.small)
                .foregroundStyle(ZColor.t3)
            Text(verbatim: LogsModel.badge(line.level))
                .zMono(.small, weight: .semibold)
                .foregroundStyle(color(line.level))
            Text(verbatim: line.message)
                .zMono(.small)
                .foregroundStyle(ZTokens.Colors.screenT1)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func color(_ level: LogLevel) -> Color {
        switch level {
        case .debug: ZColor.t3
        case .info: ZColor.t2
        case .warning: ZTokens.Colors.screenAmber
        case .error: ZTokens.Colors.screenRed
        }
    }
}

#if DEBUG
#Preview("日志") {
    NavigationStack { LogsView(engine: MockEngine(seed: 0, clock: .frozen941)) }
        .preferredColorScheme(.dark)
}
#endif
