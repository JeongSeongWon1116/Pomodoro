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

    /// 적은 글을 이름표와 함께 차례로 냅니다 (기록 창의 줄). 비어 있는 것은 빠집니다.
    var labeledLines: [(label: String, text: String)] {
        let trim = { (text: String) in text.trimmingCharacters(in: .whitespacesAndNewlines) }
        var lines = [("할 일", trim(task)), ("보상", trim(reward)), ("다음 시작점", trim(nextStartingPoint))]
            .filter { !$0.1.isEmpty }
            .map { (label: $0.0, text: $0.1) }
        if extensionCount > 0 { lines.append((label: "연장", text: "\(extensionCount)회")) }
        return lines
    }

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

    /// 세션 id → 그 세션에 적은 글. 기록 창이 줄마다 보여 주는 데 씁니다. 적은 글이 없는 세션은 들어 있지 않습니다.
    static func details(forSessions sessionIDs: [UUID], in context: ModelContext?) -> [UUID: TransitionDetails] {
        guard let context, !sessionIDs.isEmpty else { return [:] }
        // 세션마다 메모는 하나만 생기지만, 둘이 있어도 가장 나중 것을 쓰도록 차례를 정해 둡니다.
        let descriptor = FetchDescriptor<TransitionNote>(
            predicate: #Predicate { sessionIDs.contains($0.sessionID) },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let notes = (try? context.fetch(descriptor)) ?? []
        return Dictionary(notes.map { ($0.sessionID, $0.details) }, uniquingKeysWith: { first, _ in first })
    }

    /// 가장 최근에 적은 메모부터 limit 개.
    static func latest(_ limit: Int, in context: ModelContext?) -> [TransitionNote] {
        guard let context, limit > 0 else { return [] }
        var descriptor = FetchDescriptor<TransitionNote>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    var details: TransitionDetails {
        TransitionDetails(task: task, reward: reward, nextStartingPoint: nextStartingPoint, extensionCount: extensionCount)
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

/// 지난 메모에서 다시 쓸 글을 고릅니다 (팝오버의 할 일·보상 칸 옆 "지난 것에서 고르기").
enum NoteSuggestions {
    /// 받은 차례대로(최근 것부터 주면 최근 것부터), 같은 글은 한 번만, limit 개까지 고릅니다.
    /// 앞뒤 공백과 대소문자만 다른 글은 같은 글로 보고, 빈 글과 지금 칸에 적혀 있는 글(current)은 뺍니다.
    static func recent(_ values: [String], excluding current: String = "", limit: Int = 5) -> [String] {
        guard limit > 0 else { return [] }
        let key = { (text: String) in text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        var seen: Set<String> = ["", key(current)]
        var picked: [String] = []
        for value in values where seen.insert(key(value)).inserted {
            picked.append(value.trimmingCharacters(in: .whitespacesAndNewlines))
            if picked.count == limit { break }
        }
        return picked
    }
}
