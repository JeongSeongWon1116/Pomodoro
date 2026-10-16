// 날짜별 미션은 작은 JSON 값으로 둡니다. 기존 SwiftData 기록 스키마는 바꾸지 않습니다.
import Foundation
import Combine
import SwiftUI

struct DailyMission: Codable, Equatable {
    var text = ""
    var done = false
    var doneAt: Date?
}

struct DailyMissionText {
    let locale: Locale

    init(locale: Locale = .current) { self.locale = locale }
    var title: String { String(localized: "Today's main mission", bundle: AppLocalization.bundle(for: locale), locale: locale) }
    var placeholder: String { String(localized: "One thing you would like to finish today", bundle: AppLocalization.bundle(for: locale), locale: locale) }
    var encouragement: String { String(localized: "Finishing this is enough for today", bundle: AppLocalization.bundle(for: locale), locale: locale) }
    var done: String { String(localized: "Done", bundle: AppLocalization.bundle(for: locale), locale: locale) }
    var undo: String { String(localized: "Mark as not done", bundle: AppLocalization.bundle(for: locale), locale: locale) }
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

/// 입력은 바로 로컬에 저장하고, 외부 쓰기는 편집을 마칠 때 날짜별 최종 변경만 전달합니다.
@MainActor
final class DailyMissionEditor: ObservableObject {
    private struct Change {
        let original: DailyMission
        let latest: DailyMission
        let date: Date
    }

    private var changes: [String: Change] = [:]
    private let write: (DailyMission, Date) -> Void

    init(write: @escaping (DailyMission, Date) -> Void) {
        self.write = write
    }

    func setText(_ text: String, in store: DailyMissionStore, for date: Date) {
        let previous = store.mission(for: date)
        store.setText(text, for: date)
        recordChange(from: previous, to: store.mission(for: date), for: date)
    }

    func toggleDone(in store: DailyMissionStore, for date: Date) {
        let previous = store.mission(for: date)
        store.toggleDone(for: date)
        recordChange(from: previous, to: store.mission(for: date), for: date)
    }

    private func recordChange(from previous: DailyMission, to latest: DailyMission, for date: Date) {
        guard previous != latest else { return }
        let key = DailyMissionStore.dayKey(for: date)
        let original = changes[key]?.original ?? previous
        if latest == original {
            changes.removeValue(forKey: key)
        } else {
            changes[key] = Change(original: original, latest: latest, date: date)
        }
    }

    func flush() {
        let pending = changes.sorted { $0.key < $1.key }.map(\.value)
        changes.removeAll()
        for change in pending { write(change.latest, change.date) }
    }
}

struct DailyMissionView: View {
    @ObservedObject var store: DailyMissionStore
    @StateObject private var editor = DailyMissionEditor { mission, date in
        ObsidianExporter.shared.updateMission(mission, for: date)
    }
    @FocusState private var isEditing: Bool

    var body: some View {
        // 타이머가 쉬고 있어도, 열린 팝오버의 날짜와 편집 칸은 자정을 지나면 바뀝니다.
        TimelineView(.periodic(from: Calendar.current.startOfDay(for: .now), by: 60)) { context in
            let day = context.date
            let mission = store.mission(for: day)
            VStack(alignment: .leading, spacing: 4) {
                Text(DailyMissionText().title).font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField(DailyMissionText().placeholder, text: Binding(
                        get: { store.mission(for: day).text },
                        set: {
                            editor.setText($0, in: store, for: day)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .focused($isEditing)
                    .onSubmit { editor.flush() }
                    .id(DailyMissionStore.dayKey(for: day))
                    Button {
                        editor.toggleDone(in: store, for: day)
                        editor.flush()
                    } label: {
                        if mission.done {
                            Image(systemName: "checkmark")
                        } else {
                            Text(DailyMissionText().done)
                        }
                    }
                    .accessibilityLabel(mission.done ? DailyMissionText().undo : DailyMissionText().done)
                    .disabled(mission.text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !mission.text.isEmpty {
                    Text(DailyMissionText().encouragement)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: isEditing) { _, editing in
            if !editing { editor.flush() }
        }
        .onDisappear { editor.flush() }
    }
}
