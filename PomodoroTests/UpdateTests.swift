// File: UpdateTests.swift
// Description: 자동 업데이트에서 Sparkle 바깥에 있는 우리 쪽 판단을 검사합니다.
// (받아 둔 업데이트를 언제 설치할지, 지금이 조용한 때인지, 이 빌드가 업데이트를 쓸 수 있는지)

import Testing
import AppKit
import Foundation
@testable import Pomodoro

/// 테스트가 손으로 돌리는 시계 (앱은 깨어 있는 동안만 가는 시계를 씁니다)
@MainActor
private final class UpdateTestClock {
    var time: TimeInterval = 1_000
    func advance(_ seconds: TimeInterval) { time += seconds }
}

@MainActor
struct UpdateInstallGateTests {
    private let clock = UpdateTestClock()

    private func makeGate(settle: TimeInterval = 60, timeout: TimeInterval = 30) -> UpdateInstallGate {
        UpdateInstallGate(settleTime: settle, installTimeout: timeout, now: { [clock] in clock.time })
    }

    @Test func 맡기는_것만으로는_설치하지_않는다() {
        // 설치 동작은 Sparkle 의 대리자 호출이 끝난 뒤에만 써야 합니다. 조용함도 맡긴 뒤부터 셉니다.
        let gate = makeGate(settle: 0)
        var installs = 0
        gate.update(quiet: true)
        gate.hold { installs += 1 }
        #expect(installs == 0)
        #expect(gate.hasPendingInstall)
    }

    @Test func 조용함이_정해진_시간_이어지면_한_번_설치한다() {
        let gate = makeGate(settle: 60)
        var installs = 0
        gate.hold { installs += 1 }
        gate.update(quiet: true)
        #expect(installs == 0)
        clock.advance(59)
        gate.update(quiet: true)
        #expect(installs == 0)
        clock.advance(1)
        gate.update(quiet: true)
        #expect(installs == 1)
    }

    @Test func 중간에_바빠지면_처음부터_다시_센다() {
        // 팝오버를 닫고 곧바로 설정 창을 여는 것처럼, 잠깐 조용해 보이는 틈에 설치하면 안 됩니다.
        let gate = makeGate(settle: 60)
        var installs = 0
        gate.hold { installs += 1 }
        gate.update(quiet: true)
        clock.advance(30)
        gate.update(quiet: false)
        clock.advance(10)
        gate.update(quiet: true)
        clock.advance(59)
        gate.update(quiet: true)
        #expect(installs == 0)
        clock.advance(1)
        gate.update(quiet: true)
        #expect(installs == 1)
    }

    @Test func 설치를_시작한_뒤에는_다시_재도_또_실행하지_않는다() {
        let gate = makeGate(settle: 0)
        var installs = 0
        gate.hold { installs += 1 }
        gate.update(quiet: true)
        #expect(installs == 1)
        gate.update(quiet: true)
        gate.update(quiet: false)
        gate.update(quiet: true)
        #expect(installs == 1)
        #expect(gate.isInstallingOnItsOwn)
        #expect(gate.hasPendingInstall) // 종료가 취소되면 다시 써야 하므로 버리지 않습니다
    }

    @Test func 설치하는_도중에_다시_불려도_두_번_설치하지_않는다() {
        // 설치 동작은 앱을 끝내면서 상태 변화를 일으킬 수 있습니다. 그 안에서 다시 알림이 와도 한 번만 실행합니다.
        let gate = makeGate(settle: 0)
        var installs = 0
        gate.hold {
            installs += 1
            gate.update(quiet: true)
        }
        gate.update(quiet: true)
        #expect(installs == 1)
    }

    @Test func 종료가_취소되면_다시_조용해진_뒤에_또_설치한다() {
        // 설치하려고 끄는 사이에 사용자가 집중을 시작했다 → 종료를 취소하고, 나중에 다시 설치합니다.
        let gate = makeGate(settle: 60)
        var installs = 0
        gate.hold { installs += 1 }
        gate.update(quiet: true)
        clock.advance(60)
        gate.update(quiet: true)
        #expect(installs == 1)

        gate.installWasInterrupted()
        #expect(!gate.isInstallingOnItsOwn)
        #expect(gate.hasPendingInstall)
        gate.update(quiet: true)
        clock.advance(59)
        gate.update(quiet: true)
        #expect(installs == 1)
        clock.advance(1)
        gate.update(quiet: true)
        #expect(installs == 2)
    }

    @Test func 설치를_시작했는데_앱이_꺼지지_않으면_기다렸다가_다시_한다() {
        let gate = makeGate(settle: 10, timeout: 30)
        var installs = 0
        gate.hold { installs += 1 }
        gate.update(quiet: true)
        clock.advance(10)
        gate.update(quiet: true)
        #expect(installs == 1)

        clock.advance(29)
        gate.update(quiet: true)
        #expect(installs == 1)
        #expect(gate.isInstallingOnItsOwn)

        clock.advance(1) // 30초가 지나도 앱이 살아 있다 → 다시 붙잡고 조용함을 처음부터 센다
        gate.update(quiet: true)
        #expect(installs == 1)
        #expect(!gate.isInstallingOnItsOwn)
        clock.advance(10)
        gate.update(quiet: true)
        #expect(installs == 2)
    }

    @Test func 다시_맡기면_나중_것만_설치한다() {
        let gate = makeGate(settle: 0)
        var installed: [String] = []
        gate.hold { installed.append("처음") }
        gate.hold { installed.append("나중") }
        gate.update(quiet: true)
        #expect(installed == ["나중"])
    }

    @Test func 버리면_조용해져도_설치하지_않는다() {
        let gate = makeGate(settle: 0)
        var installs = 0
        gate.hold { installs += 1 }
        gate.discard()
        #expect(!gate.hasPendingInstall)
        gate.update(quiet: true)
        #expect(installs == 0)
        #expect(!gate.isInstallingOnItsOwn)
    }

    @Test func 사용자가_지금_설치를_누르면_바빠도_실행한다() {
        let gate = makeGate(settle: 60)
        var installs = 0
        gate.hold { installs += 1 }
        gate.update(quiet: false)
        gate.installNow()
        #expect(installs == 1)
        // 사용자가 고른 종료이므로, 조용하지 않다는 이유로 취소하면 안 됩니다.
        #expect(!gate.isInstallingOnItsOwn)
    }

    @Test func 맡긴_것이_없으면_지금_설치는_아무것도_하지_않는다() {
        let gate = makeGate(settle: 0)
        gate.installNow()
        gate.update(quiet: true)
        #expect(!gate.hasPendingInstall)
        #expect(!gate.isInstallingOnItsOwn)
    }

    @Test func 설치가_진행_중이면_지금_설치를_또_눌러도_다시_실행하지_않는다() {
        let gate = makeGate(settle: 0, timeout: 30)
        var installs = 0
        gate.hold { installs += 1 }
        gate.installNow()
        gate.installNow()
        gate.update(quiet: true)
        #expect(installs == 1)
        #expect(gate.isInstalling)
        clock.advance(30) // 한참 지나도 앱이 살아 있으면 다시 누를 수 있습니다
        gate.installNow()
        #expect(installs == 2)
    }

    @Test func 스스로_설치를_막아_두면_조용해도_설치하지_않고_풀면_다시_센다() {
        // 설정에서 "자동 설치"를 끈 경우. 붙잡은 것은 버리지 않습니다 — 다시 켜면 이어서 해야 합니다.
        let gate = makeGate(settle: 60)
        var installs = 0
        gate.hold { installs += 1 }
        gate.allowsAutomaticInstall = false
        gate.update(quiet: true)
        clock.advance(600)
        gate.update(quiet: true)
        #expect(installs == 0)
        #expect(gate.hasPendingInstall)

        gate.allowsAutomaticInstall = true
        gate.update(quiet: true)
        #expect(installs == 0) // 막혀 있던 동안의 조용함은 세지 않습니다
        clock.advance(60)
        gate.update(quiet: true)
        #expect(installs == 1)
    }

    @Test func 스스로_설치를_막아_두어도_지금_설치는_된다() {
        let gate = makeGate(settle: 60)
        var installs = 0
        gate.hold { installs += 1 }
        gate.allowsAutomaticInstall = false
        gate.installNow()
        #expect(installs == 1)
    }
}

struct UpdateQuietnessTests {

    @Test func 타이머가_완전히_대기이고_열린_창이_없을_때만_조용하다() {
        #expect(UpdateQuietness.isQuiet(currentState: .idle, timerState: .idle, popoverShown: false, openWindows: 0))
    }

    @Test func 세션이_돌거나_멈춰_있거나_선택을_기다리면_조용하지_않다() {
        for timer in [TimerState.running, .paused, .awaitingChoice] {
            #expect(!UpdateQuietness.isQuiet(currentState: .focus, timerState: timer, popoverShown: false, openWindows: 0))
        }
        #expect(!UpdateQuietness.isQuiet(currentState: .shortBreak, timerState: .running, popoverShown: false, openWindows: 0))
        #expect(!UpdateQuietness.isQuiet(currentState: .longBreak, timerState: .paused, popoverShown: false, openWindows: 0))
    }

    @Test func 다음_세션을_준비만_해_둔_대기는_조용하지_않다() {
        // 자동 시작이 꺼져 있으면 타이머는 멈춰 있어도 다음 세션과 사이클 횟수를 들고 있습니다.
        // 이때 다시 켜면 긴 휴식까지의 횟수를 잃습니다.
        for state in [PomodoroState.focus, .shortBreak, .longBreak] {
            #expect(!UpdateQuietness.isQuiet(currentState: state, timerState: .idle, popoverShown: false, openWindows: 0))
        }
    }

    @Test func 팝오버나_창이_열려_있으면_조용하지_않다() {
        #expect(!UpdateQuietness.isQuiet(currentState: .idle, timerState: .idle, popoverShown: true, openWindows: 0))
        #expect(!UpdateQuietness.isQuiet(currentState: .idle, timerState: .idle, popoverShown: false, openWindows: 1))
    }

    @Test func 제목_줄이_있는_창만_열린_창으로_센다() {
        // 메뉴 바 항목과 팝오버도 창이지만 제목 줄이 없습니다. 이것까지 세면 영영 조용해지지 않습니다.
        #expect(UpdateQuietness.openWindowCount([(visible: true, miniaturized: false, titled: false)]) == 0)
        #expect(UpdateQuietness.openWindowCount([(visible: true, miniaturized: false, titled: true)]) == 1)
    }

    @Test func 최소화한_창도_열린_창이다() {
        // Dock 에 내려 둔 기록·설정 창은 보이지 않지만 닫힌 것이 아닙니다. 다시 켜면 사라집니다.
        #expect(UpdateQuietness.openWindowCount([(visible: false, miniaturized: true, titled: true)]) == 1)
    }

    @Test func 앱이_가려져_있으면_가려지기_전에_열려_있던_창을_센다() {
        // "가리기"를 하면 창이 보이지 않게 되지만 닫힌 것이 아닙니다. 가려지기 직전에 센 수를 씁니다.
        #expect(UpdateQuietness.effectiveOpenWindows(live: 0, appHidden: true, countBeforeHide: 1) == 1)
        #expect(UpdateQuietness.effectiveOpenWindows(live: 0, appHidden: true, countBeforeHide: 0) == 0)
        // 가려진 채로 켜져서 가려지기 전을 센 적이 없으면 지금 센 수를 씁니다.
        #expect(UpdateQuietness.effectiveOpenWindows(live: 0, appHidden: true, countBeforeHide: nil) == 0)
        // 가려져 있지 않으면 지금 센 수만 봅니다.
        #expect(UpdateQuietness.effectiveOpenWindows(live: 2, appHidden: false, countBeforeHide: 5) == 2)
        #expect(UpdateQuietness.effectiveOpenWindows(live: 0, appHidden: false, countBeforeHide: 1) == 0)
    }

    @Test func 닫힌_창은_세지_않는다() {
        #expect(UpdateQuietness.openWindowCount([(visible: false, miniaturized: false, titled: true)]) == 0)
        #expect(UpdateQuietness.openWindowCount([]) == 0)
        #expect(UpdateQuietness.openWindowCount([
            (visible: true, miniaturized: false, titled: true),
            (visible: false, miniaturized: true, titled: true),
            (visible: true, miniaturized: false, titled: false),
            (visible: false, miniaturized: false, titled: true)
        ]) == 2)
    }
}

struct TerminationRequestTests {
    @Test func 앱_안에서_부른_종료에는_종료_이벤트가_없다() {
        #expect(TerminationRequest.classify(isQuitEvent: false, hasQuitReason: false) == .fromThisApp)
        // 다른 Apple 이벤트를 처리하다가 앱이 스스로 끝내는 경우도 앱 안의 종료로 봅니다.
        #expect(TerminationRequest.classify(isQuitEvent: false, hasQuitReason: true) == .fromThisApp)
    }

    @Test func 이유가_붙은_종료_이벤트는_로그아웃이나_시스템_종료다() {
        #expect(TerminationRequest.classify(isQuitEvent: true, hasQuitReason: true) == .fromSystem)
    }

    @Test func 이유_없는_종료_이벤트는_다른_프로세스가_끄는_것이다() {
        #expect(TerminationRequest.classify(isQuitEvent: true, hasQuitReason: false) == .fromAnotherProcess)
    }

    @Test @MainActor func 테스트가_부르는_동안에는_처리_중인_종료_이벤트가_없다() {
        #expect(TerminationRequest.current == .fromThisApp)
    }
}

struct UpdateSettingsCaptionTests {
    @Test func 자동_확인이_꺼져_있으면_알려_준다고_하지_않는다() {
        let text = UpdateSettingsSection.caption(hasPending: false, automaticallyChecks: false, automaticallyInstalls: true)
        #expect(text.contains("자동 확인이 꺼져"))
        #expect(!text.contains("알려 주기만"))
        #expect(!text.contains("스스로 설치") && !text.contains("다시 켜면서 설치"))
    }

    @Test func 자동_설치만_꺼져_있으면_알려_주기만_한다고_적는다() {
        let text = UpdateSettingsSection.caption(hasPending: false, automaticallyChecks: true, automaticallyInstalls: false)
        #expect(text.contains("알려 주기만"))
    }

    @Test func 받아_둔_것이_있으면_자동_설치_여부에_따라_적는다() {
        let on = UpdateSettingsSection.caption(hasPending: true, automaticallyChecks: false, automaticallyInstalls: true)
        #expect(on.contains("스스로 설치하고 다시 켭니다") && on.contains("팝오버"))
        let off = UpdateSettingsSection.caption(hasPending: true, automaticallyChecks: true, automaticallyInstalls: false)
        #expect(off.contains("스스로 설치하지 않습니다"))
    }
}

struct UpdaterConfigurationTests {

    // 32바이트를 base64 로 적은 것 (실제 키가 아닙니다. 0x00 ~ 0x1f)
    private let sampleKey = Data((0..<32).map { UInt8($0) }).base64EncodedString()
    private let feed = "https://example.com/appcast.xml"

    @Test func 주소와_키가_있으면_쓴다() {
        let config = UpdaterConfiguration(info: ["SUFeedURL": feed, "SUPublicEDKey": sampleKey])
        #expect(config.isUsable)
        #expect(config.feedURL == URL(string: feed))
        #expect(config.disabledReason == nil)
    }

    @Test func 공개_키가_비어_있으면_쓰지_않는다() {
        let config = UpdaterConfiguration(info: ["SUFeedURL": feed, "SUPublicEDKey": ""])
        #expect(!config.isUsable)
        #expect(config.disabledReason != nil)
    }

    @Test func 키가_없거나_주소가_없으면_쓰지_않는다() {
        #expect(!UpdaterConfiguration(info: ["SUFeedURL": feed]).isUsable)
        #expect(!UpdaterConfiguration(info: ["SUPublicEDKey": sampleKey]).isUsable)
        #expect(!UpdaterConfiguration(info: [:]).isUsable)
    }

    @Test func 채워지지_않은_빌드_설정_자리표시는_쓰지_않는다() {
        #expect(!UpdaterConfiguration(info: ["SUFeedURL": "$(POMODORO_FEED_URL)", "SUPublicEDKey": sampleKey]).isUsable)
        #expect(!UpdaterConfiguration(info: ["SUFeedURL": feed, "SUPublicEDKey": "$(POMODORO_ED_PUBLIC_KEY)"]).isUsable)
    }

    @Test func 키가_32바이트가_아니면_쓰지_않는다() {
        let short = Data((0..<16).map { UInt8($0) }).base64EncodedString()
        #expect(!UpdaterConfiguration(info: ["SUFeedURL": feed, "SUPublicEDKey": short]).isUsable)
        #expect(!UpdaterConfiguration(info: ["SUFeedURL": feed, "SUPublicEDKey": "base64가 아닌 글"]).isUsable)
    }

    @Test func 웹_주소가_아니면_쓰지_않는다() {
        #expect(!UpdaterConfiguration(info: ["SUFeedURL": "file:///tmp/appcast.xml", "SUPublicEDKey": sampleKey]).isUsable)
        #expect(!UpdaterConfiguration(info: ["SUFeedURL": "appcast.xml", "SUPublicEDKey": sampleKey]).isUsable)
    }

    @Test func 암호화하지_않은_주소는_이_컴퓨터를_가리킬_때만_쓴다() {
        // http 는 중간에서 업데이트 목록을 바꾸거나 막을 수 있습니다. 시험용(localhost)만 받습니다.
        #expect(!UpdaterConfiguration(info: ["SUFeedURL": "http://example.com/appcast.xml", "SUPublicEDKey": sampleKey]).isUsable)
        #expect(!UpdaterConfiguration(info: ["SUFeedURL": "http://localhost.example.com/appcast.xml", "SUPublicEDKey": sampleKey]).isUsable)
        #expect(UpdaterConfiguration(info: ["SUFeedURL": "http://localhost:18731/appcast.xml", "SUPublicEDKey": sampleKey]).isUsable)
        #expect(UpdaterConfiguration(info: ["SUFeedURL": "http://127.0.0.1:18731/appcast.xml", "SUPublicEDKey": sampleKey]).isUsable)
    }

    @Test func 앞뒤_공백은_무시한다() {
        let config = UpdaterConfiguration(info: ["SUFeedURL": "  \(feed)\n", "SUPublicEDKey": " \(sampleKey) "])
        #expect(config.isUsable)
        #expect(config.feedURL == URL(string: feed))
    }

    @Test func 앱_묶음에_업데이트_설정이_들어_있다() {
        // 테스트 호스트(앱)의 Info.plist — 프로젝트 설정이 실제로 묶음에 들어갔는지 봅니다.
        let info = Bundle.main.infoDictionary ?? [:]
        #expect(info["SUFeedURL"] as? String == "https://github.com/JeongSeongWon1116/Pomodoro/releases/latest/download/appcast.xml")
        #expect(info["SUPublicEDKey"] is String)
        #expect(info["SUEnableInstallerLauncherService"] as? Bool == true)
        #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(info["SUAutomaticallyUpdate"] as? Bool == true)
        // 메뉴 바 앱 설정이 덮어써지지 않았는지도 봅니다.
        #expect(info["LSUIElement"] as? Bool == true)
    }
}

@MainActor
struct UpdateControllerTests {
    private let clock = UpdateTestClock()

    private var usable: UpdaterConfiguration {
        UpdaterConfiguration(info: [
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": Data((0..<32).map { UInt8($0) }).base64EncodedString()
        ])
    }

    private func makeController(settle: TimeInterval = 0) -> UpdateController {
        UpdateController(
            configuration: usable,
            gate: UpdateInstallGate(settleTime: settle, installTimeout: 30, now: { [clock] in clock.time }),
            now: { [clock] in clock.time }
        )
    }

    // 켤지 말지: 셋 가운데 하나라도 걸리면 켜지 않습니다. 한 조건씩만 걸어 봅니다
    // (테스트는 개발 빌드로 돌기 때문에, 한꺼번에 보면 다른 조건이 가려 줍니다).
    @Test func 테스트_호스트에서는_업데이터를_켜지_않는다() {
        #expect(UpdateController.whyNotStarting(isRunningTests: true, isDebugBuild: false, configuration: usable) != nil)
    }

    @Test func 개발_빌드에서는_켜지_않는다() {
        // Xcode에서 실행한 개발 빌드가 릴리스를 받아 자기 자신을 바꾸면 안 됩니다.
        let reason = UpdateController.whyNotStarting(isRunningTests: false, isDebugBuild: true, configuration: usable)
        #expect(reason?.contains("개발 빌드") == true)
    }

    @Test func 쓸_수_없는_설정이면_켜지_않고_이유를_알려_준다() {
        let config = UpdaterConfiguration(info: [:])
        let reason = UpdateController.whyNotStarting(isRunningTests: false, isDebugBuild: false, configuration: config)
        #expect(reason != nil)
        #expect(reason == config.disabledReason)
    }

    @Test func 걸리는_것이_없으면_켠다() {
        #expect(UpdateController.whyNotStarting(isRunningTests: false, isDebugBuild: false, configuration: usable) == nil)
    }

    @Test func 지금_이_테스트_호스트의_업데이터는_꺼져_있다() {
        // 단위 테스트가 네트워크로 업데이트를 찾거나 설치 창을 띄우면 안 됩니다.
        let controller = makeController()
        controller.start()
        #expect(!controller.isEnabled)
        #expect(!controller.canCheckForUpdates)
        #expect(controller.statusText != nil)
        #expect(!UpdateController.shared.isEnabled)
    }

    @Test func 받아_둔_업데이트는_붙잡아_두고_조용해지면_설치한다() {
        let controller = makeController(settle: 60)
        var quiet = false
        controller.quietProbe = { quiet }
        var installs = 0

        controller.holdInstall(version: "1.2.1") { installs += 1 }
        #expect(installs == 0)
        #expect(controller.pendingVersion == "1.2.1")

        controller.reevaluateQuietness()
        #expect(installs == 0)

        quiet = true
        controller.reevaluateQuietness()
        clock.advance(60)
        controller.reevaluateQuietness()
        #expect(installs == 1)
    }

    @Test func 조용할_때_받아도_맡기는_호출_안에서는_설치하지_않는다() {
        // Sparkle 은 대리자가 "내가 설치하겠다"고 답한 뒤에만 설치 동작을 쓰게 합니다.
        let controller = makeController(settle: 0)
        controller.quietProbe = { true }
        var installs = 0
        controller.holdInstall(version: "1.2.1") { installs += 1 }
        #expect(installs == 0)
        controller.reevaluateQuietness()
        #expect(installs == 1)
    }

    @Test func 설치를_넘기기_직전에_바빠졌으면_미루고_다시_붙잡는다() {
        // Sparkle 은 설치를 넘기기 직전에 한 번 "미룰까"를 묻습니다. 그 사이 집중을 시작했으면 미룹니다.
        let controller = makeController(settle: 0)
        var quiet = true
        controller.quietProbe = { quiet }
        var installs = 0
        controller.holdInstall(version: "1.2.1") { installs += 1 }
        controller.reevaluateQuietness()
        #expect(installs == 1)

        quiet = false
        var resumed = 0
        #expect(controller.shouldPostponeRelaunch { resumed += 1 })
        #expect(!controller.gate.isInstalling)

        quiet = true
        controller.reevaluateQuietness()
        #expect(resumed == 1) // 미룬 뒤에는 Sparkle 이 준 "이어서 하기"를 실행합니다
        #expect(installs == 1)
    }

    @Test func 조용한_채로면_미루지_않는다() {
        let controller = makeController(settle: 0)
        controller.quietProbe = { true }
        controller.holdInstall(version: "1.2.1") {}
        controller.reevaluateQuietness()
        #expect(!controller.shouldPostponeRelaunch {})
    }

    @Test func 사용자가_누른_설치는_바빠도_미루지_않는다() {
        let controller = makeController(settle: 60)
        controller.quietProbe = { false }
        controller.holdInstall(version: "1.2.1") {}
        controller.installPendingUpdateNow()
        #expect(!controller.shouldPostponeRelaunch {})
    }

    @Test func Sparkle이_끄는_순간에_바빠졌으면_종료를_막고_다시_붙잡는다() {
        let controller = makeController(settle: 0)
        var quiet = true
        controller.quietProbe = { quiet }
        var installs = 0
        controller.holdInstall(version: "1.2.1") { installs += 1 }
        controller.reevaluateQuietness()
        #expect(installs == 1)
        controller.sparkleWillRelaunch() // Sparkle 이 "이제 끄고 다시 켠다"고 알림

        quiet = false // 종료 요청이 닿기 전에 사용자가 집중을 시작했다
        #expect(controller.shouldCancelTermination(.fromAnotherProcess))
        #expect(!controller.shouldCancelTermination(.fromAnotherProcess)) // 한 번만 막습니다
        #expect(controller.pendingVersion == "1.2.1")

        quiet = true
        controller.reevaluateQuietness()
        #expect(installs == 2)
    }

    @Test func 종료를_한_번_막은_뒤_다시_설치할_때도_끄는_순간에_다시_본다() {
        // Sparkle 은 "이제 끈다"는 알림을 설치 하나에 한 번만 보냅니다. 종료를 막은 뒤의 재시도에는 알림이 다시 오지 않습니다.
        let controller = makeController(settle: 0)
        var quiet = true
        controller.quietProbe = { quiet }
        var installs = 0
        controller.holdInstall(version: "1.2.1") { installs += 1 }
        controller.reevaluateQuietness()
        controller.sparkleWillRelaunch()
        quiet = false
        #expect(controller.shouldCancelTermination(.fromAnotherProcess))

        quiet = true
        clock.advance(60) // 알림은 한참 전의 일이 됐다
        controller.reevaluateQuietness() // 재시도 — Sparkle 은 다시 알리지 않는다
        #expect(installs == 2)
        quiet = false // 이번에도 종료 요청이 닿기 전에 팝오버를 열었다
        #expect(controller.shouldCancelTermination(.fromAnotherProcess))
        #expect(controller.pendingVersion == "1.2.1")
    }

    @Test func 미뤘다가_이어서_한_설치도_종료를_막은_뒤의_재시도까지_지킨다() {
        let controller = makeController(settle: 0)
        var quiet = true
        controller.quietProbe = { quiet }
        var resumes = 0
        controller.holdInstall(version: "1.2.1") {}
        controller.reevaluateQuietness() // 설치 시작
        quiet = false
        #expect(controller.shouldPostponeRelaunch { resumes += 1 }) // 넘기기 직전에 바빠져 미룸
        quiet = true
        controller.reevaluateQuietness() // 이어서 하기
        #expect(resumes == 1)
        controller.sparkleWillRelaunch() // 이제야 Sparkle 이 알린다 (한 번뿐)
        quiet = false
        #expect(controller.shouldCancelTermination(.fromAnotherProcess))

        quiet = true
        clock.advance(60)
        controller.reevaluateQuietness() // 재시도 — 물음도 알림도 다시 오지 않는다
        #expect(resumes == 2)
        quiet = false
        #expect(controller.shouldCancelTermination(.fromAnotherProcess))
    }

    @Test func 종료를_막은_뒤_사용자가_지금_설치를_누르면_막지_않는다() {
        let controller = makeController(settle: 0)
        var quiet = true
        controller.quietProbe = { quiet }
        var installs = 0
        controller.holdInstall(version: "1.2.1") { installs += 1 }
        controller.reevaluateQuietness()
        controller.sparkleWillRelaunch()
        quiet = false
        #expect(controller.shouldCancelTermination(.fromAnotherProcess))

        controller.installPendingUpdateNow()
        #expect(installs == 2)
        #expect(!controller.shouldCancelTermination(.fromAnotherProcess))
    }

    @Test func 새로_받은_업데이트는_Sparkle이_다시_알릴_때까지_종료를_막지_않는다() {
        // 새로 받으면 Sparkle 쪽 설치도 새것이라, 끄기 전에 다시 묻고 다시 알립니다.
        let controller = makeController(settle: 0)
        var quiet = true
        controller.quietProbe = { quiet }
        controller.holdInstall(version: "1.2.1") {}
        controller.reevaluateQuietness()
        controller.sparkleWillRelaunch()
        quiet = false
        #expect(controller.shouldCancelTermination(.fromAnotherProcess))

        quiet = true
        clock.advance(60)
        controller.holdInstall(version: "1.2.2") {}
        controller.reevaluateQuietness()
        #expect(controller.gate.isInstallingOnItsOwn)
        quiet = false
        #expect(!controller.shouldCancelTermination(.fromAnotherProcess))
        controller.sparkleWillRelaunch()
        #expect(controller.shouldCancelTermination(.fromAnotherProcess))
    }

    @Test func 앱_안에서_누른_종료와_로그아웃은_Sparkle이_끄는_중이어도_막지_않는다() {
        let controller = makeController(settle: 0)
        var quiet = true
        controller.quietProbe = { quiet }
        controller.holdInstall(version: "1.2.1") {}
        controller.reevaluateQuietness()
        controller.sparkleWillRelaunch()
        quiet = false
        #expect(!controller.shouldCancelTermination(.fromThisApp))
        #expect(!controller.shouldCancelTermination(.fromSystem))
        // 물어본 것만으로 상태가 바뀌지 않습니다: 뒤이어 온 Sparkle 의 종료는 막습니다.
        #expect(controller.shouldCancelTermination(.fromAnotherProcess))
    }

    @Test func Sparkle이_끈다고_알리기_전의_종료는_막지_않는다() {
        // 스스로 설치를 시작했더라도, Sparkle 이 끈다고 알리기 전에 온 종료는 사용자의 것입니다(팝오버의 "종료", 로그아웃).
        let controller = makeController(settle: 0)
        var quiet = true
        controller.quietProbe = { quiet }
        controller.holdInstall(version: "1.2.1") {}
        controller.reevaluateQuietness()
        #expect(controller.gate.isInstallingOnItsOwn)
        quiet = false
        #expect(!controller.shouldCancelTermination(.fromAnotherProcess))
    }

    @Test func Sparkle이_끈다고_알린_지_오래됐으면_막지_않는다() {
        let controller = makeController(settle: 0)
        var quiet = true
        controller.quietProbe = { quiet }
        controller.holdInstall(version: "1.2.1") {}
        controller.reevaluateQuietness()
        controller.sparkleWillRelaunch()
        clock.advance(UpdateController.relaunchGrace)
        quiet = false
        #expect(!controller.shouldCancelTermination(.fromAnotherProcess))
    }

    @Test func 조용한_채로_꺼지는_것은_막지_않는다() {
        let controller = makeController(settle: 0)
        controller.quietProbe = { true }
        controller.holdInstall(version: "1.2.1") {}
        controller.reevaluateQuietness()
        controller.sparkleWillRelaunch()
        #expect(!controller.shouldCancelTermination(.fromAnotherProcess))
    }

    @Test func 붙잡고만_있을_때_사용자가_끄는_것은_막지_않는다() {
        // 이때는 Sparkle 이 꺼지면서 설치합니다.
        let controller = makeController(settle: 60)
        controller.quietProbe = { false }
        controller.holdInstall(version: "1.2.1") {}
        #expect(!controller.shouldCancelTermination(.fromAnotherProcess))
    }

    @Test func 사용자가_지금_설치를_누르면_바빠도_설치하고_종료를_막지_않는다() {
        let controller = makeController(settle: 60)
        controller.quietProbe = { false }
        var installs = 0
        controller.holdInstall(version: "1.2.1") { installs += 1 }
        #expect(controller.canInstallPendingUpdate)
        controller.installPendingUpdateNow()
        #expect(installs == 1)
        controller.sparkleWillRelaunch()
        #expect(!controller.shouldCancelTermination(.fromAnotherProcess))
        #expect(!controller.canInstallPendingUpdate) // 진행 중에는 단추를 또 누를 수 없습니다
    }

    @Test func 자동_설치를_끄면_스스로_설치하지_않고_다시_켜면_이어서_한다() {
        // 꺼 놓았는데 조용해졌다고 스스로 다시 켜지면 안 됩니다. 붙잡은 것은 남겨 두어, 다시 켜거나 "지금 설치"를 누르면 됩니다.
        let controller = makeController(settle: 0)
        controller.quietProbe = { true }
        controller.automaticallyInstalls = true
        var installs = 0
        controller.holdInstall(version: "1.2.1") { installs += 1 }

        controller.automaticallyInstalls = false
        controller.reevaluateQuietness()
        #expect(installs == 0)
        #expect(controller.pendingVersion == "1.2.1")
        #expect(controller.canInstallPendingUpdate)

        controller.automaticallyInstalls = true
        controller.reevaluateQuietness()
        #expect(installs == 1)
    }

    @Test func 자동_설치가_꺼져_있어도_지금_설치는_된다() {
        let controller = makeController(settle: 0)
        controller.quietProbe = { true }
        controller.automaticallyInstalls = false
        var installs = 0
        controller.holdInstall(version: "1.2.1") { installs += 1 }
        controller.reevaluateQuietness()
        #expect(installs == 0)
        controller.installPendingUpdateNow()
        #expect(installs == 1)
    }

    @Test func 자동_설치가_꺼져_있어도_지금_설치가_먹지_않았으면_단추가_다시_살아난다() {
        // 설치를 시작했는데 앱이 꺼지지 않은 경우(설치 도우미 실패 등). 자동 설치가 꺼져 있어도 다시 재야 그것을 알아챕니다.
        let controller = makeController(settle: 60)
        controller.quietProbe = { false }
        controller.automaticallyInstalls = false
        controller.holdInstall(version: "1.2.1") {}
        #expect(!controller.needsQuietTimer) // 붙잡고만 있고 스스로 설치하지 않으면 잴 것이 없다
        controller.installPendingUpdateNow()
        #expect(controller.installInProgress)
        #expect(!controller.canInstallPendingUpdate)
        #expect(controller.needsQuietTimer)

        clock.advance(31)
        controller.reevaluateQuietness()
        #expect(!controller.installInProgress)
        #expect(controller.canInstallPendingUpdate)
        #expect(!controller.needsQuietTimer)
    }

    @Test func 스스로_설치할_것을_붙잡고_있는_동안에만_주기적으로_다시_잰다() {
        let controller = makeController(settle: 60)
        controller.quietProbe = { false }
        #expect(!controller.needsQuietTimer)
        controller.holdInstall(version: "1.2.1") {}
        #expect(controller.needsQuietTimer)
        controller.updateCycleDidFinish()
        #expect(!controller.needsQuietTimer)
    }

    @Test func Sparkle이_부르는_대리자_메서드가_모두_있다() {
        // Sparkle 은 이 메서드들이 있을 때만 부릅니다(선택 사항). 이름이 한 글자라도 어긋나면 조용히 불리지 않습니다.
        let controller = makeController()
        for name in [
            "updater:willInstallUpdateOnQuit:immediateInstallationBlock:",
            "updater:shouldPostponeRelaunchForUpdate:untilInvokingBlock:",
            "updaterWillRelaunchApplication:",
            "updater:didFinishUpdateCycleForUpdateCheck:error:",
            "updater:didAbortWithError:"
        ] {
            #expect(controller.responds(to: NSSelectorFromString(name)), "\(name)")
        }
    }

    @Test func Sparkle의_업데이트_주기가_끝나면_붙잡은_것을_치운다() {
        // 주기가 끝나면(설치 도우미와의 연결이 끊기는 등) 받아 둔 설치 동작은 더 쓸 수 없습니다.
        // 남겨 두면 설정 창에 눌러도 아무 일 없는 단추가 남고, "지금 확인"도 가려집니다.
        let controller = makeController(settle: 0)
        controller.quietProbe = { true }
        var installs = 0
        controller.holdInstall(version: "1.2.1") { installs += 1 }
        controller.updateCycleDidFinish()
        #expect(controller.pendingVersion == nil)
        #expect(!controller.gate.hasPendingInstall)
        controller.reevaluateQuietness()
        #expect(installs == 0)
    }
}

@MainActor
struct UpdateTerminationWiringTests {
    private let clock = UpdateTestClock()

    @Test func 앱_대리자는_업데이트가_막으라고_하면_종료를_취소한다() {
        // AppDelegate.applicationShouldTerminate 가 실제로 물어보는지 (이 연결이 빠지면 집중 도중에 다시 켜질 수 있습니다)
        let controller = UpdateController(
            configuration: UpdaterConfiguration(info: [:]),
            gate: UpdateInstallGate(settleTime: 0, installTimeout: 30, now: { [clock] in clock.time }),
            now: { [clock] in clock.time }
        )
        var quiet = true
        controller.quietProbe = { quiet }
        controller.holdInstall(version: "1.2.1") {}
        controller.reevaluateQuietness()
        controller.sparkleWillRelaunch()
        quiet = false

        let delegate = AppDelegate()
        delegate.updates = controller
        // 앱 안에서 부른 종료(팝오버의 "종료")는 이 상태에서도 막지 않습니다. 물어본 것만으로 상태가 바뀌지도 않습니다.
        delegate.terminationRequestProbe = { .fromThisApp }
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
        #expect(controller.gate.isInstallingOnItsOwn)
        // Sparkle 의 설치 도우미처럼 다른 프로세스가 끄는 종료는 막습니다.
        delegate.terminationRequestProbe = { .fromAnotherProcess }
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
        // 막을 일이 없으면 예전처럼 끝냅니다 (이 대리자에는 타이머가 없으므로 곧바로 종료).
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
    }
}
