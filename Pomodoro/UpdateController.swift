// File: UpdateController.swift
// Description: 자동 업데이트(Sparkle)를 켜고, 설정 창이 볼 상태를 내놓습니다.
// 받아 둔 업데이트는 타이머가 쉬고 있고 창이 없을 때 스스로 설치하고 다시 켭니다(UpdateInstallGate).

import AppKit
import Combine
import Sparkle
import UserNotifications

@MainActor
final class UpdateController: NSObject, ObservableObject {
    static let shared = UpdateController(configuration: UpdaterConfiguration(info: Bundle.main.infoDictionary ?? [:]))

    let configuration: UpdaterConfiguration
    let gate = UpdateInstallGate()
    /// 지금이 조용한 때인지(UpdateQuietness) 재는 것. AppDelegate가 넣어 줍니다.
    var quietProbe: @MainActor () -> Bool = { false }

    @Published private(set) var canCheckForUpdates = false
    /// 찾았지만 아직 설치하지 않은 새 버전 (창을 앞에 띄우지 않고 알릴 때만 값이 있음)
    @Published private(set) var availableVersion: String?
    @Published private(set) var lastCheckDate: Date?
    @Published var automaticallyChecks = false {
        didSet {
            guard let updater, updater.automaticallyChecksForUpdates != automaticallyChecks else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecks
        }
    }
    @Published var automaticallyInstalls = false {
        didSet {
            guard let updater, updater.automaticallyDownloadsUpdates != automaticallyInstalls else { return }
            updater.automaticallyDownloadsUpdates = automaticallyInstalls
        }
    }

    private let isRunningTests: Bool
    private let isDebugBuild: Bool
    private var controller: SPUStandardUpdaterController?
    private var canCheckObservation: AnyCancellable?
    private var quietTimer: Timer?
    private let reminderNotificationId = "pomodoro_update"

    private var updater: SPUUpdater? { controller?.updater }

    var isEnabled: Bool { controller != nil }

    /// 업데이트를 쓰지 않을 때 그 이유. 쓰고 있으면 nil.
    var statusText: String? {
        if isEnabled { return nil }
        if isRunningTests { return "테스트 중에는 업데이트를 확인하지 않습니다" }
        if isDebugBuild { return "개발 빌드는 업데이트를 확인하지 않습니다" }
        return configuration.disabledReason ?? "업데이트를 시작하지 않았습니다"
    }

    #if DEBUG
    static let builtForDebugging = true
    #else
    static let builtForDebugging = false
    #endif

    init(
        configuration: UpdaterConfiguration,
        isRunningTests: Bool = DataController.isRunningTests,
        isDebugBuild: Bool = UpdateController.builtForDebugging
    ) {
        self.configuration = configuration
        self.isRunningTests = isRunningTests
        self.isDebugBuild = isDebugBuild
        super.init()
    }

    /// 업데이터를 켭니다. 아래에서는 아무것도 하지 않습니다:
    /// 단위 테스트의 호스트, Xcode에서 실행한 개발 빌드(릴리스로 자기 자신을 바꾸면 안 됩니다), 주소·서명 키가 없는 빌드.
    func start() {
        guard controller == nil, !isRunningTests, !isDebugBuild, configuration.isUsable else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        let updater = controller.updater
        automaticallyChecks = updater.automaticallyChecksForUpdates
        automaticallyInstalls = updater.automaticallyDownloadsUpdates
        lastCheckDate = updater.lastUpdateCheckDate
        canCheckObservation = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
    }

    /// 사용자가 "지금 확인"을 눌렀을 때. 메뉴 바 앱이라 창이 앞에 오도록 앱을 먼저 활성화합니다.
    func checkForUpdates() {
        guard let controller else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    /// 타이머 상태나 창이 바뀌었을 때 불러, 붙잡아 둔 설치를 할 수 있는지 다시 봅니다.
    func reevaluateQuietness() {
        guard gate.hasPendingInstall else { return }
        gate.update(quiet: quietProbe())
        refreshQuietTimer()
    }

    // 창이 닫히는 것처럼 알림이 오지 않는 변화도 놓치지 않도록, 설치를 붙잡고 있는 동안에만 30초마다 다시 잽니다.
    private func refreshQuietTimer() {
        if gate.hasPendingInstall {
            guard quietTimer == nil else { return }
            quietTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.reevaluateQuietness() }
            }
        } else {
            quietTimer?.invalidate()
            quietTimer = nil
        }
    }

    private func showReminder(version: String) {
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
    // 자동으로 받아 둔 업데이트는 원래 앱을 끌 때 설치됩니다. 메뉴 바 앱은 몇 주씩 켜 두므로
    // 설치 동작을 받아 두었다가, 조용할 때 스스로 설치하고 다시 켭니다. (그 전에 앱을 끄면 Sparkle이 그때 설치합니다.)
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        gate.update(quiet: quietProbe())
        gate.hold(immediateInstallHandler)
        refreshQuietTimer()
        return true
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        lastCheckDate = updater.lastUpdateCheckDate
    }
}

// MARK: - 알리는 방식 (메뉴 바 앱이라 창을 갑자기 띄우지 않습니다)

extension UpdateController: SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    // 앱을 방금 켰을 때처럼 창이 앞에 뜰 수 있으면 Sparkle이 그대로 보여 주고,
    // 아니면 알림과 설정 창의 한 줄로만 알립니다.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        availableVersion = update.displayVersionString
        showReminder(version: update.displayVersionString)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        clearReminder()
    }

    func standardUserDriverWillFinishUpdateSession() {
        clearReminder()
    }
}
