//
//  TimerStateMachineTests.swift
//  PomodoroTests
//
//  PomodoroViewModel 의 타이머 상태 기계를 주입한 시계로 검증합니다.
//  (실제 시간을 기다리지 않고, 사용자의 설정·기록·보관함을 건드리지 않습니다.)
//

import Foundation
import SwiftData
import Testing
@testable import Pomodoro

/// 테스트가 마음대로 앞으로 돌릴 수 있는 시계
@MainActor
final class TestClock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}

@MainActor
struct TimerStateMachineTests {

    private let clock = TestClock()
    private let settings: AppSettings
    private let container: ModelContainer
    private let appDelegate = AppDelegate()
    private let viewModel: PomodoroViewModel

    init() throws {
        // 저장소 없는 설정: 기본값(집중 25분, 짧은 휴식 5분, 긴 휴식 간격 4)으로 시작하고 아무것도 저장하지 않습니다.
        let settings = AppSettings(defaults: nil)
        settings.notificationSoundName = AppSettings.soundOff
        self.settings = settings
        container = try ModelContainer(
            for: FocusLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let clock = self.clock
        viewModel = PomodoroViewModel(
            modelContext: container.mainContext,
            appDelegate: appDelegate,
            settings: settings,
            now: { clock.date }
        )
    }

    private func loggedEntries() throws -> [FocusLogEntry] {
        try container.mainContext.fetch(FetchDescriptor<FocusLogEntry>(sortBy: [SortDescriptor(\.startTime)]))
    }

    /// 현재 세션을 끝까지 흘려보냅니다.
    private func finishCurrentSession() {
        clock.advance(viewModel.timeRemaining)
        viewModel.tick()
    }

    @Test func 시작_정지_재개_후에도_활동_시간과_정지_시간이_정확하다() throws {
        viewModel.startFocusSession()
        #expect(viewModel.currentState == .focus)
        #expect(viewModel.timerState == .running)

        clock.advance(60)
        viewModel.pauseTimer()
        #expect(viewModel.timerState == .paused)

        clock.advance(30) // 정지 중에는 남은 시간이 줄지 않습니다
        viewModel.resumeTimer()
        #expect(viewModel.timerState == .running)
        #expect(viewModel.timeRemaining == 25 * 60 - 60)

        clock.advance(120)
        viewModel.tick()
        #expect(viewModel.timeRemaining == 25 * 60 - 180)

        viewModel.resetToIdle()
        let entries = try loggedEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.duration == 180)
        #expect(entries.first?.pausedDuration == 30)
        #expect(entries.first?.sessionType == .focus)
    }

    @Test func 끝까지_마친_집중은_사이클_횟수를_올린다() throws {
        viewModel.startFocusSession()
        finishCurrentSession()

        #expect(viewModel.completedFocusSessions == 1)
        #expect(viewModel.currentState == .shortBreak)
        #expect(try loggedEntries().first?.duration == 25 * 60)
    }

    @Test func 건너뛴_집중은_완료로_세지_않는다() {
        viewModel.startFocusSession()
        clock.advance(10)
        viewModel.skipToNextSession()

        #expect(viewModel.completedFocusSessions == 0)
        #expect(viewModel.currentState == .shortBreak)
    }

    @Test func 긴_휴식_직전의_집중을_건너뛰면_긴_휴식이_오지_않는다() {
        settings.longBreakInterval = 2
        viewModel.startFocusSession()
        finishCurrentSession() // 집중 1회 완료 → 짧은 휴식
        finishCurrentSession() // 짧은 휴식 끝 → 집중
        #expect(viewModel.currentState == .focus)

        clock.advance(10)
        viewModel.skipToNextSession()
        #expect(viewModel.completedFocusSessions == 1)
        #expect(viewModel.currentState == .shortBreak)
    }

    @Test func 간격만큼_집중을_마치면_긴_휴식이_온다() {
        settings.longBreakInterval = 2
        viewModel.startFocusSession()
        finishCurrentSession()
        #expect(viewModel.currentState == .shortBreak)
        finishCurrentSession()
        finishCurrentSession()
        #expect(viewModel.completedFocusSessions == 2)
        #expect(viewModel.currentState == .longBreak)
    }

    @Test(arguments: [0, -3])
    func 긴_휴식_간격이_0이나_음수여도_죽지_않는다(interval: Int) {
        settings.longBreakInterval = interval
        viewModel.startFocusSession()
        finishCurrentSession()

        // 간격은 최소 1로 취급: 집중을 마칠 때마다 긴 휴식
        #expect(viewModel.completedFocusSessions == 1)
        #expect(viewModel.currentState == .longBreak)
    }

    @Test func 저장된_긴_휴식_간격이_0이나_음수면_1로_읽는다() {
        #expect(AppSettings.validLongBreakInterval(0) == 1)
        #expect(AppSettings.validLongBreakInterval(-3) == 1)
        #expect(AppSettings.validLongBreakInterval(4) == 4)
    }

    @Test func 종료할_때_진행_중인_세션을_중단된_기록으로_남긴다() throws {
        viewModel.startFocusSession()
        clock.advance(100)
        viewModel.pauseTimer()
        clock.advance(20)
        viewModel.resumeTimer()
        clock.advance(200)

        viewModel.logInterruptedSession()
        viewModel.logInterruptedSession() // '종료' 버튼과 앱 종료 알림이 둘 다 불러도 한 번만 남습니다

        let entries = try loggedEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.duration == 300)
        #expect(entries.first?.pausedDuration == 20)
        #expect(entries.first?.sessionType == .focus)
        #expect(entries.first?.endTime == clock.date)
    }

    @Test func 대기_상태에서_종료하면_기록을_남기지_않는다() throws {
        viewModel.logInterruptedSession()
        #expect(try loggedEntries().isEmpty)
    }
}
