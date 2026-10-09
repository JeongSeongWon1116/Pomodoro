// File: UpdateTests.swift
// Description: 자동 업데이트에서 Sparkle 바깥에 있는 우리 쪽 판단을 검사합니다.
// (받아 둔 업데이트를 언제 설치할지, 지금이 조용한 때인지, 이 빌드가 업데이트를 쓸 수 있는지)

import Testing
import Foundation
@testable import Pomodoro

@MainActor
struct UpdateInstallGateTests {

    @Test func 조용할_때_맡기면_곧바로_한_번_설치한다() {
        let gate = UpdateInstallGate(quiet: true)
        var installs = 0
        gate.hold { installs += 1 }
        #expect(installs == 1)
        #expect(!gate.hasPendingInstall)
    }

    @Test func 조용하지_않을_때_맡기면_기다렸다가_조용해지면_한_번_설치한다() {
        let gate = UpdateInstallGate(quiet: false)
        var installs = 0
        gate.hold { installs += 1 }
        #expect(installs == 0)
        #expect(gate.hasPendingInstall)

        gate.update(quiet: false)
        #expect(installs == 0)

        gate.update(quiet: true)
        #expect(installs == 1)
        #expect(!gate.hasPendingInstall)
    }

    @Test func 조용해졌다는_알림이_여러_번_와도_한_번만_설치한다() {
        let gate = UpdateInstallGate(quiet: false)
        var installs = 0
        gate.hold { installs += 1 }
        gate.update(quiet: true)
        gate.update(quiet: false)
        gate.update(quiet: true)
        gate.update(quiet: true)
        #expect(installs == 1)
    }

    @Test func 다시_맡기면_나중_것만_설치한다() {
        let gate = UpdateInstallGate(quiet: false)
        var installed: [String] = []
        gate.hold { installed.append("처음") }
        gate.hold { installed.append("나중") }
        gate.update(quiet: true)
        #expect(installed == ["나중"])
    }

    @Test func 버리면_조용해져도_설치하지_않는다() {
        let gate = UpdateInstallGate(quiet: false)
        var installs = 0
        gate.hold { installs += 1 }
        gate.discard()
        #expect(!gate.hasPendingInstall)
        gate.update(quiet: true)
        #expect(installs == 0)
    }

    @Test func 조용했다가_바빠진_뒤에_맡기면_기다린다() {
        let gate = UpdateInstallGate(quiet: true)
        gate.update(quiet: false)
        var installs = 0
        gate.hold { installs += 1 }
        #expect(installs == 0)
        #expect(gate.hasPendingInstall)
    }

    @Test func 설치하는_도중에_다시_불려도_두_번_설치하지_않는다() {
        // 설치 블록은 앱을 끝내면서 상태 변화를 일으킬 수 있습니다. 그 안에서 다시 알림이 와도 한 번만 실행합니다.
        let gate = UpdateInstallGate(quiet: false)
        var installs = 0
        gate.hold {
            installs += 1
            gate.update(quiet: true)
        }
        gate.update(quiet: true)
        #expect(installs == 1)
    }
}

struct UpdateQuietnessTests {

    @Test func 타이머가_완전히_대기이고_열린_창이_없을_때만_조용하다() {
        #expect(UpdateQuietness.isQuiet(currentState: .idle, timerState: .idle, popoverShown: false, visibleWindows: 0))
    }

    @Test func 세션이_돌거나_멈춰_있거나_선택을_기다리면_조용하지_않다() {
        for timer in [TimerState.running, .paused, .awaitingChoice] {
            #expect(!UpdateQuietness.isQuiet(currentState: .focus, timerState: timer, popoverShown: false, visibleWindows: 0))
        }
        #expect(!UpdateQuietness.isQuiet(currentState: .shortBreak, timerState: .running, popoverShown: false, visibleWindows: 0))
        #expect(!UpdateQuietness.isQuiet(currentState: .longBreak, timerState: .paused, popoverShown: false, visibleWindows: 0))
    }

    @Test func 다음_세션을_준비만_해_둔_대기는_조용하지_않다() {
        // 자동 시작이 꺼져 있으면 타이머는 멈춰 있어도 다음 세션과 사이클 횟수를 들고 있습니다.
        // 이때 다시 켜면 긴 휴식까지의 횟수를 잃습니다.
        for state in [PomodoroState.focus, .shortBreak, .longBreak] {
            #expect(!UpdateQuietness.isQuiet(currentState: state, timerState: .idle, popoverShown: false, visibleWindows: 0))
        }
    }

    @Test func 팝오버나_창이_열려_있으면_조용하지_않다() {
        #expect(!UpdateQuietness.isQuiet(currentState: .idle, timerState: .idle, popoverShown: true, visibleWindows: 0))
        #expect(!UpdateQuietness.isQuiet(currentState: .idle, timerState: .idle, popoverShown: false, visibleWindows: 1))
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

    @Test func 테스트_호스트에서는_업데이터를_켜지_않는다() {
        // 단위 테스트가 네트워크로 업데이트를 찾거나 설치 창을 띄우면 안 됩니다.
        let controller = UpdateController(configuration: UpdaterConfiguration(info: [
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": Data((0..<32).map { UInt8($0) }).base64EncodedString()
        ]))
        controller.start()
        #expect(!controller.isEnabled)
        #expect(!controller.canCheckForUpdates)
    }

    private var usable: UpdaterConfiguration {
        UpdaterConfiguration(info: [
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": Data((0..<32).map { UInt8($0) }).base64EncodedString()
        ])
    }

    @Test func 쓸_수_없는_설정이면_켜지_않고_이유를_알려_준다() {
        let config = UpdaterConfiguration(info: [:])
        let controller = UpdateController(configuration: config, isRunningTests: false, isDebugBuild: false)
        controller.start()
        #expect(!controller.isEnabled)
        #expect(controller.statusText == config.disabledReason)
        #expect(controller.statusText != nil)
    }

    @Test func 개발_빌드에서는_켜지_않는다() {
        // Xcode에서 실행한 개발 빌드가 릴리스를 받아 자기 자신을 바꾸면 안 됩니다.
        let controller = UpdateController(configuration: usable, isRunningTests: false, isDebugBuild: true)
        controller.start()
        #expect(!controller.isEnabled)
        #expect(controller.statusText?.contains("개발 빌드") == true)
    }
}
