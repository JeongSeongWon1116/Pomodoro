import SwiftUI

struct StatusBarView: View {
    // @EnvironmentObject를 통해 앱의 중앙 ViewModel에 접근합니다.
    @EnvironmentObject var viewModel: PomodoroViewModel

    var body: some View {
        // HStack을 사용하여 아이콘과 텍스트/진행률 뷰를 정렬합니다.
        HStack(spacing: 4) {
            // 현재 세션 상태에 따라 다른 아이콘을 표시합니다.
            Image(systemName: iconForState(viewModel.pomodoroState))
              .font(.headline)
              .foregroundColor(colorForState(viewModel.pomodoroState))

            // 계획서 섹션 2.3.2의 고급 UI 구현: ZStack과 마스킹을 활용.[1]
            ZStack {
                // 배경 텍스트 (채워지지 않은 부분)
                Text(viewModel.timeRemainingString)
                  .foregroundColor(.gray.opacity(0.8))

                // 전경 텍스트 (채워진 부분)
                Text(viewModel.timeRemainingString)
                  .foregroundColor(colorForState(viewModel.pomodoroState))
                  .mask(
                        // 왼쪽에서부터 진행률에 따라 채워지는 마스크
                        GeometryReader { geometry in
                            HStack {
                                Rectangle()
                                  .frame(width: geometry.size.width * viewModel.progress)
                                Spacer(minLength: 0)
                            }
                        }
                    )
            }
            // 고정 폭 폰트를 사용하여 시간이 바뀔 때 텍스트 너비가 흔들리지 않도록 합니다.
          .font(.system(.body, design:.monospaced).bold())
          .frame(width: 50, alignment:.trailing)
        }
      .padding(.horizontal, 6)
    }
    
    // 현재 상태에 맞는 SF Symbol 아이콘 이름을 반환하는 헬퍼 함수
    private func iconForState(_ state: PomodoroViewModel.PomodoroState) -> String {
        switch state {
        case.focus:
            return "brain.head.profile"
        case.shortBreak:
            return "cup.and.saucer"
        case.longBreak:
            return "bed.double"
        case.paused:
            return "pause"
        case.idle:
            return "hourglass"
        }
    }
    
    // 현재 상태에 맞는 색상을 반환하는 헬퍼 함수
    private func colorForState(_ state: PomodoroViewModel.PomodoroState) -> Color {
        switch state {
        case.focus:
            return.red
        case.shortBreak:
            return.green
        case.longBreak:
            return.blue
        case.paused,.idle:
            return.primary
        }
    }
}

struct StatusBarView_Previews: PreviewProvider {
    static var previews: some View {
        // 미리보기용으로 다양한 상태를 테스트할 수 있습니다.
        let viewModel = PomodoroViewModel()
        viewModel.pomodoroState = .focus
        viewModel.timeRemaining = 12 * 60 + 34
        viewModel.progress = (12 * 60 + 34) / (25 * 60)
        
        return StatusBarView()
          .environmentObject(viewModel)
          .padding()
    }
}
