//
//  ReturnToFocusTests.swift
//  PomodoroTests
//
//  복귀(1.3): 휴식 중에 누르면 휴식을 지금까지로 기록하고, 다시 계획하지 않고 바로 집중을 시작합니다.
//  휴식 추천: 휴식 중에만, 마친 집중 수에 따라 돌아가며 보여 줍니다.
//

import Foundation
import SwiftData
import Testing
@testable import Pomodoro

@MainActor
struct ReturnToFocusTests {

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

    private func runOutTheClock() {
        clock.advance(viewModel.timeRemaining)
        viewModel.tick()
    }

    /// 집중을 끝까지 마치고 휴식을 고른 상태로 만듭니다.
    private func finishFocusAndStartBreak() {
        viewModel.startFocusSession()
        runOutTheClock()
        viewModel.startBreakAfterFocus()
    }

    // MARK: - 복귀

    @Test func 휴식_중에_복귀하면_휴식이_기록되고_바로_집중이_시작된다() throws {
        viewModel.focusTask = "제안서 서론"
        finishFocusAndStartBreak()
        #expect(viewModel.currentState == .shortBreak)
        #expect(viewModel.canReturnToFocus)

        clock.advance(60)
        viewModel.returnToFocus()

        #expect(viewModel.currentState == .focus)
        #expect(viewModel.timerState == .running)
        #expect(viewModel.completedFocusSessions == 1, "복귀는 집중 횟수를 바꾸지 않는다")
        #expect(viewModel.focusTask == "제안서 서론", "할 일을 다시 적지 않아도 된다")
        let logs = try loggedEntries()
        #expect(logs.map(\.sessionType) == [.focus, .shortBreak])
        #expect(abs((logs.last?.duration ?? 0) - 60) < 0.5, "휴식은 지금까지로 기록된다")
    }

    @Test func 멈춘_휴식에서도_복귀할_수_있다() throws {
        finishFocusAndStartBreak()
        clock.advance(30)
        viewModel.pauseTimer()
        clock.advance(600)
        #expect(viewModel.canReturnToFocus)
        viewModel.returnToFocus()
        #expect(viewModel.currentState == .focus)
        #expect(viewModel.timerState == .running)
        #expect(try loggedEntries().map(\.sessionType) == [.focus, .shortBreak])
    }

    @Test func 준비만_된_휴식에서_복귀하면_휴식_기록_없이_집중이_시작된다() throws {
        settings.autoStartBreaks = false
        viewModel.startFocusSession()
        clock.advance(120)
        viewModel.skipToNextSession() // 건너뛴 집중 → 휴식은 준비만 된다
        #expect(viewModel.currentState == .shortBreak)
        #expect(viewModel.timerState == .idle)
        #expect(viewModel.canReturnToFocus)

        viewModel.returnToFocus()
        #expect(viewModel.currentState == .focus)
        #expect(viewModel.timerState == .running)
        #expect(try loggedEntries().map(\.sessionType) == [.focus], "시작하지 않은 휴식은 기록하지 않는다")
    }

    @Test func 집중_중이나_선택을_기다릴_때는_복귀가_없다() {
        #expect(!viewModel.canReturnToFocus, "대기")
        viewModel.startFocusSession()
        #expect(!viewModel.canReturnToFocus, "집중 중")
        runOutTheClock()
        #expect(viewModel.timerState == .awaitingChoice)
        #expect(!viewModel.canReturnToFocus, "선택을 기다림")
        viewModel.returnToFocus()
        #expect(viewModel.timerState == .awaitingChoice, "눌러도 아무 일도 없다")
    }

    @Test func 전환_관리를_끄면_복귀가_없다() {
        settings.transitionManagementEnabled = false
        settings.autoStartBreaks = true
        viewModel.startFocusSession()
        runOutTheClock()
        #expect(viewModel.currentState == .shortBreak)
        #expect(!viewModel.canReturnToFocus)
        viewModel.returnToFocus()
        #expect(viewModel.currentState == .shortBreak)
    }

    // MARK: - 휴식 추천

    @Test func 휴식_추천은_휴식_중에만_보이고_휴식마다_바뀐다() {
        #expect(viewModel.breakSuggestion == nil, "대기")
        viewModel.startFocusSession()
        #expect(viewModel.breakSuggestion == nil, "집중 중")
        runOutTheClock()
        viewModel.startBreakAfterFocus()
        #expect(viewModel.breakSuggestion == BreakSuggestion.pick(0))

        runOutTheClock() // 휴식 끝 → 집중
        if viewModel.timerState == .idle { viewModel.startFocusSession() }
        runOutTheClock()
        viewModel.startBreakAfterFocus()
        #expect(viewModel.breakSuggestion == BreakSuggestion.pick(1))
    }

    @Test func 전환_관리를_끄면_휴식_추천도_없다() {
        settings.transitionManagementEnabled = false
        settings.autoStartBreaks = true
        viewModel.startFocusSession()
        runOutTheClock()
        #expect(viewModel.currentState == .shortBreak)
        #expect(viewModel.breakSuggestion == nil)
    }
}
