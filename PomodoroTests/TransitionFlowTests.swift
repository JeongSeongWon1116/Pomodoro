//
//  TransitionFlowTests.swift
//  PomodoroTests
//
//  집중이 끝났을 때의 선택(휴식 시작 / 10분 연장)과 할 일·보상·다음 시작점 기록을
//  주입한 시계로 검증합니다. (사용자의 설정·기록·보관함을 건드리지 않습니다.)
//

import Foundation
import SwiftData
import Testing
@testable import Pomodoro

@MainActor
struct TransitionFlowTests {

    private let clock = TestClock()
    private let settings: AppSettings
    private let container: ModelContainer
    private let notesContainer: ModelContainer
    private let appDelegate = AppDelegate()
    private let viewModel: PomodoroViewModel

    init() throws {
        let settings = AppSettings(defaults: nil)
        settings.notificationSoundName = AppSettings.soundOff
        self.settings = settings
        container = try ModelContainer(
            for: FocusLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        notesContainer = try ModelContainer(
            for: TransitionNote.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let clock = self.clock
        viewModel = PomodoroViewModel(
            modelContext: container.mainContext,
            appDelegate: appDelegate,
            settings: settings,
            notesContext: notesContainer.mainContext,
            now: { clock.date }
        )
    }

    private func loggedEntries() throws -> [FocusLogEntry] {
        try container.mainContext.fetch(FetchDescriptor<FocusLogEntry>(sortBy: [SortDescriptor(\.startTime)]))
    }

    private func savedNotes() throws -> [TransitionNote] {
        try notesContainer.mainContext.fetch(FetchDescriptor<TransitionNote>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    /// 현재 세션의 시간을 끝까지 흘려보냅니다.
    private func runOutTheClock() {
        clock.advance(viewModel.timeRemaining)
        viewModel.tick()
    }

    // MARK: - 끝났을 때 선택

    @Test func 집중이_끝나면_선택을_기다리고_휴식이_혼자_시작되지_않는다() throws {
        viewModel.startFocusSession()
        runOutTheClock()

        #expect(viewModel.timerState == .awaitingChoice)
        #expect(viewModel.currentState == .focus)
        #expect(viewModel.completedFocusSessions == 0)
        #expect(try loggedEntries().isEmpty)

        clock.advance(5 * 60) // 자리를 비워도 그대로 기다립니다
        viewModel.tick()
        #expect(viewModel.timerState == .awaitingChoice)
        #expect(viewModel.currentState == .focus)
        #expect(viewModel.timeRemaining == 0)
        #expect(try loggedEntries().isEmpty)
    }

    @Test func 휴식을_고르면_집중이_기록되고_휴식이_바로_시작된다() throws {
        settings.autoStartBreaks = false // 직접 고른 휴식은 자동 시작 설정과 상관없이 시작합니다
        viewModel.startFocusSession()
        let start = clock.date
        runOutTheClock()
        let deadline = clock.date
        clock.advance(120) // 2분 뒤에 고름

        viewModel.startBreakAfterFocus()

        #expect(viewModel.completedFocusSessions == 1)
        #expect(viewModel.currentState == .shortBreak)
        #expect(viewModel.timerState == .running)
        let entries = try loggedEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.sessionType == .focus)
        #expect(entries.first?.startTime == start)
        #expect(entries.first?.duration == TimeInterval(25 * 60))
        #expect(entries.first?.pausedDuration == 0) // 기다린 시간은 집중 기록에 넣지 않습니다
        #expect(entries.first?.endTime == deadline)  // 끝난 시각은 고른 때가 아니라 시간이 다 된 때
    }

    @Test func 연장을_고르면_같은_집중이_10분_더_이어진다() throws {
        viewModel.startFocusSession()
        runOutTheClock()
        clock.advance(30)

        viewModel.extendFocus()

        #expect(viewModel.timerState == .running)
        #expect(viewModel.currentState == .focus)
        #expect(viewModel.timeRemaining == TimeInterval(10 * 60))
        #expect(viewModel.extensionCount == 1)
        #expect(try loggedEntries().isEmpty) // 아직 같은 세션입니다

        runOutTheClock()
        #expect(viewModel.timerState == .awaitingChoice)
        viewModel.startBreakAfterFocus()

        let entries = try loggedEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.duration == TimeInterval(35 * 60))
        #expect(entries.first?.pausedDuration == 30) // 연장을 고르기까지 기다린 시간
        #expect(viewModel.completedFocusSessions == 1)
        #expect(try savedNotes().first?.extensionCount == 1)
    }

    @Test func 연장을_연달아_눌러도_한_번만_늘어난다() {
        viewModel.startFocusSession()
        runOutTheClock()

        viewModel.extendFocus()
        viewModel.extendFocus() // 두 번째 클릭은 이미 돌고 있는 타이머에 닿으므로 무시됩니다

        #expect(viewModel.timeRemaining == TimeInterval(10 * 60))
        #expect(viewModel.extensionCount == 1)
    }

    @Test func 절전으로_틱이_늦게_와도_끝난_시각은_시간이_다_된_때다() throws {
        viewModel.startFocusSession()
        let start = clock.date
        clock.advance(25 * 60 + 15 * 60) // 끝나고 15분 뒤에야 깨어남
        viewModel.tick()
        #expect(viewModel.timerState == .awaitingChoice)

        viewModel.startBreakAfterFocus()

        let entry = try #require(try loggedEntries().first)
        #expect(entry.duration == TimeInterval(25 * 60))
        #expect(entry.endTime == start.addingTimeInterval(25 * 60))
    }

    @Test func 늦게_깨어나_연장하면_끝난_뒤_흐른_시간이_모두_정지_시간이다() throws {
        viewModel.startFocusSession()
        clock.advance(25 * 60 + 15 * 60)
        viewModel.tick()
        clock.advance(60)

        viewModel.extendFocus()
        runOutTheClock()
        viewModel.startBreakAfterFocus()

        let entry = try #require(try loggedEntries().first)
        #expect(entry.duration == TimeInterval(35 * 60))
        #expect(entry.pausedDuration == TimeInterval(16 * 60))
    }

    @Test func 선택을_기다리는_동안_건너뛰기와_일시정지는_아무_일도_하지_않는다() throws {
        viewModel.startFocusSession()
        runOutTheClock()

        viewModel.skipToNextSession()
        viewModel.pauseTimer()
        viewModel.resumeTimer()
        viewModel.startFocusSession()

        #expect(viewModel.timerState == .awaitingChoice)
        #expect(viewModel.currentState == .focus)
        #expect(try loggedEntries().isEmpty)
    }

    @Test func 선택을_기다리는_중에_종료하면_집중_전체가_기록된다() throws {
        viewModel.startFocusSession()
        runOutTheClock()
        let deadline = clock.date
        clock.advance(600)

        viewModel.logInterruptedSession()
        viewModel.logInterruptedSession()

        let entries = try loggedEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.duration == TimeInterval(25 * 60))
        #expect(entries.first?.pausedDuration == 0)
        #expect(entries.first?.endTime == deadline)
    }

    @Test func 선택을_기다리는_중에_초기화하면_집중을_기록하고_대기로_돌아간다() throws {
        viewModel.startFocusSession()
        runOutTheClock()
        clock.advance(60)

        viewModel.resetToIdle()

        #expect(viewModel.timerState == .idle)
        #expect(viewModel.currentState == .idle)
        #expect(try loggedEntries().first?.duration == TimeInterval(25 * 60))
    }

    @Test func 간격만큼_집중을_마치고_휴식을_고르면_긴_휴식이_온다() {
        settings.longBreakInterval = 2
        viewModel.startFocusSession()
        runOutTheClock()
        viewModel.startBreakAfterFocus()
        #expect(viewModel.currentState == .shortBreak)
        runOutTheClock() // 휴식 끝 → 집중 자동 시작
        #expect(viewModel.currentState == .focus)

        runOutTheClock()
        viewModel.startBreakAfterFocus()
        #expect(viewModel.completedFocusSessions == 2)
        #expect(viewModel.currentState == .longBreak)
    }

    @Test func 전환_관리를_끄면_예전처럼_자동으로_넘어가고_메모를_남기지_않는다() throws {
        viewModel.focusTask = "꺼 두기 전에 적어 둔 할 일"
        settings.transitionManagementEnabled = false
        viewModel.startFocusSession()
        runOutTheClock()

        #expect(viewModel.currentState == .shortBreak)
        #expect(viewModel.timerState == .running)
        #expect(viewModel.completedFocusSessions == 1)
        #expect(try loggedEntries().count == 1)
        #expect(try savedNotes().isEmpty)
    }

    @Test func 연장한_집중을_건너뛰면_마친_집중으로_세고_적어_둔_다음_시작점을_넘긴다() throws {
        settings.longBreakInterval = 1
        viewModel.startFocusSession()
        runOutTheClock()
        viewModel.nextStartingPoint = "표 2 다시 그리기" // 적어 두고 나서 연장을 고름
        viewModel.extendFocus()
        clock.advance(180)

        viewModel.skipToNextSession()

        #expect(viewModel.completedFocusSessions == 1) // 원래 25분은 이미 다 채웠습니다
        #expect(viewModel.currentState == .longBreak)
        #expect(viewModel.resumeHint == "표 2 다시 그리기")
        #expect(viewModel.nextStartingPoint == "")
        let entry = try #require(try loggedEntries().first)
        #expect(entry.duration == TimeInterval(25 * 60 + 180))
        let note = try #require(try savedNotes().first)
        #expect(note.extensionCount == 1)
        #expect(note.nextStartingPoint == "표 2 다시 그리기")
    }

    @Test func 건너뛴_집중은_선택_화면_없이_휴식으로_넘어간다() {
        viewModel.startFocusSession()
        clock.advance(10)
        viewModel.skipToNextSession()

        #expect(viewModel.currentState == .shortBreak)
        #expect(viewModel.completedFocusSessions == 0)
    }

    // MARK: - 할 일 · 보상 · 다음 시작점

    @Test func 할_일과_보상과_다음_시작점이_집중_기록과_함께_저장된다() throws {
        viewModel.focusTask = "3장 초안"
        viewModel.focusReward = "커피"
        viewModel.startFocusSession()
        runOutTheClock()
        viewModel.nextStartingPoint = "3.2절 두 번째 문단부터"
        viewModel.startBreakAfterFocus()

        let entry = try #require(try loggedEntries().first)
        let notes = try savedNotes()
        #expect(notes.count == 1)
        #expect(notes.first?.sessionID == entry.id)
        #expect(notes.first?.task == "3장 초안")
        #expect(notes.first?.reward == "커피")
        #expect(notes.first?.nextStartingPoint == "3.2절 두 번째 문단부터")
        #expect(notes.first?.extensionCount == 0)
    }

    @Test func 적어_둔_다음_시작점은_다음_집중에서_이어서_보인다() {
        viewModel.startFocusSession()
        runOutTheClock()
        viewModel.nextStartingPoint = "  표 2 다시 그리기  "
        viewModel.startBreakAfterFocus()

        #expect(viewModel.resumeHint == "표 2 다시 그리기") // 앞뒤 공백은 뗍니다
        #expect(viewModel.nextStartingPoint == "")           // 다음 선택 화면은 빈 칸에서 시작

        runOutTheClock() // 휴식 끝 → 다음 집중
        #expect(viewModel.currentState == .focus)
        #expect(viewModel.resumeHint == "표 2 다시 그리기")
    }

    @Test func 다음_시작점을_비워_두고_마치면_지난_것은_지워진다() {
        viewModel.startFocusSession()
        runOutTheClock()
        viewModel.nextStartingPoint = "표 2 다시 그리기"
        viewModel.startBreakAfterFocus()
        runOutTheClock()

        runOutTheClock() // 두 번째 집중 끝
        viewModel.startBreakAfterFocus()

        #expect(viewModel.resumeHint == "")
    }

    @Test func 건너뛰거나_초기화한_집중은_다음_시작점을_바꾸지_않는다() {
        viewModel.startFocusSession()
        runOutTheClock()
        viewModel.nextStartingPoint = "표 2 다시 그리기"
        viewModel.startBreakAfterFocus()
        runOutTheClock()

        clock.advance(10)
        viewModel.skipToNextSession() // 선택 화면을 거치지 않았으므로 적을 기회가 없었습니다
        #expect(viewModel.resumeHint == "표 2 다시 그리기")

        runOutTheClock() // 휴식 끝 → 다음 집중
        #expect(viewModel.currentState == .focus)
        clock.advance(10)
        viewModel.resetToIdle()
        #expect(viewModel.resumeHint == "표 2 다시 그리기")
    }

    @Test(arguments: [true, false])
    func 선택_화면에서_적지_않고_초기화하거나_종료하면_지난_다음_시작점이_남는다(quit: Bool) {
        viewModel.startFocusSession()
        runOutTheClock()
        viewModel.nextStartingPoint = "표 2 다시 그리기"
        viewModel.startBreakAfterFocus()
        runOutTheClock() // 휴식 끝 → 다음 집중
        runOutTheClock() // 다음 집중 끝 → 선택 대기
        #expect(viewModel.timerState == .awaitingChoice)

        if quit { viewModel.logInterruptedSession() } else { viewModel.resetToIdle() }

        #expect(viewModel.resumeHint == "표 2 다시 그리기")
    }

    @Test func 선택_화면에서_적고_초기화해도_적은_다음_시작점은_넘어간다() {
        viewModel.startFocusSession()
        runOutTheClock()
        viewModel.nextStartingPoint = "그림 3 캡션"
        viewModel.resetToIdle()

        #expect(viewModel.resumeHint == "그림 3 캡션")
        #expect(viewModel.nextStartingPoint == "")
    }

    @Test func 메모_저장소가_없어도_집중_기록은_남는다() throws {
        let clock = self.clock
        let withoutStore = PomodoroViewModel(
            modelContext: container.mainContext, appDelegate: appDelegate,
            settings: settings, notesContext: nil, now: { clock.date }
        )
        withoutStore.focusTask = "3장 초안"
        withoutStore.startFocusSession()
        clock.advance(withoutStore.timeRemaining)
        withoutStore.tick()
        withoutStore.startBreakAfterFocus()

        #expect(try loggedEntries().count == 1)
        #expect(try savedNotes().isEmpty)
        #expect(withoutStore.currentState == .shortBreak)
    }

    @Test func 아무것도_적지_않고_연장도_없으면_메모를_남기지_않는다() throws {
        viewModel.startFocusSession()
        runOutTheClock()
        viewModel.startBreakAfterFocus()

        #expect(try loggedEntries().count == 1)
        #expect(try savedNotes().isEmpty)
    }

    @Test func 중간에_그만둔_집중에도_할_일은_남는다() throws {
        viewModel.focusTask = "메일 답장"
        viewModel.startFocusSession()
        clock.advance(90)
        viewModel.resetToIdle()

        let entry = try #require(try loggedEntries().first)
        #expect(try savedNotes().first?.sessionID == entry.id)
        #expect(try savedNotes().first?.task == "메일 답장")
    }

    @Test func 휴식_기록에는_메모를_붙이지_않는다() throws {
        viewModel.focusTask = "3장 초안"
        viewModel.startFocusSession()
        runOutTheClock()
        viewModel.startBreakAfterFocus()
        runOutTheClock() // 휴식 끝

        #expect(try loggedEntries().count == 2)
        #expect(try savedNotes().count == 1)
    }

    @Test func 기록을_지우면_딸린_메모만_함께_지워진다() throws {
        let context = notesContainer.mainContext
        let kept = UUID(), removed = UUID()
        for id in [kept, removed] {
            context.insert(TransitionNote(sessionID: id, details: TransitionDetails(task: "할 일")))
        }
        try context.save()

        TransitionNote.delete(forSessions: [removed], in: context)
        #expect(try savedNotes().map(\.sessionID) == [kept])

        TransitionNote.delete(forSessions: nil, in: context)
        #expect(try savedNotes().isEmpty)
    }

    @Test func 적어_둔_할_일과_보상과_다음_시작점은_저장소가_있으면_앱을_다시_켜도_남는다() throws {
        // 이름을 고정합니다: 돌릴 때마다 새 이름을 쓰면, 지운 뒤에도 빈 설정 파일이 앱의 컨테이너에 하나씩 남습니다.
        let suite = "PomodoroTests-transition-notes"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = self.clock

        let first = PomodoroViewModel(
            modelContext: container.mainContext, appDelegate: appDelegate,
            settings: AppSettings(defaults: defaults), notesContext: notesContainer.mainContext,
            now: { clock.date }
        )
        first.focusTask = "3장 초안"
        first.focusReward = "커피"
        first.startFocusSession()
        clock.advance(first.timeRemaining)
        first.tick()
        first.nextStartingPoint = "표 2 다시 그리기"
        first.startBreakAfterFocus()

        let second = PomodoroViewModel(
            modelContext: container.mainContext, appDelegate: appDelegate,
            settings: AppSettings(defaults: defaults), notesContext: notesContainer.mainContext,
            now: { clock.date }
        )
        #expect(second.focusTask == "3장 초안")
        #expect(second.focusReward == "커피")
        #expect(second.resumeHint == "표 2 다시 그리기")
    }
}

// MARK: - Obsidian 기록 줄

@MainActor
struct TransitionMarkdownTests {

    private let heading = ObsidianExporter.sectionHeading
    private let stats = ObsidianExporter.statsPrefix

    /// 09:00 에 시작한 25분 집중 (현재 시간대 기준)
    private func focusEntry(minutes: Int = 25) -> FocusLogEntry {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 9, minute: 0))!
        return FocusLogEntry(
            startTime: start,
            endTime: start.addingTimeInterval(TimeInterval(minutes * 60)),
            duration: TimeInterval(minutes * 60),
            sessionType: .focus
        )
    }

    @Test func 적은_것이_없으면_기록_줄은_예전과_같다() {
        let entry = focusEntry()
        #expect(ObsidianExporter.markdownLines(for: entry, details: nil) == ObsidianExporter.markdownLine(for: entry))
        let empty = TransitionDetails(task: "  ")
        #expect(ObsidianExporter.markdownLines(for: entry, details: empty) == "- 🍅 집중 25분 (09:00–09:25)")
    }

    @Test func 적은_것은_기록_줄_아래에_들여쓴_줄로_붙는다() {
        let entry = focusEntry(minutes: 35)
        let details = TransitionDetails(task: "3장 초안", reward: "커피",
                                        nextStartingPoint: "3.2절 두 번째 문단부터", extensionCount: 1)
        #expect(ObsidianExporter.markdownLines(for: entry, details: details) == """
        - 🍅 집중 35분 (09:00–09:35)
        \t- 할 일: 3장 초안
        \t- 보상: 커피
        \t- 다음 시작점: 3.2절 두 번째 문단부터
        \t- 연장: +10분
        """)
    }

    @Test func 줄바꿈이_든_글은_한_줄로_펴서_적는다() {
        let entry = focusEntry()
        let details = TransitionDetails(task: "메일 답장\n## 회의록\r\n정리 ")
        #expect(ObsidianExporter.markdownLines(for: entry, details: details) == "- 🍅 집중 25분 (09:00–09:25)\n\t- 할 일: 메일 답장 ## 회의록 정리")
    }

    @Test func Obsidian_주석_표시는_짝이_없어도_뒤를_숨기지_않게_띄어_적는다() {
        let entry = focusEntry()
        let details = TransitionDetails(task: "진척 50%% 완료 %%%")
        #expect(ObsidianExporter.markdownLines(for: entry, details: details) == "- 🍅 집중 25분 (09:00–09:25)\n\t- 할 일: 진척 50% % 완료 % % %")
    }

    @Test func 들여쓴_줄이_있어도_하루_통계는_집중_줄만_세고_들여쓴_줄을_보존한다() {
        let first = focusEntry()
        let firstDetails = TransitionDetails(task: "- 🍅 집중 99분 (흉내)", nextStartingPoint: "표 2부터")
        let afterFirst = ObsidianExporter.insert(line: ObsidianExporter.markdownLines(for: first, details: firstDetails), into: "")
        let afterSecond = ObsidianExporter.insert(line: "- 🍅 집중 12분 30초 (09:30–09:42)", into: afterFirst)

        #expect(afterSecond == """
        \(heading)
        \(stats) 🍅 2회 · 총 37분 30초
        - 🍅 집중 25분 (09:00–09:25)
        \t- 할 일: - 🍅 집중 99분 (흉내)
        \t- 다음 시작점: 표 2부터
        - 🍅 집중 12분 30초 (09:30–09:42)

        """)
    }
}
