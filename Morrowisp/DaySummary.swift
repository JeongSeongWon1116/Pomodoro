import Foundation
import Combine
import SwiftUI
import SwiftData

struct DaySummary: Equatable {
    /// 모델과 저장소에서 분리한 읽기 전용 값. 날짜는 세션이 끝난 시각을 기준으로 합니다.
    struct Entry {
        let id: UUID
        let endTime: Date
        let duration: TimeInterval
        let sessionType: PomodoroState
        let completed: Bool
        var extensionCount: Int
    }

    let focusCount: Int
    let focusMinutes: Int
    let extensionCount: Int
    let mainTask: String?
    let hasFocus: Bool

    static func make(entries: [Entry], notes: [UUID: TransitionDetails], calendar: Calendar, now: Date) -> DaySummary {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let focus = entries.filter { $0.sessionType == .focus && $0.endTime >= start && $0.endTime < end }
        var tasks: [String: Int] = [:]
        for entry in focus {
            let task = (notes[entry.id]?.task ?? "").split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
            if !task.isEmpty { tasks[task, default: 0] += 1 }
        }
        // 동률은 글자순으로 정해 입력 배열이나 Dictionary 순서에 영향을 받지 않습니다.
        let mainTask = tasks.keys.sorted {
            let left = tasks[$0, default: 0], right = tasks[$1, default: 0]
            return left == right ? $0 < $1 : left > right
        }.first
        return DaySummary(
            focusCount: focus.filter(\.completed).count,
            focusMinutes: Int(focus.reduce(0) { $0 + max(0, $1.duration) } / 60),
            extensionCount: focus.reduce(0) { $0 + max(0, max($1.extensionCount, notes[$1.id]?.extensionCount ?? 0)) },
            mainTask: mainTask,
            hasFocus: !focus.isEmpty
        )
    }

    var text: String { DaySummaryText.line(self) }
}

enum DaySummaryText {
    static func empty(locale: Locale = .current) -> String {
        String(localized: "Ready for your first focus session today?", bundle: AppLocalization.bundle(for: locale), locale: locale)
    }
    static func line(_ summary: DaySummary, locale: Locale = .current) -> String {
        guard summary.hasFocus else { return empty(locale: locale) }
        var text = String(localized: "Focus sessions today: \(summary.focusCount.formatted(.number.locale(locale))) · \(summary.focusMinutes.formatted(.number.locale(locale))) min · Extensions: \(summary.extensionCount.formatted(.number.locale(locale)))", bundle: AppLocalization.bundle(for: locale), locale: locale)
        if let task = summary.mainTask { text += String(localized: " · Mostly: \(task)", bundle: AppLocalization.bundle(for: locale), locale: locale) }
        return text
    }
}

struct FocusCompletion: Codable, Equatable {
    let completed: Bool
    let extensionCount: Int
}

/// 기존 집중/메모 SwiftData 스키마를 유지하는 완료 여부 보조 저장소.
/// 과거 기록에는 완료 표식이 없으므로 시간을 세되 완료 횟수를 추측하지 않습니다.
@MainActor
final class FocusCompletionStore: ObservableObject {
    private static let key = "focusCompletions.v1"
    private let defaults: UserDefaults?
    @Published private(set) var records: [UUID: FocusCompletion]
    // 선택 중인 세션은 아직 SwiftData 기록 전입니다. 같은 id로 합쳐 중복 없이 바로 보여 줍니다.
    @Published var pending: DaySummary.Entry?
    @Published var pendingDetails: TransitionDetails?

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        records = defaults?.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([UUID: FocusCompletion].self, from: $0) } ?? [:]
    }

    func record(_ id: UUID, completed: Bool, extensionCount: Int) {
        records[id] = FocusCompletion(completed: completed, extensionCount: extensionCount)
        save()
    }

    func remove(_ ids: [UUID]?) {
        if let ids {
            for id in ids { records.removeValue(forKey: id) }
        } else {
            records.removeAll()
        }
        save()
    }

    func entries(from logs: [FocusLogEntry]) -> [DaySummary.Entry] {
        var entries = logs.map { log in
            DaySummary.Entry(id: log.id, endTime: log.endTime, duration: log.duration,
                             sessionType: log.sessionType, completed: records[log.id]?.completed ?? false,
                             extensionCount: records[log.id]?.extensionCount ?? 0)
        }
        if let pending, !entries.contains(where: { $0.id == pending.id }) { entries.append(pending) }
        return entries
    }

    func includingPendingNotes(_ notes: [UUID: TransitionDetails]) -> [UUID: TransitionDetails] {
        var notes = notes
        if let pending, let pendingDetails { notes[pending.id] = pendingDetails }
        return notes
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults?.set(data, forKey: Self.key)
    }
}

struct DaySummaryView: View {
    @ObservedObject var completions: FocusCompletionStore
    @Query private var logs: [FocusLogEntry]
    @State private var notes: [UUID: TransitionDetails] = [:]

    var body: some View {
        TimelineView(.periodic(from: Calendar.current.startOfDay(for: .now), by: 60)) { context in
            let summary = DaySummary.make(entries: completions.entries(from: logs),
                                          notes: completions.includingPendingNotes(notes),
                                          calendar: .current, now: context.date)
            Text(summary.text)
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(summary.text)
        }
        .task(id: logs.map(\.id)) {
            notes = TransitionNote.details(forSessions: logs.map(\.id), in: DataController.shared.transitionContainer?.mainContext)
        }
    }
}
