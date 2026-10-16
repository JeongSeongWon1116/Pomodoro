import Foundation
import Combine
import SwiftUI
import SwiftData

struct WeeklyReviewText {
    let locale: Locale

    init(locale: Locale = .current) { self.locale = locale }
    var title: String { String(localized: "This week", bundle: AppLocalization.bundle(for: locale), locale: locale) }
    var period: String { String(localized: "The past 7 days, including today", bundle: AppLocalization.bundle(for: locale), locale: locale) }
    var date: String { String(localized: "Date", bundle: AppLocalization.bundle(for: locale), locale: locale) }
    var mission: String { String(localized: "Main mission", bundle: AppLocalization.bundle(for: locale), locale: locale) }
    var done: String { String(localized: "Done", bundle: AppLocalization.bundle(for: locale), locale: locale) }
    var count: String { String(localized: "Focus sessions", bundle: AppLocalization.bundle(for: locale), locale: locale) }
    var minutes: String { String(localized: "Focus minutes", bundle: AppLocalization.bundle(for: locale), locale: locale) }
    var memo: String { String(localized: "What helped this week", bundle: AppLocalization.bundle(for: locale), locale: locale) }
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
    @Environment(\.locale) private var locale
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
                    Text(WeeklyReviewText(locale: locale).title).font(.headline).foregroundStyle(.primary)
                    Text(WeeklyReviewText(locale: locale).period).font(.caption).foregroundStyle(.secondary)
                }
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        Text(WeeklyReviewText(locale: locale).date)
                            .fixedSize()
                        Text(WeeklyReviewText(locale: locale).mission).frame(maxWidth: .infinity, alignment: .leading)
                        Text(WeeklyReviewText(locale: locale).done)
                            .fixedSize()
                        Text(WeeklyReviewText(locale: locale).count)
                            .fixedSize()
                        Text(WeeklyReviewText(locale: locale).minutes)
                            .fixedSize()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    ForEach(rows) { row in
                        GridRow {
                            Text(row.date.formatted(.dateTime.locale(locale).month().day()))
                                .fixedSize()
                            Text(row.mission.text.isEmpty ? "—" : row.mission.text)
                                .lineLimit(2).help(row.mission.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if row.mission.done {
                                Image(systemName: "checkmark").accessibilityLabel(WeeklyReviewText(locale: locale).done)
                            } else {
                                Text(verbatim: "—")
                            }
                            Text(row.summary.focusCount.formatted(.number.locale(locale))).monospacedDigit()
                                .gridColumnAlignment(.trailing)
                            Text(row.summary.focusMinutes.formatted(.number.locale(locale))).monospacedDigit()
                                .gridColumnAlignment(.trailing)
                        }
                    }
                }
                .font(.caption)
                TextField(WeeklyReviewText(locale: locale).memo, text: Binding(
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
