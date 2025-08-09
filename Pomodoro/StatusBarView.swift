// File: StatusBarView.swift
// Description: 메뉴 막대에 표시될 커스텀 UI입니다.

import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var viewModel: PomodoroViewModel

    var body: some View {
        HStack(spacing: 5) {
            Text(viewModel.currentState.emoji)
                .font(.system(size: 18))

            BatteryProgressBar(progress: viewModel.progress, color: viewModel.currentState.color)
        }
        .padding(.horizontal, 8)
        .fixedSize()
    }
}

struct BatteryProgressBar: View {
    var progress: Double
    var color: Color

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3.5)
                .stroke(Color.primary.opacity(0.8), lineWidth: 1.5)

            GeometryReader { geometry in
                let fillWidth = (geometry.size.width - 3) * CGFloat(progress)
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: fillWidth)
                    .padding(1.5)
            }
        }
        .frame(width: 35, height: 14)
    }
}
