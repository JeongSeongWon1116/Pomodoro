import Foundation
import Testing
@testable import Pomodoro

@MainActor
struct WeeklyReviewTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        return calendar
    }
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func 오늘까지_지난_7일을_빈_날도_포함해서_만든다() {
        let today = date(2026, 10, 16)
        let mission = DailyMission(text: "한 문단", done: true, doneAt: today)
        let entry = DaySummary.Entry(id: UUID(), endTime: today, duration: 1500,
                                     sessionType: .focus, completed: true, extensionCount: 0)
        let rows = WeeklyReview.make(entries: [entry], notes: [:], missions: ["2026-10-16": mission], calendar: calendar, now: today)
        #expect(rows.count == 7)
        #expect(rows.map(\.id) == (10...16).map { "2026-10-\($0)" })
        #expect(rows.first?.summary.focusCount == 0)
        #expect(rows.first?.mission == DailyMission())
        #expect(rows.last?.mission == mission)
        #expect(rows.last?.summary.focusCount == 1)
        #expect(rows.last?.summary.focusMinutes == 25)
    }

    @Test func ISO_주_키는_연말과_연초에도_같은_주를_가리킨다() {
        #expect(WeeklyReview.weekKey(for: date(2021, 1, 1), calendar: calendar) == "2020-W53")
        #expect(WeeklyReview.weekKey(for: date(2021, 1, 3), calendar: calendar) == "2020-W53")
        #expect(WeeklyReview.weekKey(for: date(2021, 1, 4), calendar: calendar) == "2021-W01")
        #expect(WeeklyReview.weekKey(for: date(2018, 12, 31), calendar: calendar) == "2019-W01")
    }

    @Test func ISO_주_경계도_로컬_자정이다() {
        let monday = date(2021, 1, 4)
        #expect(WeeklyReview.weekKey(for: monday.addingTimeInterval(-1), calendar: calendar) == "2020-W53")
        #expect(WeeklyReview.weekKey(for: monday, calendar: calendar) == "2021-W01")
    }

    @Test func 서머타임을_지나도_날짜_행은_일곱이다() throws {
        var local = calendar
        local.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let now = try #require(local.date(from: DateComponents(year: 2026, month: 3, day: 10)))
        let rows = WeeklyReview.make(entries: [], notes: [:], missions: [:], calendar: local, now: now)
        #expect(rows.map(\.id) == (4...10).map { String(format: "2026-03-%02d", $0) })
    }

    @Test func 주별_메모를_저장하고_다음_주는_빈칸이다() throws {
        let suite = "WeeklyReviewTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WeeklyReviewStore(defaults: defaults)
        store.setMemo("산책\n물 마시기", for: date(2021, 1, 1), calendar: calendar)
        let reopened = WeeklyReviewStore(defaults: defaults)
        #expect(reopened.memo(for: date(2021, 1, 3), calendar: calendar) == "산책 물 마시기")
        #expect(reopened.memo(for: date(2021, 1, 4), calendar: calendar).isEmpty)
        #expect(WeeklyReviewText(locale: Locale(identifier: "ko")).memo == "이번 주에 도움이 된 것")
    }

    @Test func 미션은_Obsidian_섹션_맨_위에서_갱신되고_다른_내용은_남는다() {
        let heading = ObsidianExporter.sectionHeading
        let session = "- 🍅 집중 25분 (09:00–09:25)"
        let content = "# 하루\n기존 글\n\n\(heading)\n\(session)\n\n## 다른 기록\n그대로\n"
        let mission = DailyMission(text: "초안\n%%메모", done: true)
        let first = ObsidianExporter.insert(line: nil, into: content, mission: mission)
        #expect(first.contains("\(heading)\n\t- 오늘의 메인 미션: ✓ 초안 % %메모\n"))
        #expect(first.hasPrefix("# 하루\n기존 글\n\n"))
        #expect(first.hasSuffix("## 다른 기록\n그대로\n"))
        let second = ObsidianExporter.insert(line: nil, into: first, mission: DailyMission(text: "교정"))
        #expect(second.components(separatedBy: "오늘의 메인 미션:").count == 2)
        #expect(!second.contains("초안"))
        #expect(second.contains(session))
        #expect(second.contains("1회 · 총 25분"))
        let cleared = ObsidianExporter.insert(line: nil, into: second, mission: DailyMission())
        #expect(!cleared.contains("오늘의 메인 미션:"))
        #expect(cleared.contains(session))
    }

    @Test func 미션을_넘기지_않으면_기존_미션은_유지한다() {
        let first = ObsidianExporter.insert(line: nil, into: "", mission: DailyMission(text: "초안"))
        let updated = ObsidianExporter.insert(line: "- 🍅 집중 25분 (09:00–09:25)", into: first)
        #expect(updated.contains("\t- 오늘의 메인 미션: 초안"))
        #expect(updated.contains("1회 · 총 25분"))
    }

    @Test func 미션만_적은_날도_파일에_남긴다() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WeeklyReviewTests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let note = folder.appendingPathComponent("2026-10-16.md")
        try ObsidianExporter.appendLine(nil, toNoteAt: note, mission: DailyMission(text: "초안"))
        let written = try String(contentsOf: note, encoding: .utf8)
        #expect(written.contains("\t- 오늘의 메인 미션: 초안"))
        #expect(written.contains("0회"))
    }
}
