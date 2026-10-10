// File: UpdateController.swift
// Description: 자동 업데이트(Sparkle)를 켜고, 설정 창이 볼 상태를 내놓습니다.
// 받아 둔 업데이트는 타이머가 쉬고 있고 창이 없는 상태가 한동안 이어졌을 때 스스로 설치하고 다시 켭니다(UpdateInstallGate).

import AppKit
import Combine
import os
import Sparkle
import UserNotifications

@MainActor
final class UpdateController: NSObject, ObservableObject {
    static let shared = UpdateController(configuration: UpdaterConfiguration(info: Bundle.main.infoDictionary ?? [:]))

    #if DEBUG
    nonisolated static let builtForDebugging = true
    #else
    nonisolated static let builtForDebugging = false
    #endif

    /// 조용함이 이만큼(초) 이어져야 받아 둔 업데이트를 스스로 설치합니다.
    /// 사용자 기본값 `UpdateInstallSettleSeconds`로 바꿀 수 있습니다(scripts/update-e2e.sh 가 시험을 빨리 돌리려고 씁니다).
    nonisolated static let settleTimeKey = "UpdateInstallSettleSeconds"
    nonisolated static let defaultSettleTime: TimeInterval = 60
    /// Sparkle이 "이제 끄고 다시 켠다"고 알린 뒤(재시도에서는 설치 동작을 다시 실행한 뒤) 이만큼(초) 안에,
    /// 다른 프로세스가 보낸 종료만 Sparkle의 종료로 봅니다.
    nonisolated static let relaunchGrace: TimeInterval = 10

    let configuration: UpdaterConfiguration
    let gate: UpdateInstallGate
    /// 지금이 조용한 때인지(UpdateQuietness) 재는 것. AppDelegate가 넣어 줍니다.
    var quietProbe: @MainActor () -> Bool = { false }

    @Published private(set) var canCheckForUpdates = false
    /// 찾았지만 받지 않은 새 버전 (자동 설치를 껐을 때, 창을 앞에 띄우지 않고 알릴 때만 값이 있음)
    @Published private(set) var availableVersion: String?
    /// 받아 두고 설치를 기다리는 버전
    @Published private(set) var pendingVersion: String?
    /// 받아 둔 업데이트의 설치를 시작해 앱이 꺼지기를 기다리는 중인지
    @Published private(set) var installInProgress = false
    @Published private(set) var lastCheckDate: Date?
    @Published var automaticallyChecks = false {
        didSet {
            guard !syncingFromUpdater, let updater, updater.automaticallyChecksForUpdates != automaticallyChecks else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecks
        }
    }
    @Published var automaticallyInstalls = true {
        didSet {
            // 끄면 붙잡아 둔 것을 스스로 설치하지 않습니다. 버리지는 않습니다 — 다시 켜면 이어서 하고, "지금 설치"도 됩니다.
            gate.allowsAutomaticInstall = automaticallyInstalls
            refreshQuietTimer()
            guard !syncingFromUpdater, let updater, updater.automaticallyDownloadsUpdates != automaticallyInstalls else { return }
            updater.automaticallyDownloadsUpdates = automaticallyInstalls
        }
    }

    private let isRunningTests: Bool
    private let isDebugBuild: Bool
    // 깨어 있는 동안만 가는 시계(초)
    private let now: () -> TimeInterval
    private var controller: SPUStandardUpdaterController?
    private var startError: String?
    private var observations = Set<AnyCancellable>()
    // Sparkle 쪽에서 바뀐 값을 받아 적는 중인지 (받은 값을 Sparkle에 되쓰지 않기 위함)
    private var syncingFromUpdater = false
    private var quietTimer: Timer?
    // Sparkle의 종료 요청이 곧 올 것으로 보는 때: Sparkle이 "이제 끄고 다시 켠다"고 알린 때, 또는 그 뒤의 재시도를 실행한 때
    private var relaunchAnnouncedAt: TimeInterval?
    // Sparkle이 지금 붙잡고 있는 설치에 대해 이미 알렸는지. Sparkle은 설치 하나에 한 번만 알리고 미룰지도 한 번만 묻습니다.
    private var relaunchWasAnnounced = false
    private let reminderNotificationId = "pomodoro_update"
    // 업데이트가 왜 설치됐는지(또는 안 됐는지)를 나중에 볼 수 있게 남깁니다 (콘솔 앱에서 category "update").
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pomodoro", category: "update")
    private var lastLoggedQuiet: Bool?

    private var updater: SPUUpdater? { controller?.updater }

    var isEnabled: Bool { controller != nil }

    /// 받아 둔 업데이트를 사용자가 "지금 설치"할 수 있는지
    var canInstallPendingUpdate: Bool { pendingVersion != nil && gate.hasPendingInstall && !installInProgress }

    /// 업데이트를 쓰지 않을 때 그 이유. 쓰고 있으면 nil.
    var statusText: String? {
        if isEnabled { return nil }
        return Self.whyNotStarting(isRunningTests: isRunningTests, isDebugBuild: isDebugBuild, configuration: configuration)
            ?? startError
            ?? "업데이트를 시작하지 않았습니다"
    }

    /// 업데이터를 켜지 않는 이유. 켜도 되면 nil.
    /// 단위 테스트의 호스트(네트워크에 나가거나 창을 띄우면 안 됨), Xcode에서 실행한 개발 빌드(릴리스로 자기 자신을
    /// 바꾸면 안 됨), 주소·서명 키가 없는 빌드에서는 켜지 않습니다.
    nonisolated static func whyNotStarting(isRunningTests: Bool, isDebugBuild: Bool, configuration: UpdaterConfiguration) -> String? {
        if isRunningTests { return "테스트 중에는 업데이트를 확인하지 않습니다" }
        if isDebugBuild { return "개발 빌드는 업데이트를 확인하지 않습니다" }
        return configuration.disabledReason
    }

    init(
        configuration: UpdaterConfiguration,
        isRunningTests: Bool = DataController.isRunningTests,
        isDebugBuild: Bool = UpdateController.builtForDebugging,
        gate: UpdateInstallGate? = nil,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.configuration = configuration
        self.isRunningTests = isRunningTests
        self.isDebugBuild = isDebugBuild
        self.now = now
        let configured = UserDefaults.standard.double(forKey: Self.settleTimeKey)
        self.gate = gate ?? UpdateInstallGate(settleTime: configured >= 1 ? configured : Self.defaultSettleTime, now: now)
        super.init()
    }

    /// 업데이터를 켭니다(`whyNotStarting`이 이유를 대면 아무것도 하지 않습니다).
    func start() {
        guard controller == nil,
              Self.whyNotStarting(isRunningTests: isRunningTests, isDebugBuild: isDebugBuild, configuration: configuration) == nil
        else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        let updater = controller.updater
        do {
            // 설정이 잘못되면(주소, 키, 설치 도우미) Sparkle이 시작을 거부합니다. 경고 창 대신 설정 창에 이유를 보여 줍니다.
            try updater.start()
        } catch {
            startError = "업데이트를 시작하지 못했습니다: \(error.localizedDescription)"
            return
        }
        self.controller = controller
        // Sparkle 쪽에서 바뀌는 값(업데이트 안내 창의 "앞으로 자동으로 설치" 등)도 따라가도록 구독합니다.
        // 알림이 늦게 도착할 수 있으므로, 받은 값이 아니라 그때의 Sparkle 값을 읽어 맞춥니다.
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncFromUpdater() }
            .store(in: &observations)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncFromUpdater() }
            .store(in: &observations)
        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncFromUpdater() }
            .store(in: &observations)
        updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncFromUpdater() }
            .store(in: &observations)
        syncFromUpdater()
    }

    private func syncFromUpdater() {
        guard let updater else { return }
        syncingFromUpdater = true
        defer { syncingFromUpdater = false }
        if canCheckForUpdates != updater.canCheckForUpdates { canCheckForUpdates = updater.canCheckForUpdates }
        if automaticallyChecks != updater.automaticallyChecksForUpdates { automaticallyChecks = updater.automaticallyChecksForUpdates }
        if automaticallyInstalls != updater.automaticallyDownloadsUpdates { automaticallyInstalls = updater.automaticallyDownloadsUpdates }
        if lastCheckDate != updater.lastUpdateCheckDate { lastCheckDate = updater.lastUpdateCheckDate }
    }

    /// 사용자가 "지금 확인"을 눌렀을 때. 메뉴 바 앱이라 창이 앞에 오도록 앱을 먼저 활성화합니다.
    func checkForUpdates() {
        guard let controller else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    /// 받아 둔 업데이트의 설치 동작을 붙잡아 둡니다. 여기서는 실행하지 않습니다 —
    /// Sparkle은 대리자가 "내가 설치하겠다"고 답한 뒤에만 설치 동작을 쓰게 합니다.
    func holdInstall(version: String, _ install: @escaping () -> Void) {
        log.notice("holding update \(version, privacy: .public) until quiet for \(self.gate.settleTime, privacy: .public) s")
        pendingVersion = version
        lastLoggedQuiet = nil
        relaunchAnnouncedAt = nil
        relaunchWasAnnounced = false
        gate.hold { [weak self] in
            self?.log.notice("installing held update \(version, privacy: .public) now")
            self?.heldInstallWillRun()
            install()
        }
        gateDidChange()
    }

    // 문지기가 설치 동작을 실행하기 직전에. 종료를 한 번 막은 뒤의 재시도에는 Sparkle의 알림이 다시 오지 않으므로
    // (설치 도우미에게 종료 요청만 다시 보내게 합니다), 스스로 다시 실행하는 지금을 알린 때로 삼습니다.
    private func heldInstallWillRun() {
        if relaunchWasAnnounced { relaunchAnnouncedAt = now() }
    }

    /// 타이머 상태나 창이 바뀌었을 때, 그리고 붙잡고 있는 동안 주기적으로 불러 지금 조용한지를 다시 잽니다.
    func reevaluateQuietness() {
        if gate.hasPendingInstall {
            let quiet = quietProbe()
            if quiet != lastLoggedQuiet {
                log.notice("quiet for update: \(quiet, privacy: .public)")
                lastLoggedQuiet = quiet
            }
            gate.update(quiet: quiet)
        }
        gateDidChange()
    }

    /// 사용자가 설정에서 "지금 설치하고 다시 켜기"를 눌렀을 때.
    func installPendingUpdateNow() {
        log.notice("user asked to install the held update now")
        gate.installNow()
        gateDidChange()
    }

    /// Sparkle이 설치를 넘기기 직전에 "미룰까"를 물을 때(한 번만 묻습니다). 스스로 시작한 설치인데 그 사이 조용하지 않게
    /// 됐으면 참을 돌려주고, Sparkle이 준 "이어서 하기"를 대신 붙잡아 둡니다.
    func shouldPostponeRelaunch(resume: @escaping () -> Void) -> Bool {
        guard gate.isInstallingOnItsOwn, !quietProbe() else { return false }
        log.notice("postponed install: no longer quiet")
        lastLoggedQuiet = nil
        let version = pendingVersion ?? "?"
        gate.hold { [weak self] in
            self?.log.notice("resuming postponed install of \(version, privacy: .public)")
            self?.heldInstallWillRun()
            resume()
        }
        gateDidChange()
        return true
    }

    /// Sparkle이 "이제 앱을 끄고 다시 켠다"고 알렸을 때.
    func sparkleWillRelaunch() {
        relaunchWasAnnounced = true
        relaunchAnnouncedAt = now()
    }

    /// 앱이 꺼지려 할 때 AppDelegate가 묻습니다. 문지기가 스스로 시작한 설치로 Sparkle이 방금 끄는 중인데 그 사이
    /// 조용하지 않게 됐으면(집중 시작, 창 열림) 참을 돌려주고 설치를 다시 붙잡습니다.
    /// Sparkle의 설치 도우미는 다른 프로세스에서 종료를 요청하므로 그런 요청만, 그것도 Sparkle이 끈다고 알린 직후에만 봅니다 —
    /// 앱 안에서 누른 "종료", 로그아웃·시스템 종료, "지금 설치"는 막지 않습니다.
    func shouldCancelTermination(_ request: TerminationRequest) -> Bool {
        guard request == .fromAnotherProcess,
              let announcedAt = relaunchAnnouncedAt, now() - announcedAt < Self.relaunchGrace,
              gate.isInstallingOnItsOwn, !quietProbe()
        else { return false }
        log.notice("cancelled termination for update: no longer quiet")
        lastLoggedQuiet = nil
        gate.installWasInterrupted()
        gateDidChange()
        return true
    }

    /// Sparkle의 업데이트 주기가 끝났거나 오류로 중단됐을 때. 받아 둔 설치 동작은 그 주기의 것이라 더 쓸 수 없으므로 치웁니다.
    /// 주기는 설치 도우미의 오류나 연결 끊김으로 끝나고 그때 도우미도 스스로 끝나므로, 그 업데이트는 대개 다음 확인 때 다시 받습니다.
    func updateCycleDidFinish() {
        if gate.hasPendingInstall { log.notice("update cycle finished: dropping the held install") }
        gate.discard()
        pendingVersion = nil
        gateDidChange()
    }

    // 문지기를 건드린 뒤에: 설정 창이 볼 값을 맞추고, 다시 재는 타이머를 켜거나 끕니다.
    private func gateDidChange() {
        if installInProgress != gate.isInstalling { installInProgress = gate.isInstalling }
        refreshQuietTimer()
    }

    /// 10초마다 다시 재야 하는지. 창이 열리고 닫히는 것처럼 알림이 오지 않는 변화를 놓치지 않도록 스스로 설치할 것을
    /// 붙잡고 있는 동안에, 그리고 시작한 설치가 먹지 않았을 때 그것을 알아채도록 설치 중인 동안에 잽니다.
    var needsQuietTimer: Bool {
        gate.hasPendingInstall && (gate.allowsAutomaticInstall || gate.isInstalling)
    }

    private func refreshQuietTimer() {
        if needsQuietTimer {
            guard quietTimer == nil else { return }
            let timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.reevaluateQuietness() }
            }
            // 붙잡은 채로 며칠씩 갈 수 있으므로(선택을 기다리는 화면도 조용한 때가 아닙니다), 깨어나는 때를 느슨하게 둡니다.
            timer.tolerance = 3
            quietTimer = timer
        } else {
            quietTimer?.invalidate()
            quietTimer = nil
        }
    }

    private func showReminder(version: String) {
        availableVersion = version
        let content = UNMutableNotificationContent()
        content.title = "Pomodoro \(version) 업데이트가 있습니다"
        content.body = "설정 > 일반 > 지금 확인에서 설치할 수 있습니다."
        let request = UNNotificationRequest(identifier: reminderNotificationId, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func clearReminder() {
        availableVersion = nil
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [reminderNotificationId])
    }
}

// MARK: - 업데이트의 진행

extension UpdateController: SPUUpdaterDelegate {
    // 자동으로 받아 둔 업데이트는 원래 앱을 끌 때 설치됩니다. 메뉴 바 앱은 몇 주씩 켜 두므로 설치 동작을 받아 두었다가,
    // 조용함이 이어지면 스스로 설치하고 다시 켭니다. 그 전에 앱을 끄면 Sparkle이 그때 설치합니다.
    // (참을 돌려주면 설치할 때까지 Sparkle의 업데이트 확인이 멈춥니다 — 그동안 "지금 확인"은 쓸 수 없고 더 새 버전도 찾지 않습니다.)
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        holdInstall(version: item.displayVersionString, immediateInstallHandler)
        // 이 호출이 끝난 뒤에 조용함을 세기 시작합니다.
        Task { @MainActor [weak self] in self?.reevaluateQuietness() }
        return true
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        shouldPostponeRelaunch(resume: installHandler)
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        sparkleWillRelaunch()
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        updateCycleDidFinish()
    }

    // 오류로 중단될 때도 치웁니다. (자동으로 받는 경로에서는 오류가 있는 중단 뒤에 주기 끝 알림도 오므로 대개 겹칩니다.
    // 붙잡고 있는 동안에는 다른 확인이 끼어들지 못해, 멀쩡히 붙잡은 것을 여기서 치우는 일은 없습니다.)
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        updateCycleDidFinish()
    }
}

extension TerminationRequest {
    /// 'why?' = kAEQuitReason: 로그아웃·재시동·시스템 종료가 종료 이벤트에 붙이는 이유. Swift 에 이름이 나와 있지 않아 값으로 씁니다.
    static let quitReasonKeyword = AEKeyword(0x7768_793F)

    /// 종료를 처리하는 순간의 Apple 이벤트로 가립니다. 이벤트가 없으면 앱 안에서 부른 종료입니다.
    static func classify(event: NSAppleEventDescriptor?) -> TerminationRequest {
        guard let event else { return .fromThisApp }
        let isQuit = event.eventClass == AEEventClass(kCoreEventClass) && event.eventID == AEEventID(kAEQuitApplication)
        // 이유는 이벤트의 속성으로 옵니다. 매개변수로 붙여 보내는 곳이 있어도 시스템의 종료로 봅니다.
        let hasReason = event.attributeDescriptor(forKeyword: quitReasonKeyword) != nil
            || event.paramDescriptor(forKeyword: quitReasonKeyword) != nil
        return classify(isQuitEvent: isQuit, hasQuitReason: hasReason)
    }

    /// 지금 처리 중인 종료 요청 (applicationShouldTerminate 안에서 읽습니다).
    @MainActor static var current: TerminationRequest {
        classify(event: NSAppleEventManager.shared().currentAppleEvent)
    }
}

// MARK: - 알리는 방식 (메뉴 바 앱이라 창을 갑자기 띄우지 않습니다)

// 이 대리자는 Sparkle이 메인 스레드에서 부르지만 헤더에 그렇게 표시돼 있지 않아, 메서드를 nonisolated 로 두고 안에서 넘어옵니다.
extension UpdateController: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    // 자동 설치를 꺼 둔 경우의 알림입니다. 앱을 방금 켰을 때처럼 창이 앞에 뜰 수 있으면 Sparkle이 안내 창을 그대로 보여 주고,
    // 아니면 알림과 설정 창의 한 줄로만 알립니다.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        let version = update.displayVersionString
        MainActor.assumeIsolated { showReminder(version: version) }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { clearReminder() }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { clearReminder() }
    }
}
