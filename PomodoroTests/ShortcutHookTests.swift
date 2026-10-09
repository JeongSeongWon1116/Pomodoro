//
//  ShortcutHookTests.swift
//  PomodoroTests
//
//  집중이 시작하고 끝날 때 설정에 적어 둔 단축어를 실행하는지, 가짜 실행기로 검증합니다.
//  (실제 단축어는 실행하지 않습니다.)
//

import Foundation
import SwiftData
import Testing
@testable import Pomodoro

/// 실행해 달라고 받은 단축어 이름을 차례로 적어 두는 가짜 실행기
@MainActor
final class ShortcutRecorder: ShortcutRunning {
    private(set) var names: [String] = []
    /// 실행 요청마다 받은 "전달됨" 알림. 테스트가 직접 불러 전달된 것처럼 만듭니다.
    private(set) var deliveries: [(() -> Void)?] = []
    func run(named name: String, completion: (() -> Void)?) {
        names.append(name)
        deliveries.append(completion)
    }
}

@MainActor
struct ShortcutHookTests {

    private let start = "집중 시작"
    private let end = "집중 끝"
    private let clock = TestClock()
    private let settings: AppSettings
    private let container: ModelContainer
    private let appDelegate = AppDelegate()
    private let recorder = ShortcutRecorder()
    private let viewModel: PomodoroViewModel

    init() throws {
        let settings = AppSettings(defaults: nil)
        settings.notificationSoundName = AppSettings.soundOff
        settings.focusStartShortcut = start
        settings.focusEndShortcut = end
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
            shortcuts: recorder,
            now: { clock.date }
        )
    }

    private func runOutTheClock() {
        clock.advance(viewModel.timeRemaining)
        viewModel.tick()
    }

    @Test func 집중을_시작하면_시작_단축어를_실행한다() {
        viewModel.startFocusSession()
        #expect(recorder.names == [start])
    }

    @Test func 집중_시간이_다_되면_끝_단축어를_실행하고_휴식을_골라도_다시_실행하지_않는다() {
        viewModel.startFocusSession()
        runOutTheClock()
        #expect(viewModel.timerState == .awaitingChoice)
        #expect(recorder.names == [start, end])

        viewModel.startBreakAfterFocus()
        #expect(recorder.names == [start, end])
    }

    @Test func 연장하면_시작_단축어를_다시_실행하고_연장이_끝나면_끝_단축어를_실행한다() {
        viewModel.startFocusSession()
        runOutTheClock()
        viewModel.extendFocus()
        #expect(recorder.names == [start, end, start])

        runOutTheClock()
        #expect(recorder.names == [start, end, start, end])
    }

    @Test(arguments: ["건너뛰기", "초기화", "종료"])
    func 집중을_도중에_그만두면_끝_단축어를_실행한다(how: String) {
        viewModel.startFocusSession()
        clock.advance(60)

        switch how {
        case "건너뛰기": viewModel.skipToNextSession()
        case "초기화": viewModel.resetToIdle()
        default:
            viewModel.logInterruptedSession()
            viewModel.logInterruptedSession() // '종료' 버튼과 앱 종료 알림이 둘 다 불러도 한 번만
        }

        // 건너뛰면 휴식이 이어서 시작되지만, 휴식에서는 아무것도 실행하지 않습니다.
        #expect(recorder.names == [start, end])
    }

    @Test(arguments: ["건너뛰기", "초기화", "종료"])
    func 연장한_집중을_도중에_그만둬도_끝_단축어는_한_번만_더_실행한다(how: String) {
        viewModel.startFocusSession()
        runOutTheClock()
        viewModel.extendFocus()
        clock.advance(60)

        switch how {
        case "건너뛰기": viewModel.skipToNextSession()
        case "초기화": viewModel.resetToIdle()
        default:
            viewModel.logInterruptedSession()
            viewModel.logInterruptedSession()
        }

        #expect(recorder.names == [start, end, start, end])
    }

    @Test(arguments: ["건너뛰기", "종료"])
    func 일시정지한_집중을_그만둬도_끝_단축어를_실행한다(how: String) {
        viewModel.startFocusSession()
        clock.advance(60)
        viewModel.pauseTimer()
        clock.advance(30)

        if how == "건너뛰기" { viewModel.skipToNextSession() } else { viewModel.logInterruptedSession() }

        #expect(recorder.names == [start, end])
    }

    @Test func 집중_도중에_전환_관리를_꺼도_끝날_때_끝_단축어를_한_번_실행한다() {
        viewModel.startFocusSession()
        clock.advance(60)
        settings.transitionManagementEnabled = false
        runOutTheClock() // 선택 없이 휴식으로 넘어감

        #expect(viewModel.currentState == .shortBreak)
        #expect(recorder.names == [start, end])
    }

    @Test func 선택을_기다리는_동안_전환_관리를_꺼도_끝_단축어를_다시_실행하지_않는다() {
        viewModel.startFocusSession()
        runOutTheClock()
        settings.transitionManagementEnabled = false
        viewModel.startBreakAfterFocus()

        #expect(recorder.names == [start, end])
    }

    @Test func 일시정지와_재개는_단축어를_실행하지_않고_정지한_채_초기화하면_끝_단축어를_실행한다() {
        viewModel.startFocusSession()
        clock.advance(60)
        viewModel.pauseTimer()
        clock.advance(30)
        viewModel.resumeTimer()
        viewModel.pauseTimer()
        #expect(recorder.names == [start])

        viewModel.resetToIdle()
        #expect(recorder.names == [start, end])
    }

    @Test(arguments: [true, false])
    func 선택을_기다리다_초기화하거나_종료해도_끝_단축어를_두_번_실행하지_않는다(quit: Bool) {
        viewModel.startFocusSession()
        runOutTheClock()
        if quit { viewModel.logInterruptedSession() } else { viewModel.resetToIdle() }

        #expect(recorder.names == [start, end])
    }

    @Test func 휴식이_시작하고_끝날_때는_실행하지_않고_다음_집중에서_다시_실행한다() {
        viewModel.startFocusSession()
        runOutTheClock()
        viewModel.startBreakAfterFocus()
        clock.advance(60)
        viewModel.tick()
        #expect(recorder.names == [start, end])

        runOutTheClock() // 휴식 끝 → 집중 자동 시작
        #expect(viewModel.currentState == .focus)
        #expect(recorder.names == [start, end, start])
    }

    @Test func 휴식을_초기화해도_끝_단축어를_실행하지_않는다() {
        viewModel.startFocusSession()
        runOutTheClock()
        viewModel.startBreakAfterFocus()
        viewModel.resetToIdle()

        #expect(recorder.names == [start, end])
    }

    @Test func 휴식을_건너뛰면_끝_단축어_없이_다음_집중의_시작_단축어만_실행한다() {
        viewModel.startFocusSession()
        runOutTheClock()
        viewModel.startBreakAfterFocus()
        clock.advance(10)
        viewModel.skipToNextSession() // 휴식을 건너뜀 → 집중 자동 시작

        #expect(viewModel.currentState == .focus)
        #expect(recorder.names == [start, end, start])
    }

    /// 휴식이 끝났지만 자동 시작이 꺼져 있어, 집중이 준비만 된 상태로 만듭니다.
    private func prepareFocusWithoutStarting() {
        settings.autoStartFocus = false
        viewModel.startFocusSession()
        runOutTheClock()
        viewModel.startBreakAfterFocus()
        runOutTheClock() // 휴식 끝 → 집중이 준비만 됨
    }

    @Test func 자동_시작이_꺼져_준비만_된_집중은_직접_시작할_때_실행한다() {
        prepareFocusWithoutStarting()
        #expect(viewModel.currentState == .focus)
        #expect(viewModel.timerState == .idle)
        #expect(recorder.names == [start, end])

        viewModel.startFocusSession() // 준비된 집중을 그대로 시작
        #expect(viewModel.timerState == .running)
        #expect(recorder.names == [start, end, start])
    }

    @Test func 시작한_적_없는_준비된_집중을_치워도_끝_단축어를_실행하지_않는다() {
        prepareFocusWithoutStarting()
        viewModel.resetToIdle()

        #expect(viewModel.currentState == .idle)
        #expect(recorder.names == [start, end])
    }

    @Test func 전환_관리를_꺼도_집중의_시작과_끝에_실행한다() {
        settings.transitionManagementEnabled = false
        viewModel.startFocusSession()
        runOutTheClock() // 선택 없이 휴식으로 넘어감

        #expect(viewModel.currentState == .shortBreak)
        #expect(recorder.names == [start, end])
    }

    @Test func 이름을_비워_두면_실행하지_않고_앞뒤_공백은_떼고_실행한다() {
        settings.focusStartShortcut = "   "
        settings.focusEndShortcut = "  방해금지 끄기\n"
        viewModel.startFocusSession()
        #expect(recorder.names.isEmpty)

        runOutTheClock()
        #expect(recorder.names == ["방해금지 끄기"])
    }

    // MARK: - 종료할 때

    @Test func 집중_도중에_종료하면_끝_단축어가_전달된_뒤에_알려_준다() {
        viewModel.startFocusSession()
        clock.advance(60)
        var delivered = false

        let mustWait = viewModel.logInterruptedSession(shortcutDelivered: { delivered = true })

        #expect(mustWait) // 부른 쪽은 알림이 올 때까지 종료를 미룹니다
        #expect(recorder.names == [start, end])
        #expect(!delivered)
        recorder.deliveries.last??()
        #expect(delivered)
    }

    @Test(arguments: ["대기", "휴식", "선택 대기", "끝 단축어 없음"])
    func 실행할_끝_단축어가_없으면_종료를_기다리게_하지_않는다(situation: String) {
        switch situation {
        case "대기": break
        case "휴식":
            viewModel.startFocusSession()
            runOutTheClock()
            viewModel.startBreakAfterFocus()
        case "선택 대기":
            viewModel.startFocusSession()
            runOutTheClock()
        default:
            settings.focusEndShortcut = ""
            viewModel.startFocusSession()
            clock.advance(60)
        }
        let before = recorder.names
        var delivered = false

        let mustWait = viewModel.logInterruptedSession(shortcutDelivered: { delivered = true })

        #expect(!mustWait)
        #expect(!delivered)
        #expect(recorder.names == before)
    }

    @Test func 적어_둔_단축어_이름은_저장소가_있으면_앱을_다시_켜도_남는다() throws {
        let suite = "PomodoroTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppSettings(defaults: defaults)
        #expect(first.focusStartShortcut == "")
        first.focusStartShortcut = "방해금지 켜기"
        first.focusEndShortcut = "방해금지 끄기"

        let second = AppSettings(defaults: defaults)
        #expect(second.focusStartShortcut == "방해금지 켜기")
        #expect(second.focusEndShortcut == "방해금지 끄기")
    }
}

// MARK: - 단축어 주소

struct ShortcutURLTests {

    @Test func 단축어를_실행하는_주소를_만든다() {
        #expect(URLShortcutRunner.url(forShortcutNamed: "Focus On")?.absoluteString == "shortcuts://run-shortcut?name=Focus%20On")
    }

    @Test func 주소에_뜻이_있는_글자는_이름의_일부로_남도록_바꿔_넣는다() {
        #expect(URLShortcutRunner.url(forShortcutNamed: "A b&c+d=e#f?g")?.absoluteString
            == "shortcuts://run-shortcut?name=A%20b%26c%2Bd%3De%23f%3Fg")
    }

    @Test(arguments: ["집중 시작", "방해금지 켜기 & 알림 끄기", "50% 집중+휴식", "a/b?c=d#e"])
    func 어떤_이름이든_주소에서_다시_읽으면_그대로다(name: String) throws {
        let url = try #require(URLShortcutRunner.url(forShortcutNamed: name))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "shortcuts")
        #expect(components.host == "run-shortcut")
        #expect(components.queryItems?.count == 1)
        #expect(components.queryItems?.first?.name == "name")
        #expect(components.queryItems?.first?.value == name)
    }

    @Test func 자모가_풀린_한글_이름도_합친_형태의_이름과_같은_주소가_된다() {
        let composed = "집중 시작"
        let decomposed = composed.decomposedStringWithCanonicalMapping
        #expect(decomposed.unicodeScalars.count > composed.unicodeScalars.count)
        #expect(URLShortcutRunner.url(forShortcutNamed: decomposed) == URLShortcutRunner.url(forShortcutNamed: composed))
    }

    @Test func 빈_이름으로는_주소를_만들지_않는다() {
        #expect(URLShortcutRunner.url(forShortcutNamed: "") == nil)
        #expect(URLShortcutRunner.url(forShortcutNamed: "  \n") == nil)
    }
}
