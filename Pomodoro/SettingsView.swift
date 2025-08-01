import SwiftUI

struct SettingsView: View {
    // @EnvironmentObject를 통해 앱의 중앙 ViewModel에 접근합니다.
    @EnvironmentObject var viewModel: PomodoroViewModel
    
    // 메인 로그 윈도우를 열기 위한 환경 변수
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 16) {
            Text("뽀모도로 설정")
              .font(.title2)
              .fontWeight(.bold)

            // --- 타이머 제어 섹션 ---
            VStack {
                Text(viewModel.timeRemainingString)
                  .font(.system(size: 48, weight:.bold, design:.monospaced))
                  .foregroundColor(viewModel.pomodoroState == .focus ? .red : (viewModel.pomodoroState == .shortBreak ? .green : (viewModel.pomodoroState == .longBreak ? .blue : .primary)))
                
                ProgressView(value: viewModel.progress)
                  .progressViewStyle(.linear)
                
                HStack {
                    Button(action: {
                        viewModel.mainButtonTapped()
                    }) {
                        Text(viewModel.mainButtonTitle)
                          .frame(maxWidth:.infinity)
                    }
                  .controlSize(.large)
                    
                    if viewModel.pomodoroState != .idle && viewModel.pomodoroState != .paused {
                        Button(action: {
                            viewModel.skipToNextSession()
                        }) {
                            Image(systemName: "forward.end.fill")
                        }
                      .controlSize(.large)
                      .help("다음 세션으로 건너뛰기")
                    }
                }
            }
          .padding(.bottom, 10)

            Divider()

            // --- 시간 설정 섹션 ---
            // 계획서 섹션 3.2의 요구사항에 따라 Stepper를 사용하여 쉽게 값을 조정하도록 구현.[1]
            // $viewModel.focusDurationInMinutes와 같이 양방향 바인딩을 사용합니다.
            VStack(alignment:.leading, spacing: 12) {
                SettingRow(label: "집중 시간", value: $viewModel.focusDurationInMinutes, unit: "분")
                SettingRow(label: "짧은 휴식", value: $viewModel.shortBreakDurationInMinutes, unit: "분")
                SettingRow(label: "긴 휴식", value: $viewModel.longBreakDurationInMinutes, unit: "분")
                
                HStack {
                    Text("긴 휴식 간격")
                    Spacer()
                    // Int 타입에 대한 Stepper
                    Stepper("\(viewModel.sessionsUntilLongBreak) 세션", value: $viewModel.sessionsUntilLongBreak, in: 2...10)
                }
              .frame(height: 24)
            }
            
            Spacer()
            
            Divider()

            // --- 앱 제어 버튼 ---
            HStack {
                Button("로그 보기") {
                    // 메인 윈도우를 여는 액션
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "log-window")
                }
                
                Button("초기화") {
                    viewModel.resetTimer()
                }
              .help("모든 세션 기록을 지우고 타이머를 초기 상태로 되돌립니다.")
                
                // 계획서 섹션 3.3의 필수 요구사항: 명시적인 종료 버튼.[1]
                Button("종료") {
                    NSApplication.shared.terminate(nil)
                }
            }
          .padding(.top, 8)
        }
      .padding()
      .frame(width: 240, height: 320)
      .onAppear {
            // 앱 시작 시 알림 권한을 요청합니다.
            PomodoroViewModel.requestNotificationPermission()
        }
    }
}

// 재사용 가능한 설정 행(Row) 뷰
struct SettingRow: View {
    let label: String
    @Binding var value: Double
    let unit: String
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Stepper("\(Int(value)) \(unit)", value: $value, in: 1...120, step: 1)
        }
      .frame(height: 24)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
          .environmentObject(PomodoroViewModel())
    }
}
