// File: PomodoroViewModel.swift
// Description: 앱의 핵심 로직(상태, 타이머, 알림, 데이터 저장)을 관리하는 ViewModel입니다.

import SwiftUI
import Combine
import SwiftData
import UserNotifications
import AppKit

enum PomodoroState: String, Codable, CaseIterable {
    case idle = "대기", focus = "집중", shortBreak = "짧은 휴식", longBreak = "긴 휴식"
    var description: String { self.rawValue }
    var emoji: String {
        switch self {
        case .idle: "⏳"
        case .focus: "🍅"
        case .shortBreak: "☕️"
        case .longBreak: "🎉"
        }
    }
}
/// awaitingChoice: 집중 시간이 다 되어, 휴식을 시작할지 연장할지 고르기를 기다리는 상태
enum TimerState { case running, paused, idle, awaitingChoice }

@MainActor
class PomodoroViewModel: ObservableObject {
    /// 연장 한 번에 늘어나는 집중 시간
    static let focusExtension: TimeInterval = 10 * 60
    private static let focusTaskKey = "transitionFocusTask"
    private static let focusRewardKey = "transitionFocusReward"
    private static let resumeHintKey = "transitionResumeHint"

    @Published var currentState: PomodoroState = .idle
    @Published var timerState: TimerState = .idle
    @Published var timeRemaining: TimeInterval = 0
    @Published var hasNotificationPermission: Bool = false
    @Published var completedFocusSessions: Int = 0

    /// 이번 집중에서 할 일과, 끝나면 받을 보상. 고칠 때까지 다음 집중에도 그대로 남습니다.
    @Published var focusTask: String {
        didSet { settings.defaults?.set(focusTask, forKey: Self.focusTaskKey) }
    }
    @Published var focusReward: String {
        didSet { settings.defaults?.set(focusReward, forKey: Self.focusRewardKey) }
    }
    /// 선택 화면에서 적는, 다음에 이어서 시작할 자리
    @Published var nextStartingPoint: String = ""
    /// 지난 집중을 마치며 적어 둔 다음 시작점 (이번 집중에서 "이어서"로 보여 줍니다)
    @Published private(set) var resumeHint: String {
        didSet { settings.defaults?.set(resumeHint, forKey: Self.resumeHintKey) }
    }
    /// 이번 집중을 연장한 횟수
    @Published private(set) var extensionCount: Int = 0

    let settings: AppSettings
    // 현재 시각 공급자. 테스트에서 실제 시간을 기다리지 않고 시계를 주입하기 위한 이음매입니다.
    private let now: () -> Date

    private var timerSubscription: AnyCancellable?
    private var settingsSubscription: AnyCancellable?
    private let sessionNotificationId = "pomodoro_session"
    private var lastResumeTime: Date?
    private var accumulatedActiveTime: TimeInterval = 0
    private var sessionStartTime: Date? // 세션의 실제 시작 시간
    private var lastPauseTime: Date? // 정지 시작 시간
    private var accumulatedPausedTime: TimeInterval = 0 // 누적 정지 시간
    private var sessionDuration: TimeInterval = 0 // 현재 세션의 전체 길이
    private var awaitingSince: Date? // 집중 시간이 다 된 시각 (선택을 기다리는 동안에만 값이 있음)
    private var modelContext: ModelContext
    private let notesContext: ModelContext? // 할 일·보상·다음 시작점을 두는 별도 저장소. nil 이면 저장하지 않습니다.
    private weak var appDelegate: AppDelegate?

    init(
        modelContext: ModelContext,
        appDelegate: AppDelegate,
        settings: AppSettings = .shared,
        notesContext: ModelContext? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.notesContext = notesContext
        self.settings = settings
        self.now = now
        self.appDelegate = appDelegate
        self.focusTask = settings.defaults?.string(forKey: Self.focusTaskKey) ?? ""
        self.focusReward = settings.defaults?.string(forKey: Self.focusRewardKey) ?? ""
        self.resumeHint = settings.defaults?.string(forKey: Self.resumeHintKey) ?? ""
        self.timeRemaining = TimeInterval(settings.focusDurationInMinutes * 60)

        // 타이머가 돌지 않을 때 설정에서 시간을 바꾸면 대기 화면의 표시 시간을 갱신합니다.
        // ($ publisher는 willSet 시점에 발행되므로 다음 런루프에서 새 값을 읽습니다.)
        settingsSubscription = Publishers.MergeMany(
            settings.$focusDurationInMinutes,
            settings.$shortBreakDurationInMinutes,
            settings.$longBreakDurationInMinutes
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.refreshIdleTimeRemaining()
        }
    }

    var timeRemainingString: String {
        let totalSeconds = max(0, Int(timeRemaining.rounded(.up)))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    var progress: Double {
        guard sessionDuration > 0 else { return 0 }
        let elapsedTime = sessionDuration - timeRemaining
        return min(max(elapsedTime / sessionDuration, 0.0), 1.0)
    }

    /// 긴 휴식까지 남은 사이클 표시용 (현재 사이클에서 완료한 집중 횟수)
    var focusSessionsInCurrentCycle: Int {
        let interval = AppSettings.validLongBreakInterval(settings.longBreakInterval)
        let remainder = completedFocusSessions % interval
        // 긴 휴식 직전(= 배수)에는 가득 찬 상태로 보여줍니다.
        if completedFocusSessions > 0 && remainder == 0 && currentState != .focus && currentState != .idle {
            return interval
        }
        return remainder
    }

    // NSApp.delegate는 SwiftUI 라이프사이클에서 우리 AppDelegate가 아닐 수 있어
    // (캐스트 실패 → 조용히 무시됨), init에서 직접 주입받은 참조로 팝오버를 닫습니다.
    func closePopover() {
        appDelegate?.closePopover()
    }

    func startFocusSession() {
        guard timerState == .idle else { return }
        if currentState == .idle {
            completedFocusSessions = 0
        }
        startSession(currentState == .idle ? .focus : currentState)
    }

    func pauseTimer() {
        guard timerState == .running, let resumeTime = lastResumeTime else { return }
        accumulatedActiveTime = min(accumulatedActiveTime + now().timeIntervalSince(resumeTime), sessionDuration)
        lastResumeTime = nil
        lastPauseTime = now()
        timerSubscription?.cancel()
        timerState = .paused
    }

    func resumeTimer() {
        guard timerState == .paused else { return }
        if let pauseTime = lastPauseTime {
            accumulatedPausedTime += now().timeIntervalSince(pauseTime)
            lastPauseTime = nil
        }
        startTicking()
    }

    func skipToNextSession() {
        // 선택을 기다리는 집중은 이미 끝까지 마친 것이라 건너뛸 것이 없습니다.
        guard timerState == .running || timerState == .paused else { return }
        timerDidEnd(skipped: true)
    }

    /// 선택 화면의 "휴식 시작": 마친 집중을 기록하고 휴식을 바로 시작합니다.
    /// (직접 고른 것이므로 휴식 자동 시작 설정과 상관없이 시작합니다.)
    func startBreakAfterFocus() {
        guard timerState == .awaitingChoice else { return }
        let nextSessionType = getNextSessionType(from: .focus)
        logSession(choseBreak: true)
        completedFocusSessions += 1
        startSession(nextSessionType)
    }

    /// 선택 화면의 "10분 더": 같은 집중을 이어 갑니다.
    /// 기다리는 상태에서만 받으므로 연달아 눌러도 한 번만 늘어납니다.
    func extendFocus() {
        guard timerState == .awaitingChoice, let since = awaitingSince else { return }
        // 고르기까지 기다린 시간은 정지 시간으로 셉니다 (종료 시각 = 시작 + 활동 + 정지).
        accumulatedPausedTime += now().timeIntervalSince(since)
        awaitingSince = nil
        sessionDuration += Self.focusExtension
        extensionCount += 1
        startTicking()
    }

    func resetToIdle() {
        guard timerState != .idle || currentState != .idle else { return }
        logSession()
        timerSubscription?.cancel()
        currentState = .idle
        timerState = .idle
        completedFocusSessions = 0
        clearSessionTracking()
        timeRemaining = TimeInterval(settings.focusDurationInMinutes * 60)
    }

    private func startSession(_ state: PomodoroState) {
        clearSessionTracking()
        currentState = state
        sessionDuration = getTotalDuration(for: state)
        sessionStartTime = now()
        startTicking()
    }

    /// 자동 시작이 꺼져 있을 때: 다음 세션을 대기 상태로 준비만 해 둡니다.
    private func prepareSession(_ state: PomodoroState) {
        clearSessionTracking()
        currentState = state
        sessionDuration = getTotalDuration(for: state)
        timeRemaining = sessionDuration
        timerState = .idle
    }

    private func startTicking() {
        lastResumeTime = now()
        timerState = .running
        updateTimeRemaining()

        timerSubscription = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    /// 타이머 한 틱: 남은 시간을 다시 계산하고, 다 되었으면 세션을 끝냅니다.
    func tick() {
        updateTimeRemaining()
        if timerState == .running && timeRemaining <= 0 {
            timerDidEnd()
        }
    }

    // 틱마다 1초씩 빼는 방식은 절전 모드나 타이머 지연 시 시간이 실제보다 늦게 가는
    // 문제가 있어, 벽시계 기준으로 남은 시간을 다시 계산합니다.
    private func updateTimeRemaining() {
        guard timerState == .running else { return }
        timeRemaining = max(0, sessionDuration - currentActiveTime())
    }

    private func currentActiveTime() -> TimeInterval {
        var active = accumulatedActiveTime
        if let resumeTime = lastResumeTime {
            active += now().timeIntervalSince(resumeTime)
        }
        return active
    }

    private func clearSessionTracking() {
        lastResumeTime = nil
        accumulatedActiveTime = 0
        sessionStartTime = nil
        lastPauseTime = nil
        accumulatedPausedTime = 0
        sessionDuration = 0
        awaitingSince = nil
        extensionCount = 0
    }

    private func timerDidEnd(skipped: Bool = false) {
        timerSubscription?.cancel()

        if currentState == .focus && !skipped && settings.transitionManagementEnabled {
            awaitFocusChoice()
            return
        }

        let endedSessionType = currentState
        // 연장한 집중은 원래 시간을 이미 다 채웠으므로, 연장 중에 건너뛰어도 마친 집중으로 셉니다.
        let countsAsSkipped = skipped && !(endedSessionType == .focus && extensionCount > 0)
        let nextSessionType = getNextSessionType(from: endedSessionType, skipped: countsAsSkipped)
        let shouldAutoStart = nextSessionType == .focus
            ? settings.autoStartFocus
            : settings.autoStartBreaks

        if !skipped {
            playSound()
            showSessionTransitionNotification(
                ended: endedSessionType,
                next: nextSessionType,
                autoStarting: shouldAutoStart
            )
        }

        logSession()

        // 건너뛴 집중은 완료한 것으로 세지 않습니다.
        if endedSessionType == .focus && !countsAsSkipped {
            completedFocusSessions += 1
        }

        if shouldAutoStart {
            startSession(nextSessionType)
        } else {
            prepareSession(nextSessionType)
        }
    }

    /// 집중 시간이 다 됨: 다음으로 넘어가지 않고 선택(휴식 시작 / 연장)을 기다립니다.
    /// 기록은 고른 뒤에 남깁니다. 연장하면 같은 세션이 이어지기 때문입니다.
    private func awaitFocusChoice() {
        // 절전 등으로 틱이 늦게 와도, 끝난 시각은 시간이 실제로 다 된 때로 잡습니다.
        let current = now()
        let deadline = lastResumeTime?.addingTimeInterval(sessionDuration - accumulatedActiveTime) ?? current
        awaitingSince = min(deadline, current)
        accumulatedActiveTime = sessionDuration
        lastResumeTime = nil
        timeRemaining = 0
        timerState = .awaitingChoice
        playSound()
        showFocusEndedNotification()
    }

    /// 다음 세션 타입을 계산
    private func getNextSessionType(from current: PomodoroState, skipped: Bool = false) -> PomodoroState {
        switch current {
        case .focus:
            // 건너뛴 집중은 횟수에 들어가지 않으므로 긴 휴식으로 이어지지 않습니다.
            if skipped { return .shortBreak }
            let nextCount = completedFocusSessions + 1
            let interval = AppSettings.validLongBreakInterval(settings.longBreakInterval)
            return (nextCount > 0 && nextCount % interval == 0) ? .longBreak : .shortBreak
        case .shortBreak, .longBreak, .idle:
            return .focus
        }
    }

    private func getTotalDuration(for state: PomodoroState) -> TimeInterval {
        switch state {
        case .focus: TimeInterval(settings.focusDurationInMinutes * 60)
        case .shortBreak: TimeInterval(settings.shortBreakDurationInMinutes * 60)
        case .longBreak: TimeInterval(settings.longBreakDurationInMinutes * 60)
        case .idle: TimeInterval(settings.focusDurationInMinutes * 60)
        }
    }

    private func refreshIdleTimeRemaining() {
        guard timerState == .idle else { return }
        if currentState == .idle {
            timeRemaining = TimeInterval(settings.focusDurationInMinutes * 60)
        } else {
            // 자동 시작 꺼짐으로 대기 중인 세션의 표시 시간도 갱신
            sessionDuration = getTotalDuration(for: currentState)
            timeRemaining = sessionDuration
        }
    }

    /// choseBreak: 선택 화면에서 "휴식 시작"을 골라 끝낸 집중인지 여부
    private func logSession(choseBreak: Bool = false) {
        guard currentState != .idle else { return }
        guard let startTime = sessionStartTime else { return }

        // 선택을 기다리던 집중은 고른 때가 아니라 시간이 다 된 때에 끝난 것으로 적습니다.
        let endedFromChoice = awaitingSince != nil
        let endTime = awaitingSince ?? now()

        // 실제 활동 시간 계산
        var totalActiveDuration = accumulatedActiveTime
        if let resumeTime = lastResumeTime {
            totalActiveDuration += endTime.timeIntervalSince(resumeTime)
        }

        // 정지 시간 계산 (현재 정지 중이면 그 시간도 포함)
        var totalPausedDuration = accumulatedPausedTime
        if let pauseTime = lastPauseTime {
            totalPausedDuration += endTime.timeIntervalSince(pauseTime)
        }

        let finalDuration = min(totalActiveDuration, sessionDuration)
        guard finalDuration >= 1 else { return }

        let newLog = FocusLogEntry(
            startTime: startTime,
            endTime: endTime,
            duration: finalDuration,
            pausedDuration: totalPausedDuration,
            sessionType: currentState
        )

        modelContext.insert(newLog)
        try? modelContext.save()

        var details: TransitionDetails?
        if currentState == .focus {
            details = collectTransitionDetails(endedFromChoice: endedFromChoice, choseBreak: choseBreak)
            // 메모 저장소를 열지 못했으면(notesContext 가 nil) 모델을 만들지 않고 Obsidian 에만 남깁니다.
            if let details, let notesContext {
                notesContext.insert(TransitionNote(sessionID: newLog.id, details: details, createdAt: newLog.endTime))
                try? notesContext.save()
            }
        }
        ObsidianExporter.shared.appendSession(newLog, details: details)
    }

    /// 끝난 집중에 붙일 할 일·보상·다음 시작점·연장 횟수를 모으고, 다음 시작점 초안을 정리합니다.
    /// 남길 것이 없으면 nil 을 돌려줍니다.
    private func collectTransitionDetails(endedFromChoice: Bool, choseBreak: Bool) -> TransitionDetails? {
        // 다음 시작점은 선택 화면에서만 적을 수 있으므로, 그 화면을 한 번이라도 거친 집중에만 붙입니다.
        let passedChoice = endedFromChoice || extensionCount > 0
        // 전환 관리를 꺼 두었으면 메모를 남기지 않습니다 (끄기 전에 들어간 선택 화면은 마저 처리).
        guard settings.transitionManagementEnabled || passedChoice else { return nil }

        let trim = { (text: String) in text.trimmingCharacters(in: .whitespacesAndNewlines) }
        var details = TransitionDetails(task: trim(focusTask), reward: trim(focusReward), extensionCount: extensionCount)
        if passedChoice {
            details.nextStartingPoint = trim(nextStartingPoint)
            // 적은 것이 있으면 다음 집중의 "이어서"가 됩니다. 비워 둔 채 휴식을 고르면 지난 것을 지우고
            // (그것으로 시작한 집중을 마쳤으므로), 초기화나 종료로 끝났으면 지난 것을 그대로 둡니다.
            if !details.nextStartingPoint.isEmpty || choseBreak {
                resumeHint = details.nextStartingPoint
            }
            nextStartingPoint = ""
        }
        return details.isEmpty ? nil : details
    }

    /// 앱 종료 직전에 진행 중인 세션을 중단된 기록으로 남깁니다.
    /// 기록한 뒤 추적 값을 비우므로 여러 번 불려도 한 번만 남습니다.
    func logInterruptedSession() {
        guard sessionStartTime != nil else { return }
        logSession()
        timerSubscription?.cancel()
        clearSessionTracking()
    }

    private func playSound() {
        let soundName = settings.notificationSoundName
        guard soundName != AppSettings.soundOff else { return }
        NSSound(named: soundName)?.play()
    }

    func requestNotificationPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            self.hasNotificationPermission = granted
        } catch {
            print("알림 권한 요청 실패: \(error)")
            self.hasNotificationPermission = false
        }
    }

    func checkNotificationSettings() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        self.hasNotificationPermission = (settings.authorizationStatus == .authorized)
    }

    /// 세션 전환 알림 (종료 + 시작을 하나로 통합)
    private func showSessionTransitionNotification(ended: PomodoroState, next: PomodoroState, autoStarting: Bool) {
        // 테스트 호스트에서는 사용 중인 앱과 같은 번들 ID로 알림이 뜨지 않도록 건너뜁니다.
        if DataController.isRunningTests { return }
        let content = UNMutableNotificationContent()
        content.title = "\(ended.description) 종료!"
        content.body = autoStarting
            ? "\(next.description) 세션을 시작합니다."
            : "\(next.description) 세션이 준비되었습니다. 메뉴 바에서 시작하세요."
        // 알림음은 NSSound로 직접 재생하므로 시스템 알림음과 겹치지 않게 끕니다.
        content.sound = nil

        let request = UNNotificationRequest(identifier: sessionNotificationId, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// 집중이 끝나 선택을 기다린다는 알림
    private func showFocusEndedNotification() {
        if DataController.isRunningTests { return }
        let content = UNMutableNotificationContent()
        content.title = "\(PomodoroState.focus.description) 종료!"
        let reward = focusReward.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = "메뉴 바에서 휴식을 시작하거나 10분 연장하세요."
        content.body = reward.isEmpty ? prompt : "보상: \(reward)\n\(prompt)"
        content.sound = nil

        let request = UNNotificationRequest(identifier: sessionNotificationId, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// 앱 종료 시 모든 알림 취소
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
}
