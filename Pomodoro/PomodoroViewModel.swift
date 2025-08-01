import Foundation
import Combine
import SwiftUI
import UserNotifications
import SwiftData

// MARK: - Main Class Definition & Core Properties

// 섹션 4.3의 계획에 따라 모든 비즈니스 로직과 상태를 캡슐화하는 ViewModel.[1]
// ObservableObject 프로토콜을 준수하여 SwiftUI 뷰가 변경 사항을 구독할 수 있도록 합니다.
class PomodoroViewModel: ObservableObject {
    
    // MARK: - Published Properties for UI State
    
    // @Published 프로퍼티는 값이 변경될 때마다 뷰의 업데이트를 자동으로 트리거합니다.
    @Published var pomodoroState: PomodoroState = .idle
    @Published var timeRemaining: TimeInterval = 25 * 60
    @Published var progress: Double = 0.0
    @Published var completedSessions: Int = 0

    // MARK: - User Settings using @AppStorage
    
    // 섹션 1.3.2의 계획에 따라 @AppStorage를 사용하여 사용자 설정을 UserDefaults에 영속적으로 저장합니다.[1]
    // UI 컨트롤이 이 프로퍼티에 직접 바인딩되면, 변경 사항이 즉시 저장되고 앱 전체에 반영됩니다.
    @AppStorage("focusDuration") var focusDurationInMinutes: Double = 25
    @AppStorage("shortBreakDuration") var shortBreakDurationInMinutes: Double = 5
    @AppStorage("longBreakDuration") var longBreakDurationInMinutes: Double = 15
    @AppStorage("sessionsUntilLongBreak") var sessionsUntilLongBreak: Int = 4
    
    // MARK: - Private Properties
    
    // Combine 타이머 구독을 관리하기 위한 프로퍼티. 타이머를 취소(일시정지)할 때 필요합니다.[1]
    private var timerSubscription: AnyCancellable?
    private var totalDuration: TimeInterval = 25 * 60
    
    // SwiftData 저장을 위한 ModelContext. PomodoroApp에서 주입받습니다.
    private var modelContext: ModelContext?

    // MARK: - Computed Properties for UI Display
    
    // TimeInterval을 "MM:SS" 형식의 문자열로 변환하여 뷰에 제공합니다.
    var timeRemainingString: String {
        let minutes = Int(timeRemaining) / 60
        let seconds = Int(timeRemaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // 현재 타이머 상태에 따라 제어 버튼의 텍스트를 결정합니다.
    var mainButtonTitle: String {
        switch pomodoroState {
        case.idle:
            return "집중 시작"
        case.focus,.shortBreak,.longBreak:
            return "일시정지"
        case.paused:
            return "재개"
        }
    }
    
    init() {
        // 앱이 처음 시작될 때 초기 시간을 설정 값에 맞춥니다.
        self.timeRemaining = focusDurationInMinutes * 60
        self.totalDuration = focusDurationInMinutes * 60
    }
    
    // PomodoroApp에서 ModelContext를 주입받기 위한 메서드
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
}

// MARK: - Timer Control & State Machine

extension PomodoroViewModel {
    
    // 섹션 4.1.1에서 정의한 상태 머신 [1]
    enum PomodoroState {
        case idle, focus, shortBreak, longBreak, paused
    }
    
    // 메인 컨트롤 버튼을 눌렀을 때 호출되는 메서드
    func mainButtonTapped() {
        switch pomodoroState {
        case.idle:
            startFocusSession()
        case.focus,.shortBreak,.longBreak:
            pauseTimer()
        case.paused:
            resumeTimer()
        }
    }

    // 집중 세션 시작
    func startFocusSession() {
        pomodoroState = .focus
        totalDuration = focusDurationInMinutes * 60
        timeRemaining = totalDuration
        startTimer()
        scheduleNotification(for:.focus)
    }
    
    // 짧은 휴식 시작
    private func startShortBreak() {
        pomodoroState = .shortBreak
        totalDuration = shortBreakDurationInMinutes * 60
        timeRemaining = totalDuration
        startTimer()
        scheduleNotification(for:.shortBreak)
    }
    
    // 긴 휴식 시작
    private func startLongBreak() {
        pomodoroState = .longBreak
        totalDuration = longBreakDurationInMinutes * 60
        timeRemaining = totalDuration
        startTimer()
        scheduleNotification(for:.longBreak)
    }
    
    // 다음 세션으로 건너뛰기
    func skipToNextSession() {
        timerSubscription?.cancel()
        cancelPendingNotifications()
        transitionToNextState()
    }
    
    // 타이머가 0이 되었을 때 다음 상태로 전환하는 로직
    private func transitionToNextState() {
        switch pomodoroState {
        case.focus:
            completedSessions += 1
            saveFocusLog() // 집중 세션 완료 후 로그 저장
            if completedSessions % sessionsUntilLongBreak == 0 {
                startLongBreak()
            } else {
                startShortBreak()
            }
        case.shortBreak,.longBreak:
            startFocusSession()
        default:
            resetToIdle()
        }
    }
    
    // 타이머를 초기 상태로 리셋
    func resetTimer() {
        resetToIdle()
    }
    
    private func resetToIdle() {
        pomodoroState = .idle
        timerSubscription?.cancel()
        cancelPendingNotifications()
        timeRemaining = focusDurationInMinutes * 60
        totalDuration = focusDurationInMinutes * 60
        progress = 0.0
        completedSessions = 0
    }

    // 섹션 4.2.1의 계획에 따른 Combine 타이머 시작 로직 [1]
    private func startTimer() {
        progress = 1.0
        
        // 1초마다 메인 스레드에서 이벤트를 방출하는 타이머 Publisher 생성.
        //.common 모드는 스크롤 중에도 타이머가 멈추지 않도록 보장합니다.
        timerSubscription = Timer.publish(every: 1, on:.main, in:.common)
          .autoconnect()
          .sink { [weak self] _ in
                guard let self = self else { return }
                
                if self.timeRemaining > 0 {
                    self.timeRemaining -= 1
                    self.progress = self.timeRemaining / self.totalDuration
                } else {
                    self.timerSubscription?.cancel()
                    self.transitionToNextState()
                }
            }
    }
    
    // 섹션 4.2.3의 계획에 따른 '올바른' 일시정지 로직 [1]
    // 구독 자체를 취소하여 불필요한 자원 소모를 막습니다.
    private func pauseTimer() {
        timerSubscription?.cancel()
        // 현재 상태를 paused로 변경하기 전에, 원래 상태가 무엇이었는지 임시로 저장할 수도 있지만,
        // 여기서는 단순화를 위해 하나의 'paused' 상태로 통일합니다.
        pomodoroState = .paused
        cancelPendingNotifications() // 일시정지 시 예약된 알림 취소
    }
    
    // 섹션 4.2.3의 계획에 따른 '올바른' 재개 로직 [1]
    // 새로운 구독을 생성하여 타이머를 다시 시작합니다.
    private func resumeTimer() {
        // 원래 상태로 복원. (예: paused 상태가 되기 전이 focus였다면 focus로)
        // 이 예제에서는 단순화를 위해 재개 시 항상 focus로 돌아간다고 가정하거나,
        // 이전 상태를 저장하는 로직을 추가할 수 있습니다. 여기서는 focus로 가정합니다.
        // 더 정교한 구현을 원한다면 `paused(from: PomodoroState)`와 같이 연관값을 사용할 수 있습니다.
        if completedSessions % sessionsUntilLongBreak == 0 && completedSessions > 0 {
            pomodoroState = .longBreak
        } else if completedSessions > 0 {
            pomodoroState = .shortBreak
        } else {
            pomodoroState = .focus
        }
        
        startTimer()
        // 재개 시 다시 알림을 스케줄합니다.
        scheduleNotification(for: pomodoroState)
    }
}

// MARK: - User Notifications

extension PomodoroViewModel {
    
    // 섹션 5.1의 계획에 따른 알림 스케줄링 로직 [1]
    private func scheduleNotification(for state: PomodoroState) {
        let content = UNMutableNotificationContent()
        
        switch state {
        case.focus:
            content.title = "집중 시간 종료!"
            content.body = "수고하셨습니다. 잠시 휴식을 취할 시간입니다."
        case.shortBreak:
            content.title = "짧은 휴식 종료"
            content.body = "다시 집중할 시간입니다."
        case.longBreak:
            content.title = "긴 휴식 종료"
            content.body = "상쾌한 기분으로 다음 세션을 시작하세요."
        default:
            return // idle, paused 상태에서는 알림을 보내지 않음
        }
        
        // 섹션 5.2.1의 권장 사항에 따라 시스템 기본 사운드를 사용합니다.[1]
        // 커스텀 사운드를 사용하려면 프로젝트에 사운드 파일을 추가하고 파일명을 지정하면 됩니다.
        // 예: content.sound = UNNotificationSound(named: UNNotificationSoundName("alarm.wav"))
        content.sound = .default

        // 현재 남은 시간 후에 알림이 트리거되도록 설정합니다.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeRemaining, repeats: false)
        
        // 알림 요청 생성 및 시스템에 추가
        let request = UNNotificationRequest(identifier: "POMODORO_SESSION_END", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error)")
            }
        }
    }
    
    // 섹션 5.1.2의 요구사항에 따라, 예약된 알림을 취소하는 기능.[1]
    // 사용자가 세션을 건너뛰거나 일시정지할 때 호출되어 불필요한 알림을 방지합니다.
    private func cancelPendingNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    // 앱 시작 시 사용자에게 알림 권한을 요청하는 static 메서드
    static func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert,.sound,.badge]) { granted, error in
            if granted {
                print("Notification permission granted.")
            } else if let error = error {
                print("Error requesting notification permission: \(error)")
            }
        }
    }
}


// MARK: - Data Persistence (SwiftData)

extension PomodoroViewModel {
    
    // 섹션 6.1.2의 계획에 따라 완료된 집중 세션을 SwiftData에 저장합니다.[1]
    private func saveFocusLog() {
        guard let context = modelContext else {
            print("ModelContext is not available.")
            return
        }
        
        let startTime = Date().addingTimeInterval(-focusDurationInMinutes * 60)
        let newLog = FocusLogEntry(startTime: startTime, duration: focusDurationInMinutes * 60)
        
        context.insert(newLog)
        
        do {
            try context.save()
            print("Focus log saved successfully.")
        } catch {
            print("Failed to save focus log: \(error)")
        }
    }
}
