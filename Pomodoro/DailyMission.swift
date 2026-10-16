// 날짜별 미션은 작은 JSON 값으로 둡니다. 기존 SwiftData 기록 스키마는 바꾸지 않습니다.
import Foundation
import Combine
import SwiftUI

struct DailyMission: Codable, Equatable {
    var text = ""
    var done = false
    var doneAt: Date?
}

enum DailyMissionText {
    static let title = "오늘의 메인 미션"
    static let placeholder = "오늘 끝내고 싶은 한 가지"
    static let encouragement = "이것만 끝내면 오늘은 충분해요"
    static let done = "끝냄"
    static let undo = "끝냄 표시 지우기"
}

@MainActor
final class DailyMissionStore: ObservableObject {
    private static let key = "dailyMissions.v1"
    private let defaults: UserDefaults?
    @Published private(set) var missions: [String: DailyMission]

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        missions = defaults?.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([String: DailyMission].self, from: $0) } ?? [:]
    }

    nonisolated static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        // 날짜 키는 그레고리력 yyyy-MM-dd, 날짜 경계는 사용자의 로컬 시간대입니다.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func mission(for date: Date, calendar: Calendar = .current) -> DailyMission {
        missions[Self.dayKey(for: date, calendar: calendar)] ?? DailyMission()
    }

    func setText(_ text: String, for date: Date, calendar: Calendar = .current) {
        let key = Self.dayKey(for: date, calendar: calendar)
        var mission = missions[key] ?? DailyMission()
        // 붙여 넣은 여러 줄도 하나의 칸으로 남깁니다. 입력 중 공백은 보존합니다.
        mission.text = text.components(separatedBy: .newlines).joined(separator: " ")
        if mission.text.trimmingCharacters(in: .whitespaces).isEmpty { mission = DailyMission() }
        missions[key] = mission
        save()
    }

    func toggleDone(for date: Date, calendar: Calendar = .current, now: Date = Date()) {
        let key = Self.dayKey(for: date, calendar: calendar)
        guard var mission = missions[key], !mission.text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        mission.done.toggle()
        mission.doneAt = mission.done ? now : nil
        missions[key] = mission
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(missions) else { return }
        defaults?.set(data, forKey: Self.key)
    }
}

struct DailyMissionView: View {
    @ObservedObject var store: DailyMissionStore

    var body: some View {
        // 타이머가 쉬고 있어도, 열린 팝오버의 날짜와 편집 칸은 자정을 지나면 바뀝니다.
        TimelineView(.periodic(from: Calendar.current.startOfDay(for: .now), by: 60)) { context in
            let day = context.date
            let mission = store.mission(for: day)
            VStack(alignment: .leading, spacing: 4) {
                Text(DailyMissionText.title).font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField(DailyMissionText.placeholder, text: Binding(
                        get: { store.mission(for: day).text },
                        set: {
                            store.setText($0, for: day)
                            ObsidianExporter.shared.updateMission(store.mission(for: day), for: day)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .id(DailyMissionStore.dayKey(for: day))
                    Button {
                        store.toggleDone(for: day)
                        ObsidianExporter.shared.updateMission(store.mission(for: day), for: day)
                    } label: {
                        if mission.done {
                            Image(systemName: "checkmark")
                        } else {
                            Text(DailyMissionText.done)
                        }
                    }
                    .accessibilityLabel(mission.done ? DailyMissionText.undo : DailyMissionText.done)
                    .disabled(mission.text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !mission.text.isEmpty {
                    Text(DailyMissionText.encouragement)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
