import Foundation
import Combine
import SwiftUI

enum RewardSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large
    var id: Self { self }
    var title: String {
        switch self {
        case .small: "작은"
        case .medium: "중간"
        case .large: "큰"
        }
    }
}

struct RewardItem: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var size: RewardSize
}

enum RewardListText {
    static let title = "보상 목록"
    static let history = "지난 보상"
    static let choose = "보상 목록과 지난 보상에서 고르기"
    static let add = "더하기"
    static let remove = "지우기"
    static let name = "보상 이름"
    static let newReward = "새 보상"
}

@MainActor
final class RewardListStore: ObservableObject {
    private static let key = "rewardList.v1"
    private let defaults: UserDefaults?
    @Published private(set) var items: [RewardItem]

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        items = defaults?.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([RewardItem].self, from: $0) } ?? Self.examples
    }

    private static var examples: [RewardItem] {
        let groups: [(RewardSize, [String])] = [
            (.small, ["물 한 잔", "음악 한 곡", "짧은 영상 하나"]),
            (.medium, ["산책", "식사", "드라마 한 편"]),
            (.large, ["외식", "취미 시간", "긴 휴식"])
        ]
        return groups.flatMap { size, names in names.map { RewardItem(name: $0, size: size) } }
    }

    func items(in size: RewardSize) -> [RewardItem] { items.filter { $0.size == size } }

    func add(_ name: String, size: RewardSize) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        items.append(RewardItem(name: name.components(separatedBy: .newlines).joined(separator: " "), size: size))
        save()
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].name = name.components(separatedBy: .newlines).joined(separator: " ")
        save()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults?.set(data, forKey: Self.key)
    }
}

struct RewardListSettings: View {
    @ObservedObject var store: RewardListStore

    var body: some View {
        Section(RewardListText.title) {
            ForEach(RewardSize.allCases) { size in
                VStack(alignment: .leading, spacing: 6) {
                    Text(size.title).font(.caption).foregroundStyle(.secondary)
                    ForEach(store.items(in: size)) { item in
                        HStack {
                            TextField(RewardListText.name, text: Binding(
                                get: { store.items.first(where: { $0.id == item.id })?.name ?? "" },
                                set: { store.rename(item.id, to: $0) }
                            ))
                            .textFieldStyle(.roundedBorder)
                            Button { store.remove(item.id) } label: { Image(systemName: "minus.circle") }
                                .help(RewardListText.remove)
                                .accessibilityLabel(RewardListText.remove)
                        }
                    }
                    Button(RewardListText.add) { store.add(RewardListText.newReward, size: size) }
                        .controlSize(.small)
                }
            }
        }
    }
}

/// 설정에서 고친 목록을 열려 있는 팝오버에도 바로 반영합니다.
struct RewardField: View {
    @ObservedObject var store: RewardListStore
    @Binding var text: String
    let suggestions: [String]

    var body: some View {
        NoteField(title: "끝나면 받을 보상", text: $text, suggestions: suggestions,
                  help: RewardListText.choose, rewards: store.items)
    }
}
