import Foundation
import SwiftData
import Testing
@testable import Pomodoro

@MainActor
struct DaySummaryTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        return calendar
    }
    private let now = Date(timeIntervalSince1970: 1_792_155_600)

    private func entry(_ seconds: TimeInterval = 1500, completed: Bool = true,
                       extensions: Int = 0, type: PomodoroState = .focus, end: Date? = nil) -> DaySummary.Entry {
        DaySummary.Entry(id: UUID(), endTime: end ?? now, duration: seconds,
                         sessionType: type, completed: completed, extensionCount: extensions)
    }

    @Test func 마친_집중만_세고_시간은_실제_집중한_만큼_합한다() {
        let result = DaySummary.make(entries: [entry(), entry(120, completed: false), entry(type: .shortBreak)],
                                     notes: [:], calendar: calendar, now: now)
        #expect(result.focusCount == 1)
        #expect(result.focusMinutes == 27)
        #expect(result.extensionCount == 0)
    }

    @Test func 연장은_집중을_나누지_않고_횟수를_합한다() {
        let result = DaySummary.make(entries: [entry(2700, extensions: 2), entry(2100, extensions: 1)],
                                     notes: [:], calendar: calendar, now: now)
        #expect(result.focusCount == 2)
        #expect(result.focusMinutes == 80)
        #expect(result.extensionCount == 3)
        #expect(result.text == "오늘 집중 2번 · 80분 · 연장 3번")
    }

    @Test func 로컬_자정은_포함하고_다음_자정은_제외한다() throws {
        let midnight = calendar.startOfDay(for: now)
        let next = try #require(calendar.date(byAdding: .day, value: 1, to: midnight))
        let result = DaySummary.make(entries: [entry(end: midnight.addingTimeInterval(-1)), entry(end: midnight), entry(end: next)],
                                     notes: [:], calendar: calendar, now: now)
        #expect(result.focusCount == 1)
    }

    @Test func 가장_많이_적은_할_일을_고르고_동률은_글자순이다() {
        let a = entry(), b = entry(), c = entry()
        let notes = [a.id: TransitionDetails(task: " 초안 "), b.id: TransitionDetails(task: "초안"), c.id: TransitionDetails(task: "교정")]
        let result = DaySummary.make(entries: [a, b, c], notes: notes, calendar: calendar, now: now)
        #expect(result.mainTask == "초안")
        #expect(result.text.hasSuffix("주로: 초안"))
        #expect(DaySummary.make(entries: [a, c], notes: notes, calendar: calendar, now: now).mainTask == "교정")
        #expect(DaySummary.make(entries: [c, a], notes: notes, calendar: calendar, now: now).mainTask == "교정")
    }

    @Test func 기록이_없으면_부드러운_안내만_보인다() {
        let result = DaySummary.make(entries: [], notes: [:], calendar: calendar, now: now)
        #expect(result.focusCount == 0)
        #expect(result.focusMinutes == 0)
        #expect(result.mainTask == nil)
        #expect(result.text == "오늘 첫 집중을 시작해 볼까요")
    }

    @Test func 초를_합친_뒤_분으로_내린다() {
        #expect(DaySummary.make(entries: [entry(40), entry(40)], notes: [:], calendar: calendar, now: now).focusMinutes == 1)
    }

    @Test func 완료_메타데이터_저장_왕복과_삭제() throws {
        let suite = "DaySummaryTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FocusCompletionStore(defaults: defaults)
        let id = UUID()
        store.record(id, completed: true, extensionCount: 2)
        let reopened = FocusCompletionStore(defaults: defaults)
        #expect(reopened.records[id]?.completed == true)
        #expect(reopened.records[id]?.extensionCount == 2)
        reopened.remove([id])
        #expect(FocusCompletionStore(defaults: defaults).records.isEmpty)
    }

    @Test func 과거_기록의_완료_여부는_추측하지_않는다() {
        let log = FocusLogEntry(startTime: now.addingTimeInterval(-1500), endTime: now, duration: 1500, sessionType: .focus)
        let entries = FocusCompletionStore(defaults: nil).entries(from: [log])
        #expect(entries.first?.completed == false)
        #expect(DaySummary.make(entries: entries, notes: [:], calendar: calendar, now: now).focusMinutes == 25)
    }
}

@MainActor
struct DaySummaryFlowTests {
    private let clock = TestClock()
    private let settings = AppSettings(defaults: nil)
    private let container: ModelContainer
    private let appDelegate = AppDelegate()
    private let viewModel: PomodoroViewModel

    init() throws {
        container = try ModelContainer(for: FocusLogEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        settings.notificationSoundName = AppSettings.soundOff
        let clock = self.clock
        viewModel = PomodoroViewModel(modelContext: container.mainContext, appDelegate: appDelegate,
                                      settings: settings, now: { clock.date })
    }

    private func summary() throws -> DaySummary {
        let logs = try container.mainContext.fetch(FetchDescriptor<FocusLogEntry>())
        return DaySummary.make(entries: settings.focusCompletions.entries(from: logs), notes: [:], calendar: .current, now: clock.date)
    }

    @Test func 선택을_기다리는_집중도_보이며_휴식_선택_뒤_겹치지_않는다() throws {
        viewModel.startFocusSession()
        clock.advance(viewModel.timeRemaining)
        viewModel.tick()
        #expect(try summary().focusCount == 1)
        viewModel.startBreakAfterFocus()
        #expect(try summary().focusCount == 1)
    }

    @Test func 중간에_건너뛴_집중은_세지_않는다() throws {
        viewModel.startFocusSession()
        clock.advance(120)
        viewModel.skipToNextSession()
        #expect(try summary().focusCount == 0)
        #expect(try summary().focusMinutes == 2)
    }

    @Test func 연장_중에_초기화해도_원래_마친_집중은_센다() throws {
        viewModel.startFocusSession()
        clock.advance(viewModel.timeRemaining)
        viewModel.tick()
        viewModel.extendFocus()
        clock.advance(60)
        viewModel.resetToIdle()
        #expect(try summary().focusCount == 1)
        #expect(try summary().extensionCount == 1)
        #expect(try summary().focusMinutes == 26)
    }

    @Test func 전환_관리를_꺼도_완료_여부는_남는다() throws {
        settings.transitionManagementEnabled = false
        viewModel.startFocusSession()
        clock.advance(viewModel.timeRemaining)
        viewModel.tick()
        #expect(try summary().focusCount == 1)
    }
}
