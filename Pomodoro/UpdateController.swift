// File: UpdateController.swift
// Description: 자동 업데이트(Sparkle)를 켜고, 메뉴 막대 아이콘과 설정 창이 볼 상태를 내놓습니다.
// 새 버전은 미리 받아 두고 메뉴 막대 아이콘에 표시만 합니다. 앱이 켜져 있는 동안 스스로 설치하지 않습니다 — 사용자가
// "업데이트"를 누르면 그때 설치하고 다시 켭니다(HeldUpdate). 누르지 않은 채 앱을 끄면 Sparkle 이 그때 설치합니다.

import AppKit
import Combine
import os
import Sparkle

@MainActor
final class UpdateController: NSObject, ObservableObject {
    static let shared = UpdateController(configuration: UpdaterConfiguration(info: Bundle.main.infoDictionary ?? [:]))

    #if DEBUG
    nonisolated static let builtForDebugging = true
    #else
    nonisolated static let builtForDebugging = false
    #endif

    /// 시험용 실행 인자. `-UpdateInstallHeldOnArrival YES`로 켜면 업데이트를 받아 두자마자 "업데이트"를 누른 것처럼 설치합니다.
    /// scripts/update-e2e.sh 가 단추를 누르는 대신 씁니다. 실행 인자로만 읽고 저장된 설정은 보지 않으므로,
    /// 설치 뒤에 다시 켜진 앱이나 평소에 켠 앱에서는 꺼져 있습니다.
    nonisolated static let installOnArrivalArgument = "UpdateInstallHeldOnArrival"

    let configuration: UpdaterConfiguration
    let held: HeldUpdate

    @Published private(set) var canCheckForUpdates = false
    /// 찾았지만 곧바로 설치할 수 없는 새 버전. 누르면 Sparkle 의 안내 창이 떠서 거기서 이어 갑니다.
    /// (스스로 받을 수 없는 업데이트, 설치 도우미가 이미 떠 있어 이어 가는 경우, 관리자 암호가 필요해 미뤄진 경우)
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
            preferDownloadingUpdates()
        }
    }

    private let isRunningTests: Bool
    private let isDebugBuild: Bool
    private let installsOnArrival: Bool
    // 잠시 뒤에 할 일을 맡기는 것 (테스트에서는 기다리지 않고 손으로 실행합니다)
    private let schedule: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void
    private var controller: SPUStandardUpdaterController?
    private var startError: String?
    private var observations = Set<AnyCancellable>()
    // Sparkle 쪽에서 바뀐 값을 받아 적는 중인지 (받은 값을 Sparkle에 되쓰지 않기 위함)
    private var syncingFromUpdater = false
    // 업데이트를 언제 받아 두었고 언제 설치했는지를 나중에 볼 수 있게 남깁니다 (콘솔 앱에서 category "update").
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pomodoro", category: "update")

    private var updater: SPUUpdater? { controller?.updater }

    var isEnabled: Bool { controller != nil }

    /// 메뉴 막대 아이콘에 표시할 새 버전. 받아 둔 것이 먼저이고, 없으면 찾기만 한 것. 둘 다 없으면 nil(표시하지 않음).
    var indicatedVersion: String? { pendingVersion ?? availableVersion }

    /// 받아 둔 업데이트를 사용자가 지금 설치할 수 있는지
    var canInstallPendingUpdate: Bool { pendingVersion != nil && held.isHolding && !installInProgress }

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

    /// 실행 인자에 시험용 스위치(`installOnArrivalArgument`)가 켜져 있는지.
    nonisolated static func installsOnArrival(
        arguments: [String: Any] = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
    ) -> Bool {
        switch arguments[installOnArrivalArgument] {
        case let flag as Bool: return flag
        case let text as String: return (text as NSString).boolValue
        default: return false
        }
    }

    init(
        configuration: UpdaterConfiguration,
        isRunningTests: Bool = DataController.isRunningTests,
        isDebugBuild: Bool = UpdateController.builtForDebugging,
        held: HeldUpdate? = nil,
        installsOnArrival: Bool = UpdateController.installsOnArrival(),
        schedule: @escaping @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { work() } }
        }
    ) {
        self.configuration = configuration
        self.isRunningTests = isRunningTests
        self.isDebugBuild = isDebugBuild
        self.held = held ?? HeldUpdate()
        self.installsOnArrival = installsOnArrival
        self.schedule = schedule
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
        preferDownloadingUpdates()
        // Sparkle 쪽에서 바뀌는 값도 따라가도록 구독합니다.
        // 알림이 늦게 도착할 수 있으므로, 받은 값이 아니라 그때의 Sparkle 값을 읽어 맞춥니다.
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncFromUpdater() }
            .store(in: &observations)
        updater.publisher(for: \.automaticallyChecksForUpdates)
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
        if lastCheckDate != updater.lastUpdateCheckDate { lastCheckDate = updater.lastUpdateCheckDate }
    }

    // 새 버전은 늘 미리 받아 둡니다 — 그래야 한 번 눌러 설치됩니다. 1.2.1 까지 있던 설정의 "새 버전을 자동으로 받아 설치"를
    // 꺼 둔 적이 있으면 그 값이 남아 있으므로 켭니다(그 스위치는 없어졌습니다).
    // 자동 확인이 꺼져 있으면 Sparkle 은 받지도 않으므로(SPUUpdaterSettings.m) 건드리지 않습니다.
    private func preferDownloadingUpdates() {
        guard let updater, updater.automaticallyChecksForUpdates, !updater.automaticallyDownloadsUpdates else { return }
        updater.automaticallyDownloadsUpdates = true
    }

    /// 사용자가 "지금 확인"을 눌렀을 때. 메뉴 바 앱이라 창이 앞에 오도록 앱을 먼저 활성화합니다.
    func checkForUpdates() {
        guard let controller else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    /// 받아 둔 업데이트의 설치 동작을 맡아 둡니다. 여기서는 실행하지 않습니다 — 사용자가 누를 때 실행합니다.
    func holdInstall(version: String, _ install: @escaping () -> Void) {
        log.notice("holding update \(version, privacy: .public) until the user installs it")
        pendingVersion = version
        held.hold { [weak self] in
            self?.log.notice("installing held update \(version, privacy: .public) now")
            install()
        }
        refreshInstallState()
        // 시험용 스위치: 단추를 누른 것과 같은 길로 곧바로 설치합니다.
        // (Sparkle 이 준 설치 동작은 스스로 다음 차례로 넘겨 실행하므로, 대리자 호출 안에서 불러도 됩니다 — SPUAutomaticUpdateDriver.m)
        if installsOnArrival { installPendingUpdateNow() }
    }

    /// 사용자가 "업데이트"(팝오버)나 "지금 설치하고 다시 켜기"(설정)를 눌렀을 때.
    func installPendingUpdateNow() {
        guard held.isHolding else { return }
        log.notice("user asked to install the held update now")
        if held.installNow() {
            // 설치가 먹지 않아 앱이 꺼지지 않았으면 단추를 다시 누를 수 있어야 하므로, 기다리는 시간이 지난 뒤에 다시 봅니다.
            schedule(held.installTimeout + 1) { [weak self] in self?.refreshInstallState() }
        }
        refreshInstallState()
    }

    /// 메뉴 막대 표시 옆의 "업데이트"를 눌렀을 때. 받아 둔 것이 있으면 설치하고 다시 켜고,
    /// 찾기만 한 것이면 Sparkle 의 안내 창을 앞에 띄웁니다.
    func performIndicatedUpdate() {
        if pendingVersion != nil {
            installPendingUpdateNow()
        } else if availableVersion != nil {
            checkForUpdates()
        }
    }

    /// Sparkle의 업데이트 주기가 끝났거나 오류로 중단됐을 때. 받아 둔 설치 동작은 그 주기의 것이라 더 쓸 수 없으므로 치웁니다
    /// (점과 단추가 사라집니다). 주기는 설치 도우미의 오류나 연결 끊김으로 끝납니다. 도우미까지 끝났으면 다음 확인 때 다시 받고,
    /// 연결만 끊겨 도우미가 남아 있으면 앱을 끌 때 설치됩니다 — 그 경우 다음 정해진 확인은 늦을 수 있고(Sparkle 은 설치를 기다리는
    /// 동안 확인 간격을 늘립니다), "지금 확인"을 누르면 안내 창에서 이어 갑니다.
    func updateCycleDidFinish() {
        if held.isHolding { log.notice("update cycle finished: dropping the held install") }
        held.discard()
        pendingVersion = nil
        refreshInstallState()
    }

    /// 설정 창과 팝오버가 볼 "설치하는 중" 값을 맞춥니다.
    func refreshInstallState() {
        if installInProgress != held.isInstalling { installInProgress = held.isInstalling }
    }

    /// 곧바로 설치할 수 없는 새 버전을 찾았을 때(아래 알리는 방식). 메뉴 막대의 표시만 켭니다.
    func showAvailable(version: String) {
        availableVersion = version
    }

    func clearAvailable() {
        availableVersion = nil
    }
}

// MARK: - 업데이트의 진행

extension UpdateController: SPUUpdaterDelegate {
    // 자동으로 받아 둔 업데이트는 원래 앱을 끌 때 설치됩니다. 메뉴 바 앱은 몇 주씩 켜 두므로 설치 동작을 받아 두었다가,
    // 사용자가 "업데이트"를 누르면 그때 설치하고 다시 켭니다. 누르지 않고 앱을 끄면 Sparkle이 그때 설치합니다.
    // (참을 돌려주면 설치할 때까지 Sparkle의 업데이트 확인이 멈춥니다 — 그동안 "지금 확인"은 쓸 수 없고 더 새 버전도 찾지 않습니다.)
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        holdInstall(version: item.displayVersionString, immediateInstallHandler)
        return true
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        updateCycleDidFinish()
    }

    // 오류로 중단될 때도 치웁니다. (자동으로 받는 경로에서는 오류가 있는 중단 뒤에 주기 끝 알림도 오므로 대개 겹칩니다.
    // 받아 두고 있는 동안에는 다른 확인이 끼어들지 못해, 멀쩡히 받아 둔 것을 여기서 치우는 일은 없습니다.)
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        updateCycleDidFinish()
    }
}

// MARK: - 알리는 방식 (메뉴 바 앱이라 창을 갑자기 띄우지 않습니다)

// 이 대리자는 Sparkle이 메인 스레드에서 부르지만 헤더에 그렇게 표시돼 있지 않아, 메서드를 nonisolated 로 두고 안에서 넘어옵니다.
extension UpdateController: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    // 정해진 확인에서 Sparkle 이 안내 창을 보여 주려 할 때입니다(스스로 받을 수 없는 업데이트, 설치를 이어 가야 하는 경우).
    // 앱을 방금 켰을 때에도 창을 띄우지 않고 메뉴 막대의 표시로만 알립니다. 표시 옆의 "업데이트"를 누르면 그때 안내 창이 앞에 뜹니다.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        let version = update.displayVersionString
        MainActor.assumeIsolated { showAvailable(version: version) }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { clearAvailable() }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { clearAvailable() }
    }
}
