// File: PopoverView.swift
// Description: 메뉴 바 아이콘 클릭 시 표시되는 팝오버 UI입니다.
// 타이머 제어에 집중하고, 상세 설정은 별도의 설정 창에서 합니다.

import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var viewModel: PomodoroViewModel
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var updates = UpdateController.shared
    @Environment(\.openWindow) private var openWindow

    private var isAwaitingChoice: Bool { viewModel.timerState == .awaitingChoice }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: isAwaitingChoice ? "bell.badge" : viewModel.currentState.symbolName)
                    .foregroundStyle(viewModel.currentState.color)
                Text(isAwaitingChoice ? "\(viewModel.currentState.description) 끝" : viewModel.currentState.description)
                    .fontWeight(.semibold)
            }
            .font(.headline)

            Text(viewModel.timeRemainingString)
                .font(.system(size: 44, weight: .light, design: .rounded))
                .monospacedDigit()

            CycleDotsView(
                completed: viewModel.focusSessionsInCurrentCycle,
                total: settings.longBreakInterval
            )

            if settings.transitionManagementEnabled || isAwaitingChoice {
                transitionNotes
            }

            Button(action: primaryAction) {
                Text(buttonTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)

            if isAwaitingChoice {
                Button("\(Int(PomodoroViewModel.focusExtension / 60))분 더 집중") { viewModel.extendFocus() }
                    .frame(maxWidth: .infinity)
            }

            HStack {
                Button("건너뛰기") { viewModel.skipToNextSession() }
                    .disabled(viewModel.timerState == .idle || isAwaitingChoice)
                Spacer()
                Button("초기화") { viewModel.resetToIdle() }
                    .disabled(viewModel.timerState == .idle && viewModel.currentState == .idle)
            }
            .padding(.horizontal, 4)

            Divider()

            HStack {
                Button("로그 보기") {
                    viewModel.closePopover()
                    openWindow(id: "log-window")
                }
                Spacer()
                Button {
                    viewModel.closePopover()
                    openWindow(id: "settings-window")
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("설정")
                Spacer()
                Button("종료") {
                    // 진행 중인 세션은 종료 과정(AppDelegate.applicationShouldTerminate)에서 기록합니다.
                    NSApplication.shared.terminate(nil)
                }
            }

            // 새 버전이 있을 때만 보이는 한 줄. 메뉴 막대 아이콘의 점과 짝입니다.
            if let version = updates.indicatedVersion {
                UpdateRow(
                    version: version,
                    downloaded: updates.pendingVersion != nil,
                    installing: updates.installInProgress
                ) {
                    viewModel.closePopover()
                    updates.performIndicatedUpdate()
                }
            }
        }
        .padding()
        // 높이는 내용(할 일·보상 칸, 선택 화면)에 맞춰 달라집니다.
        .frame(width: 260)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 할 일·보상·다음 시작점. 집중 전과 집중 중에는 적는 칸, 집중이 끝나면 보상과 다음 시작점 칸, 휴식 중에는 읽기만.
    @ViewBuilder
    private var transitionNotes: some View {
        let reward = viewModel.focusReward.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: 6) {
            if isAwaitingChoice {
                if !reward.isEmpty { NoteLine(label: "보상", text: reward) }
                TextField("다음에 이어서 시작할 자리", text: $viewModel.nextStartingPoint)
                    .textFieldStyle(.roundedBorder)
            } else if viewModel.currentState == .idle || viewModel.currentState == .focus {
                if !viewModel.resumeHint.isEmpty { NoteLine(label: "이어서", text: viewModel.resumeHint) }
                NoteField(title: "할 일", text: $viewModel.focusTask,
                          suggestions: viewModel.taskSuggestions, help: "지난 할 일에서 고르기")
                NoteField(title: "끝나면 받을 보상", text: $viewModel.focusReward,
                          suggestions: viewModel.rewardSuggestions, help: "지난 보상에서 고르기")
            } else {
                if !reward.isEmpty { NoteLine(label: "보상", text: reward) }
                if !viewModel.resumeHint.isEmpty { NoteLine(label: "다음 시작점", text: viewModel.resumeHint) }
            }
        }
    }

    private func primaryAction() {
        switch viewModel.timerState {
        case .idle: viewModel.startFocusSession()
        case .paused: viewModel.resumeTimer()
        case .running: viewModel.pauseTimer()
        case .awaitingChoice: viewModel.startBreakAfterFocus()
        }
    }

    private var buttonTitle: String {
        switch viewModel.timerState {
        case .running: "일시정지"
        case .paused: "재개"
        case .idle: viewModel.currentState == .idle ? "시작" : "\(viewModel.currentState.description) 시작"
        case .awaitingChoice: "휴식 시작"
        }
    }

}

/// 팝오버 맨 아래의 "새 버전" 줄. 상태를 값으로 받아, 업데이터 없이도 그려 볼 수 있습니다.
struct UpdateRow: View {
    let version: String
    /// 받아 두었는지. 받아 두었으면 누르자마자 설치하고 앱이 다시 켜집니다. 아니면 Sparkle 의 안내 창이 뜹니다.
    let downloaded: Bool
    /// 설치를 시작해 앱이 꺼지기를 기다리는 중인지
    let installing: Bool
    let update: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            UpdateDot()
            Text("새 버전 \(version)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(Self.buttonTitle(installing: installing), action: update)
                .controlSize(.small)
                .disabled(installing)
                .help(Self.help(downloaded: downloaded))
        }
    }

    nonisolated static func buttonTitle(installing: Bool) -> String {
        installing ? "설치하는 중…" : "업데이트"
    }

    /// 누르면 무슨 일이 일어나는지. 받아 둔 것은 곧바로 앱을 껐다 켜므로 그렇게 적습니다.
    nonisolated static func help(downloaded: Bool) -> String {
        downloaded ? "설치하고 앱을 다시 켭니다" : "새 버전 안내 창을 엽니다"
    }
}

/// 글을 적는 칸. 지난 집중에 적었던 글이 있으면 칸 옆의 단추로 골라 넣을 수 있습니다.
struct NoteField: View {
    let title: String
    @Binding var text: String
    let suggestions: [String]
    let help: String
    @FocusState private var isEditing: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isEditing)
            if !suggestions.isEmpty {
                Menu {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(Self.menuTitle(suggestion)) { pick(suggestion) }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(help)
                .accessibilityLabel(help)
            }
        }
    }

    private func pick(_ suggestion: String) {
        // 이 칸을 편집하던 중이면 편집을 끝내고(다른 칸과 다른 창은 건드리지 않습니다) 고른 글을 넣습니다.
        isEditing = false
        text = suggestion
        // 편집을 끝내는 처리나 입력기의 확정이 뒤늦게 돌아 적던 글이 다시 들어오면, 고른 글을 한 번 더 넣습니다.
        let text = $text
        DispatchQueue.main.async {
            if text.wrappedValue != suggestion { text.wrappedValue = suggestion }
        }
    }

    /// 메뉴에는 한 줄로, 길면 줄여서 보여 줍니다 (고르면 원래 글이 그대로 들어갑니다).
    nonisolated static func menuTitle(_ text: String, limit: Int = 30) -> String {
        let oneLine = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return oneLine.count > limit ? oneLine.prefix(limit) + "…" : oneLine
    }
}

/// "보상: 커피" 처럼 적어 둔 글을 한두 줄로 보여 줍니다.
struct NoteLine: View {
    let label: String
    let text: String

    var body: some View {
        Text("\(label): \(text)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 긴 휴식까지 남은 집중 사이클을 점으로 표시합니다.
struct CycleDotsView: View {
    let completed: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(1, total), id: \.self) { index in
                Circle()
                    .fill(index < completed ? PomodoroState.focus.color : Color.primary.opacity(0.15))
                    .frame(width: 8, height: 8)
            }
        }
        .help("긴 휴식까지의 집중 사이클")
    }
}
