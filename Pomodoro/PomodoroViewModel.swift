// File: PomodoroViewModel.swift
// Description: 앱의 핵심 로직(상태, 타이머, 알림, 데이터 저장)을 관리하는 ViewModel입니다.

import SwiftUI
import Combine
import SwiftData
import UserNotifications
import AppKit

// ... (PomodoroState, TimerState Enums - 변경 없음)
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
    @AppStorage("focusDuration") var focusDurationInMinutes: Int = 25
    @AppStorage("shortBreakDuration") var shortBreakDurationInMinutes: Int = 5
    @AppStorage("longBreakDuration") var longBreakDurationInMinutes: Int = 15
    @AppStorage("longBreakInterval") var longBreakInterval: Int = 4

    @Published var currentState: PomodoroState = .idle
    @Published var timerState: TimerState = .idle
    @Published var timeRemaining: TimeInterval = 0
    @Published var hasNotificationPermission: Bool = false
    @Published var completedFocusSessions: Int = 0

    private var timerSubscription: AnyCancellable?
    private let notificationIdentifier = "pomodoro_session_end"
    private var lastResumeTime: Date?
    private var accumulatedActiveTime: TimeInterval = 0
    private var modelContext: ModelContext
    private weak var appDelegate: AppDelegate?

    init(modelContext: ModelContext, appDelegate: AppDelegate) {
        self.modelContext = modelContext
        self.appDelegate = appDelegate
        self.timeRemaining = TimeInterval(focusDurationInMinutes * 60)
    }

    var timeRemainingString: String {
        let minutes = Int(timeRemaining) / 60
        let seconds = Int(timeRemaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var progress: Double {
        let totalDuration = getTotalDuration(for: currentState)
        guard totalDuration > 0 else { return 0 }
        let elapsedTime = totalDuration - timeRemaining
        return min(max(elapsedTime / totalDuration, 0.0), 1.0)
    }

    func startFocusSession() {
        guard timerState == .idle else { return }
        if currentState == .idle {
            completedFocusSessions = 0
            currentState = .focus
        }
        startTimer(duration: getTotalDuration(for: currentState))
    }

    func pauseTimer() {
        guard timerState == .running, let resumeTime = lastResumeTime else { return }
        accumulatedActiveTime += Date().timeIntervalSince(resumeTime)
        lastResumeTime = nil
        timerSubscription?.cancel()
        timerState = .paused
        cancelPendingNotifications()
    }

    func resumeTimer() {
        guard timerState == .paused else { return }
        lastResumeTime = Date()
        startTimer(duration: timeRemaining, isResuming: true)
    }

    func skipToNextSession() {
        timerDidEnd(skipped: true)
    }

    func resetToIdle() {
        logSession()
        timerSubscription?.cancel()
        currentState = .idle
        timerState = .idle
        timeRemaining = TimeInterval(focusDurationInMinutes * 60)
        completedFocusSessions = 0
        cancelPendingNotifications()
        lastResumeTime = nil
        accumulatedActiveTime = 0
    }

    private func startTimer(duration: TimeInterval, isResuming: Bool = false) {
        if !isResuming {
            accumulatedActiveTime = 0
        }
        lastResumeTime = Date()
        timeRemaining = duration
        timerState = .running
        
        cancelPendingNotifications()
        scheduleNotification(duration: duration)

        timerSubscription = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.timeRemaining >= 1 {
                    self.timeRemaining -= 1
                } else {
                    self.timeRemaining = 0
                    self.timerDidEnd()
                }
            }
    }
    
    private func timerDidEnd(skipped: Bool = false) {
        timerSubscription?.cancel()
        if !skipped {
            playSound()
            scheduleNotification(duration: 0.1)
            appDelegate?.bringPopoverToFront()
        }
        
        logSession()
        transitionToNextState()
    }

    private func transitionToNextState() {
        let previousState = currentState
        
        let nextState: PomodoroState
        switch previousState {
        case .focus:
            completedFocusSessions += 1
            nextState = (completedFocusSessions > 0 && completedFocusSessions % longBreakInterval == 0) ? .longBreak : .shortBreak
        case .shortBreak, .longBreak, .idle:
            nextState = .focus
        }
        currentState = nextState
        
        // **FIX**: 다음 세션을 자동으로 시작합니다.
        startTimer(duration: getTotalDuration(for: nextState))
    }

    private func getTotalDuration(for state: PomodoroState) -> TimeInterval {
        switch state {
        case .focus: TimeInterval(focusDurationInMinutes * 60)
        case .shortBreak: TimeInterval(shortBreakDurationInMinutes * 60)
        case .longBreak: TimeInterval(longBreakDurationInMinutes * 60)
        case .idle: TimeInterval(focusDurationInMinutes * 60)
        }
    }

    private func logSession() {
        guard currentState != .idle else { return }
        
        var totalActiveDuration = accumulatedActiveTime
        if let resumeTime = lastResumeTime {
            totalActiveDuration += Date().timeIntervalSince(resumeTime)
        }
        
        let maxDuration = getTotalDuration(for: currentState)
        let finalDuration = (timeRemaining == 0 && timerState != .paused) ? maxDuration : min(totalActiveDuration, maxDuration)
        
        guard finalDuration >= 1 else { return }
        
        let actualStartTime = Date().addingTimeInterval(-finalDuration)
        let newLog = FocusLogEntry(startTime: actualStartTime, duration: finalDuration, sessionType: currentState)
        
        modelContext.insert(newLog)
        try? modelContext.save()
    }

    private func playSound() {
        NSSound(named: "Glass")?.play()
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

    private func scheduleNotification(duration: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "\(currentState.description) 종료!"
        content.body = "다음 세션을 시작할 준비가 되었습니다."
        content.sound = .default
        
        let trigger = duration > 0.1 ? UNTimeIntervalNotificationTrigger(timeInterval: duration, repeats: false) : nil
        let request = UNNotificationRequest(identifier: notificationIdentifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelPendingNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
    }
}
