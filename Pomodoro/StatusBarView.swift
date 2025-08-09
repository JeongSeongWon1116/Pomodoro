// File: StatusBarView.swift
// Description: 메뉴 막대에 표시될 커스텀 UI입니다.

import SwiftUI

struct StatusBarView: View {
    let emoji: String

    var body: some View {
        Text(emoji)
            .font(.title)
            .padding(.horizontal, 4)
    }
}
