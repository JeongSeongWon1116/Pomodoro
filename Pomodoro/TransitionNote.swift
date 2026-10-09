// File: TransitionNote.swift
// Description: 집중 세션에 적어 둔 할 일·보상·다음 시작점과 연장 횟수입니다.
// 집중 기록(FocusLogEntry)의 저장소를 바꾸지 않도록 별도 저장소에 두고, 세션 id 로 잇습니다.
// (기록 저장소의 모양이 바뀌면 예전 빌드가 그 저장소를 열지 못합니다.)

import Foundation
import SwiftData

/// 한 집중에 적은 글과 연장 횟수. 저장소 없이도 쓸 수 있는 값입니다(Obsidian 기록, 비었는지 판단).
struct TransitionDetails: Equatable {
    var task = ""
    var reward = ""
    var nextStartingPoint = ""
    var extensionCount = 0

    /// 적은 글도 연장도 없으면 남길 것이 없습니다.
    var isEmpty: Bool {
        extensionCount == 0 && [task, reward, nextStartingPoint].allSatisfy {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

@Model
final class TransitionNote {
    var sessionID: UUID // FocusLogEntry.id
    var task: String
    var reward: String
    var nextStartingPoint: String
    var extensionCount: Int
    var createdAt: Date

    init(sessionID: UUID, details: TransitionDetails, createdAt: Date = Date()) {
        self.sessionID = sessionID
        self.task = details.task
        self.reward = details.reward
        self.nextStartingPoint = details.nextStartingPoint
        self.extensionCount = details.extensionCount
        self.createdAt = createdAt
    }

    /// 집중 기록을 지울 때 딸린 메모도 함께 지웁니다. sessionIDs 가 nil 이면 전부 지웁니다.
    static func delete(forSessions sessionIDs: [UUID]?, in context: ModelContext?) {
        guard let context else { return }
        if let sessionIDs {
            try? context.delete(model: TransitionNote.self, where: #Predicate { sessionIDs.contains($0.sessionID) })
        } else {
            try? context.delete(model: TransitionNote.self)
        }
        try? context.save()
    }
}
