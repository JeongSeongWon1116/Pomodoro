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
enum TimerState { case running, paused, idle }

@MainActor
class PomodoroViewModel: ObservableObject {
    @Published var currentState: PomodoroState = .idle
    @Published var timerState: TimerState = .idle
    @Published var timeRemaining: TimeInterval = 0
    @Published var hasNotificationPermission: Bool = false
    @Published var completedFocusSessions: Int = 0

    let settings = AppSettings.shared

    private var timerSubscription: AnyCancellable?
    private var settingsSubscription: AnyCancellable?
    private let sessionNotificationId = "pomodoro_session"
    private var lastResumeTime: Date?
    private var accumulatedActiveTime: TimeInterval = 0
    private var sessionStartTime: Date? // 세션의 실제 시작 시간
    private var lastPauseTime: Date? // 정지 시작 시간
    private var accumulatedPausedTime: TimeInterval = 0 // 누적 정지 시간
    private var sessionDuration: TimeInterval = 0 // 현재 세션의 전체 길이
    private var modelContext: ModelContext
    private weak var appDelegate: AppDelegate?

    init(modelContext: ModelContext, appDelegate: AppDelegate) {
        self.modelContext = modelContext
        self.appDelegate = appDelegate
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
        let interval = max(1, settings.longBreakInterval)
        let remainder = completedFocusSessions % interval
        // 긴 휴식 직전(= 배수)에는 가득 찬 상태로 보여줍니다.
        if completedFocusSessions > 0 && remainder == 0 && currentState != .focus && currentState != .idle {
            return interval
        }
        return remainder
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
        accumulatedActiveTime = min(accumulatedActiveTime + Date().timeIntervalSince(resumeTime), sessionDuration)
        lastResumeTime = nil
        lastPauseTime = Date()
        timerSubscription?.cancel()
        timerState = .paused
    }

    func resumeTimer() {
        guard timerState == .paused else { return }
        if let pauseTime = lastPauseTime {
            accumulatedPausedTime += Date().timeIntervalSince(pauseTime)
            lastPauseTime = nil
        }
        startTicking()
    }

    func skipToNextSession() {
        guard timerState != .idle else { return }
        timerDidEnd(skipped: true)
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
        sessionStartTime = Date()
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
        lastResumeTime = Date()
        timerState = .running
        updateTimeRemaining()

        timerSubscription = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateTimeRemaining()
                if self.timerState == .running && self.timeRemaining <= 0 {
                    self.timerDidEnd()
                }
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
            active += Date().timeIntervalSince(resumeTime)
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
    }

    private func timerDidEnd(skipped: Bool = false) {
        timerSubscription?.cancel()

        let endedSessionType = currentState
        let nextSessionType = getNextSessionType(from: endedSessionType)
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

        if endedSessionType == .focus {
            completedFocusSessions += 1
        }

        if shouldAutoStart {
            startSession(nextSessionType)
        } else {
            prepareSession(nextSessionType)
        }
    }

    /// 다음 세션 타입을 계산
    private func getNextSessionType(from current: PomodoroState) -> PomodoroState {
        switch current {
        case .focus:
            let nextCount = completedFocusSessions + 1
            return (nextCount > 0 && nextCount % settings.longBreakInterval == 0) ? .longBreak : .shortBreak
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

    private func logSession() {
        guard currentState != .idle else { return }
        guard let startTime = sessionStartTime else { return }

        let endTime = Date()

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

        ObsidianExporter.shared.appendSession(newLog)
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

    /// 앱 종료 시 모든 알림 취소
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
}
