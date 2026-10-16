import Foundation
import Combine
import SwiftUI
import SwiftData

enum WeeklyReviewText {
    static let title = "이번 주"
    static let period = "오늘까지 지난 7일"
    static let date = "날짜"
    static let mission = "메인 미션"
    static let done = "끝냄"
    static let count = "집중 수"
    static let minutes = "집중 분"
    static let memo = "이번 주에 도움이 된 것"
}

enum WeeklyReview {
    struct Row: Identifiable {
        let id: String
        let date: Date
        let mission: DailyMission
        let summary: DaySummary
    }

    static func make(entries: [DaySummary.Entry], notes: [UUID: TransitionDetails],
                     missions: [String: DailyMission], calendar: Calendar, now: Date) -> [Row] {
        let today = calendar.startOfDay(for: now)
        return (-6...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let key = DailyMissionStore.dayKey(for: date, calendar: calendar)
            return Row(id: key, date: date, mission: missions[key] ?? DailyMission(),
                       summary: DaySummary.make(entries: entries, notes: notes, calendar: calendar, now: date))
        }
    }

    static func weekKey(for date: Date, calendar: Calendar = .current) -> String {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let parts = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
    }
}

@MainActor
final class WeeklyReviewStore: ObservableObject {
    private static let key = "weeklyReviewMemos.v1"
    private let defaults: UserDefaults?
    @Published private(set) var memos: [String: String]

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        memos = defaults?.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    func memo(for date: Date, calendar: Calendar = .current) -> String {
        memos[WeeklyReview.weekKey(for: date, calendar: calendar)] ?? ""
    }

    func setMemo(_ text: String, for date: Date, calendar: Calendar = .current) {
        memos[WeeklyReview.weekKey(for: date, calendar: calendar)] = text.components(separatedBy: .newlines).joined(separator: " ")
        guard let data = try? JSONEncoder().encode(memos) else { return }
        defaults?.set(data, forKey: Self.key)
    }
}

struct WeeklyReviewView: View {
    @ObservedObject var missions: DailyMissionStore
    @ObservedObject var completions: FocusCompletionStore
    @ObservedObject var review: WeeklyReviewStore
    @Query private var logs: [FocusLogEntry]

    var body: some View {
        TimelineView(.periodic(from: Calendar.current.startOfDay(for: .now), by: 60)) { context in
            let date = context.date
            let rows = WeeklyReview.make(entries: completions.entries(from: logs), notes: [:],
                                         missions: missions.missions, calendar: .current, now: date)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(WeeklyReviewText.title).font(.headline)
                    Text(WeeklyReviewText.period).font(.caption).foregroundStyle(.secondary)
                }
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        Text(WeeklyReviewText.date)
                        Text(WeeklyReviewText.mission).frame(maxWidth: .infinity, alignment: .leading)
                        Text(WeeklyReviewText.done)
                        Text(WeeklyReviewText.count)
                        Text(WeeklyReviewText.minutes)
                    }
                    .foregroundStyle(.secondary)
                    ForEach(rows) { row in
                        GridRow {
                            Text(row.date.formatted(.dateTime.month().day()))
                            Text(row.mission.text.isEmpty ? "—" : row.mission.text)
                                .lineLimit(1).help(row.mission.text)
                            if row.mission.done {
                                Image(systemName: "checkmark").accessibilityLabel(WeeklyReviewText.done)
                            } else {
                                Text("—")
                            }
                            Text("\(row.summary.focusCount)번").monospacedDigit()
                            Text("\(row.summary.focusMinutes)분").monospacedDigit()
                        }
                    }
                }
                .font(.caption)
                TextField(WeeklyReviewText.memo, text: Binding(
                    get: { review.memo(for: date) },
                    set: { review.setMemo($0, for: date) }
                ))
                .textFieldStyle(.roundedBorder)
                .id(WeeklyReview.weekKey(for: date))
            }
            .padding()
        }
    }
}
