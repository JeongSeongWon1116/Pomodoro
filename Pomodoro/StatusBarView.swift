// File: StatusBarView.swift
// Description: 메뉴 막대에 표시될 커스텀 UI입니다.

import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var viewModel: PomodoroViewModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: viewModel.currentState.symbolName)
                .imageScale(.medium)

            if viewModel.timerState == .running || viewModel.timerState == .paused {
                BatteryProgressBar(progress: viewModel.progress, color: viewModel.currentState.color)
            }
        }
        .padding(.horizontal, 6)
        .fixedSize()
    }
}

struct BatteryProgressBar: View {
    var progress: Double
    var color: Color

    var body: some View {
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.primary.opacity(0.6), lineWidth: 1.5)

                GeometryReader { geometry in
                    let maxFillWidth = geometry.size.width - 3
                    let fillWidth = max(0, maxFillWidth * CGFloat(progress))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color)
                        .frame(width: fillWidth)
                        .padding(1.5)
                }
            }
            .frame(width: 28, height: 13)

            // Battery terminal nub
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.primary.opacity(0.6))
                .frame(width: 2, height: 6)
        }
    }
}
