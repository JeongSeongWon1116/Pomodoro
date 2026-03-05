// File: FocusLogEntry.swift
// Description: SwiftData가 관리하는 데이터 모델입니다.

import Foundation
import SwiftData
import SwiftUI

@Model
final class FocusLogEntry {
    var id: UUID
    var startTime: Date
    var duration: TimeInterval
    var sessionType: PomodoroState

    init(id: UUID = UUID(), startTime: Date, duration: TimeInterval, sessionType: PomodoroState) {
        self.id = id
        self.startTime = startTime
        self.duration = duration
        self.sessionType = sessionType
    }
}

extension PomodoroState {
    var color: Color {
        switch self {
        case .focus: .blue
        case .shortBreak: .green
        case .longBreak: .purple
        case .idle: .gray
        }
    }

    var symbolName: String {
        switch self {
        case .idle: "hourglass"
        case .focus: "timer"
        case .shortBreak: "cup.and.saucer"
        case .longBreak: "sparkles"
        }
    }
}
