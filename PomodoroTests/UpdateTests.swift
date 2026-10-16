// File: UpdateTests.swift
// Description: 자동 업데이트에서 Sparkle 바깥에 있는 우리 쪽 판단을 검사합니다.
// (받아 둔 업데이트를 스스로 설치하지 않고 누를 때만 설치하는지, 메뉴 막대에 무엇을 표시하는지, 이 빌드가 업데이트를 쓸 수 있는지)

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

/// "잠시 뒤에 할 일"을 모아 두었다가 테스트가 손으로 실행합니다 (앱은 그 시간만큼 기다린 뒤 실행합니다)
@MainActor
private final class ScheduledWork {
    private(set) var items: [(delay: TimeInterval, work: @MainActor () -> Void)] = []
    var delays: [TimeInterval] { items.map(\.delay) }
    func add(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) { items.append((delay, work)) }
    func runAll() {
        let pending = items
        items = []
        pending.forEach { $0.work() }
    }
}

@MainActor
struct HeldUpdateTests {
    private let clock = UpdateTestClock()

    private func makeHeld(timeout: TimeInterval = 30) -> HeldUpdate {
        HeldUpdate(installTimeout: timeout, now: { [clock] in clock.time })
    }

    @Test func 맡기는_것만으로는_설치하지_않는다() {
        let held = makeHeld()
        var installs = 0
        held.hold { installs += 1 }
        #expect(installs == 0)
        #expect(held.isHolding)
        #expect(!held.isInstalling)
    }

    @Test func 시간이_아무리_지나도_스스로_설치하지_않는다() {
        // 1.2.1 까지는 조용한 때가 1분 이어지면 스스로 설치했습니다. 이제는 누를 때만 설치합니다.
        let held = makeHeld()
        var installs = 0
        held.hold { installs += 1 }
        for _ in 0..<10 {
            clock.advance(3_600)
            #expect(installs == 0)
            #expect(!held.isInstalling)
        }
        #expect(held.isHolding)
    }

    @Test func 누르면_한_번_설치한다() {
        let held = makeHeld()
        var installs = 0
        held.hold { installs += 1 }
        #expect(held.installNow())
        #expect(installs == 1)
        #expect(held.isInstalling)
        // 설치 동작은 버리지 않습니다 — 먹지 않았을 때 다시 눌러야 합니다.
        #expect(held.isHolding)
    }

    @Test func 설치가_진행_중이면_또_눌러도_다시_실행하지_않는다() {
        let held = makeHeld()
        var installs = 0
        held.hold { installs += 1 }
        held.installNow()
        clock.advance(5)
        #expect(!held.installNow())
        #expect(installs == 1)
    }

    @Test func 설치_동작이_이쪽을_다시_불러도_두_번_설치하지_않는다() {
        // 설치 동작이 앱을 끝내는 길에 "업데이트"가 한 번 더 눌린 것처럼 불릴 수 있습니다.
        let held = makeHeld()
        var installs = 0
        held.hold { [held] in
            installs += 1
            held.installNow()
        }
        held.installNow()
        #expect(installs == 1)
    }

    @Test func 설치를_시작했는데_앱이_꺼지지_않으면_기다린_뒤에_다시_누를_수_있다() {
        let held = makeHeld(timeout: 30)
        var installs = 0
        held.hold { installs += 1 }
        held.installNow()
        clock.advance(29)
        #expect(held.isInstalling)
        #expect(!held.installNow())
        clock.advance(1)
        // 설치 도우미가 실패한 경우 등: 앱이 아직 살아 있으므로 다시 누를 수 있어야 합니다.
        #expect(!held.isInstalling)
        #expect(held.isHolding)
        #expect(held.installNow())
        #expect(installs == 2)
    }

    @Test func 맡긴_것이_없으면_눌러도_아무것도_하지_않는다() {
        let held = makeHeld()
        #expect(!held.installNow())
        #expect(!held.isHolding)
        #expect(!held.isInstalling)
    }

    @Test func 다시_맡기면_나중_것만_설치하고_설치하는_중도_처음으로_돌아간다() {
        let held = makeHeld()
        var first = 0
        var second = 0
        held.hold { first += 1 }
        held.installNow()
        #expect(held.isInstalling)
        held.hold { second += 1 }
        #expect(!held.isInstalling)
        #expect(held.installNow())
        #expect(first == 1)
        #expect(second == 1)
    }

    @Test func 버리면_눌러도_설치하지_않는다() {
        let held = makeHeld()
        var installs = 0
        held.hold { installs += 1 }
        held.discard()
        #expect(!held.isHolding)
        #expect(!held.installNow())
        #expect(installs == 0)
    }

    @Test func 설치하는_중에_버리면_설치하는_중도_끝난다() {
        let held = makeHeld()
        held.hold {}
        held.installNow()
        held.discard()
        #expect(!held.isInstalling)
    }
}

struct UpdateSettingsCaptionTests {
    @Test func 자동_확인이_꺼져_있으면_알려_준다고_하지_않는다() {
        let text = UpdateSettingsSection.caption(hasPending: false, automaticallyChecks: false, locale: Locale(identifier: "ko"))
        #expect(text.contains("자동 확인이 꺼져"))
        #expect(!text.contains("알립니다"))
    }

    @Test func 평소에는_받아_두고_표시한다고_적고_스스로_설치한다고_적지_않는다() {
        let text = UpdateSettingsSection.caption(hasPending: false, automaticallyChecks: true, locale: Locale(identifier: "ko"))
        #expect(text.contains("받아 두고") && text.contains("메뉴 막대 아이콘"))
        #expect(text.contains("누르면 설치"))
        #expect(!text.contains("스스로 설치") && !text.contains("1분쯤"))
    }

    @Test func 누르지_않아도_앱을_끄면_설치된다는_것을_받아_두기_전에도_적는다() {
        // 받아 둔 업데이트는 앱이 끝날 때 Sparkle 이 설치합니다. 점이 켜지기 전에 읽는 글에도 있어야 놀라지 않습니다.
        let text = UpdateSettingsSection.caption(hasPending: false, automaticallyChecks: true, locale: Locale(identifier: "ko"))
        #expect(text.contains("앱을 끄면 그때 설치"))
        // 자동 확인이 꺼져 있으면 받지도 않으므로 그 말이 없습니다.
        #expect(!UpdateSettingsSection.caption(hasPending: false, automaticallyChecks: false, locale: Locale(identifier: "ko")).contains("앱을 끄면"))
    }

    @Test func 받아_둔_것이_있으면_누르면_설치하고_끄면_그때_설치된다고_적는다() {
        for checks in [true, false] {
            let text = UpdateSettingsSection.caption(hasPending: true, automaticallyChecks: checks, locale: Locale(identifier: "ko"))
            #expect(text.contains("누르면 설치하고 다시 켭니다"))
            #expect(text.contains("앱을 끄면 그때 설치"))
            #expect(text.contains("새로 확인하지 않습니다"))
            #expect(!text.contains("스스로 설치") && !text.contains("1분쯤"))
        }
    }

    @Test func 설치를_시작했으면_그렇다고_적는다() {
        let text = UpdateSettingsSection.caption(hasPending: true, automaticallyChecks: true, installing: true, locale: Locale(identifier: "ko"))
        #expect(text.contains("설치를 시작했습니다"))
        #expect(!text.contains("누르면"))
    }
}

struct UpdateRowTests {
    @Test func 설치하는_중이면_단추의_글이_바뀐다() {
        #expect(UpdateRow.buttonTitle(installing: false, locale: Locale(identifier: "ko")) == "업데이트")
        #expect(UpdateRow.buttonTitle(installing: true, locale: Locale(identifier: "ko")) == "설치하는 중…")
    }

    @Test func 받아_둔_것은_누르면_앱이_다시_켜진다고_알려_준다() {
        #expect(UpdateRow.help(downloaded: true, locale: Locale(identifier: "ko")).contains("다시 켭니다"))
        #expect(UpdateRow.help(downloaded: false, locale: Locale(identifier: "ko")).contains("안내 창"))
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
    private let scheduled = ScheduledWork()

    private var usable: UpdaterConfiguration {
        UpdaterConfiguration(info: [
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": Data((0..<32).map { UInt8($0) }).base64EncodedString()
        ])
    }

    private func makeController(installsOnArrival: Bool = false) -> UpdateController {
        UpdateController(
            configuration: usable,
            held: HeldUpdate(installTimeout: 30, now: { [clock] in clock.time }),
            installsOnArrival: installsOnArrival,
            schedule: { [scheduled] delay, work in scheduled.add(delay, work) }
        )
    }

    // 켤지 말지: 셋 가운데 하나라도 걸리면 켜지 않습니다. 한 조건씩만 걸어 봅니다
    // (테스트는 개발 빌드로 돌기 때문에, 한꺼번에 보면 다른 조건이 가려 줍니다).
    @Test func 테스트_호스트에서는_업데이터를_켜지_않는다() {
        #expect(UpdateController.whyNotStarting(isRunningTests: true, isDebugBuild: false, configuration: usable, locale: Locale(identifier: "ko")) != nil)
    }

    @Test func 개발_빌드에서는_켜지_않는다() {
        // Xcode에서 실행한 개발 빌드가 릴리스를 받아 자기 자신을 바꾸면 안 됩니다.
        let reason = UpdateController.whyNotStarting(isRunningTests: false, isDebugBuild: true, configuration: usable, locale: Locale(identifier: "ko"))
        #expect(reason?.contains("개발 빌드") == true)
    }

    @Test func 쓸_수_없는_설정이면_켜지_않고_이유를_알려_준다() {
        let config = UpdaterConfiguration(info: [:])
        let reason = UpdateController.whyNotStarting(isRunningTests: false, isDebugBuild: false, configuration: config, locale: Locale(identifier: "ko"))
        #expect(reason != nil)
        #expect(reason == config.disabledReason)
    }

    @Test func 걸리는_것이_없으면_켠다() {
        #expect(UpdateController.whyNotStarting(isRunningTests: false, isDebugBuild: false, configuration: usable, locale: Locale(identifier: "ko")) == nil)
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

    @Test func 받아_둔_업데이트는_들고만_있고_스스로_설치하지_않는다() {
        let controller = makeController()
        var installs = 0

        controller.holdInstall(version: "1.2.2") { installs += 1 }
        #expect(installs == 0)
        #expect(controller.pendingVersion == "1.2.2")
        #expect(controller.indicatedVersion == "1.2.2")
        #expect(controller.canInstallPendingUpdate)
        #expect(!controller.installInProgress)
        // 나중에 스스로 하려고 걸어 둔 일이 없습니다. 시간이 지나도 그대로입니다.
        #expect(scheduled.items.isEmpty)
        clock.advance(86_400)
        scheduled.runAll()
        controller.refreshInstallState()
        #expect(installs == 0)
        #expect(controller.pendingVersion == "1.2.2")
    }

    @Test func 누르면_설치하고_설치하는_중으로_바뀐다() {
        let controller = makeController()
        var installs = 0
        controller.holdInstall(version: "1.2.2") { installs += 1 }

        controller.installPendingUpdateNow()
        #expect(installs == 1)
        #expect(controller.installInProgress)
        #expect(!controller.canInstallPendingUpdate)
        // 표시는 앱이 꺼질 때까지 남습니다.
        #expect(controller.indicatedVersion == "1.2.2")
        // 설치하는 동안 또 눌러도 다시 실행하지 않습니다.
        controller.installPendingUpdateNow()
        controller.performIndicatedUpdate()
        #expect(installs == 1)
    }

    @Test func 설치가_먹지_않으면_기다린_뒤에_단추가_다시_살아난다() {
        // 설치 도우미가 실패해 앱이 꺼지지 않은 경우. 단추가 "설치하는 중…"에 멈춰 있으면 다시 누를 길이 없습니다.
        let controller = makeController()
        var installs = 0
        controller.holdInstall(version: "1.2.2") { installs += 1 }
        controller.installPendingUpdateNow()
        // 기다리는 시간이 지난 뒤에 다시 보도록 걸어 둡니다.
        #expect(scheduled.delays == [31])

        clock.advance(31)
        scheduled.runAll()
        #expect(!controller.installInProgress)
        #expect(controller.canInstallPendingUpdate)
        controller.installPendingUpdateNow()
        #expect(installs == 2)
        #expect(controller.installInProgress)
    }

    @Test func 기다리는_시간이_지나기_전에는_단추가_살아나지_않는다() {
        let controller = makeController()
        controller.holdInstall(version: "1.2.2") {}
        controller.installPendingUpdateNow()
        clock.advance(10)
        controller.refreshInstallState()
        #expect(controller.installInProgress)
        #expect(!controller.canInstallPendingUpdate)
    }

    @Test func 팝오버의_업데이트는_받아_둔_것을_설치한다() {
        let controller = makeController()
        var installs = 0
        controller.holdInstall(version: "1.2.2") { installs += 1 }
        controller.performIndicatedUpdate()
        #expect(installs == 1)
        #expect(controller.installInProgress)
    }

    @Test func 표시할_것이_없으면_눌러도_아무_일도_없다() {
        let controller = makeController()
        #expect(controller.indicatedVersion == nil)
        controller.performIndicatedUpdate()
        controller.installPendingUpdateNow()
        #expect(!controller.installInProgress)
        #expect(scheduled.items.isEmpty)
    }

    @Test func 찾기만_한_새_버전도_표시하고_받아_둔_것이_있으면_그것이_먼저다() {
        // Sparkle 이 스스로 받을 수 없는 업데이트는 "찾기만 한 것"으로 옵니다. 그때도 점은 켭니다.
        let controller = makeController()
        controller.showAvailable(version: "2.0.0")
        #expect(controller.availableVersion == "2.0.0")
        #expect(controller.indicatedVersion == "2.0.0")
        #expect(!controller.canInstallPendingUpdate)

        var installs = 0
        controller.holdInstall(version: "1.2.2") { installs += 1 }
        #expect(controller.indicatedVersion == "1.2.2")
        controller.performIndicatedUpdate()
        #expect(installs == 1)

        controller.updateCycleDidFinish()
        #expect(controller.indicatedVersion == "2.0.0")
        controller.clearAvailable()
        #expect(controller.indicatedVersion == nil)
    }

    @Test func 찾기만_한_것을_눌러도_설치_동작은_실행하지_않는다() {
        // 이때는 Sparkle 의 안내 창을 엽니다(테스트 호스트에서는 업데이터가 꺼져 있어 아무 일도 없습니다).
        let controller = makeController()
        controller.showAvailable(version: "2.0.0")
        controller.performIndicatedUpdate()
        #expect(!controller.installInProgress)
        #expect(scheduled.items.isEmpty)
        #expect(controller.indicatedVersion == "2.0.0")
    }

    @Test func Sparkle의_업데이트_주기가_끝나면_받아_둔_것을_치운다() {
        // 주기가 끝나면(설치 도우미와의 연결이 끊기는 등) 받아 둔 설치 동작은 더 쓸 수 없습니다.
        // 남겨 두면 눌러도 아무 일 없는 단추와 꺼지지 않는 점이 남고, "지금 확인"도 가려집니다.
        let controller = makeController()
        var installs = 0
        controller.holdInstall(version: "1.2.2") { installs += 1 }
        controller.updateCycleDidFinish()
        #expect(controller.pendingVersion == nil)
        #expect(controller.indicatedVersion == nil)
        #expect(!controller.held.isHolding)
        controller.installPendingUpdateNow()
        controller.performIndicatedUpdate()
        #expect(installs == 0)
    }

    @Test func 설치하는_중에_주기가_끝나면_설치하는_중도_끝난다() {
        let controller = makeController()
        controller.holdInstall(version: "1.2.2") {}
        controller.installPendingUpdateNow()
        controller.updateCycleDidFinish()
        #expect(!controller.installInProgress)
        // 걸어 둔 "다시 보기"가 뒤늦게 돌아도 그대로입니다.
        clock.advance(31)
        scheduled.runAll()
        #expect(!controller.installInProgress)
        #expect(controller.pendingVersion == nil)
    }

    @Test func 새로_받으면_앞의_설치하는_중은_잊는다() {
        let controller = makeController()
        var first = 0
        var second = 0
        controller.holdInstall(version: "1.2.2") { first += 1 }
        controller.installPendingUpdateNow()
        controller.holdInstall(version: "1.2.3") { second += 1 }
        #expect(controller.pendingVersion == "1.2.3")
        #expect(!controller.installInProgress)
        #expect(controller.canInstallPendingUpdate)
        controller.installPendingUpdateNow()
        #expect(first == 1)
        #expect(second == 1)
    }

    @Test func 시험용_스위치가_켜져_있으면_받아_두자마자_단추와_같은_길로_설치한다() {
        let controller = makeController(installsOnArrival: true)
        var installs = 0
        controller.holdInstall(version: "0.9.2") { installs += 1 }
        #expect(installs == 1)
        #expect(controller.pendingVersion == "0.9.2")
        #expect(controller.installInProgress)
        // 단추를 눌렀을 때와 같이, 먹지 않았을 때를 위한 "다시 보기"도 걸립니다.
        #expect(scheduled.delays == [31])
    }

    @Test func 시험용_스위치는_실행_인자로만_켜진다() {
        let key = UpdateController.installOnArrivalArgument
        #expect(!UpdateController.installsOnArrival(arguments: [:]))
        #expect(UpdateController.installsOnArrival(arguments: [key: "YES"]))
        #expect(UpdateController.installsOnArrival(arguments: [key: "1"]))
        #expect(UpdateController.installsOnArrival(arguments: [key: true]))
        #expect(!UpdateController.installsOnArrival(arguments: [key: "NO"]))
        #expect(!UpdateController.installsOnArrival(arguments: [key: false]))
        #expect(!UpdateController.installsOnArrival(arguments: ["UpdateInstallSettleSeconds": "5"]))
        // 이 테스트 호스트는 그 인자 없이 켜졌습니다. (읽는 곳은 실행 인자뿐이라 저장된 설정에 같은 이름이 있어도 켜지지 않습니다.)
        #expect(!UpdateController.installsOnArrival())
    }

    @Test func Sparkle이_부르는_대리자_메서드가_모두_있다() {
        // Sparkle 은 이 메서드들이 있을 때만 부릅니다(선택 사항). 이름이 한 글자라도 어긋나면 조용히 불리지 않습니다.
        let controller = makeController()
        for name in [
            "updater:willInstallUpdateOnQuit:immediateInstallationBlock:",
            "updater:didFinishUpdateCycleForUpdateCheck:error:",
            "updater:didAbortWithError:",
            "supportsGentleScheduledUpdateReminders",
            "standardUserDriverShouldHandleShowingScheduledUpdate:andInImmediateFocus:",
            "standardUserDriverWillHandleShowingUpdate:forUpdate:state:",
            "standardUserDriverDidReceiveUserAttentionForUpdate:",
            "standardUserDriverWillFinishUpdateSession"
        ] {
            #expect(controller.responds(to: NSSelectorFromString(name)), "\(name)")
        }
    }

    @Test func 스스로_설치하던_때의_대리자_메서드는_없다() {
        // 설치를 미루거나 끄는 순간을 가로채던 것들. 남아 있으면 Sparkle 이 계속 부릅니다.
        let controller = makeController()
        for name in [
            "updater:shouldPostponeRelaunchForUpdate:untilInvokingBlock:",
            "updaterWillRelaunchApplication:"
        ] {
            #expect(!controller.responds(to: NSSelectorFromString(name)), "\(name)")
        }
    }

    @Test func 창을_스스로_띄우지_않는다() {
        // 스스로 받을 수 없는 업데이트를 찾았을 때: 앱을 방금 켠 때라도 안내 창 대신 표시로만 알립니다.
        let controller = makeController()
        #expect(controller.supportsGentleScheduledUpdateReminders)
    }
}

@MainActor
struct UpdateTerminationWiringTests {
    @Test func 앱_대리자는_업데이트를_받아_두고_있어도_종료를_막지_않는다() {
        // 1.2.1 까지는 스스로 시작한 설치가 집중을 끊지 않도록 종료를 취소하는 길이 있었습니다.
        // 이제 설치는 사용자가 누른 것뿐이라 종료를 막을 일이 없습니다. (이 대리자에는 타이머가 없으므로 곧바로 종료)
        let controller = UpdateController(
            configuration: UpdaterConfiguration(info: [:]),
            held: HeldUpdate(),
            installsOnArrival: false,
            schedule: { _, _ in }
        )
        let delegate = AppDelegate()
        delegate.updates = controller
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
        controller.holdInstall(version: "1.2.2") {}
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
        controller.installPendingUpdateNow()
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
    }
}
