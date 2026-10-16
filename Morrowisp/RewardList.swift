import Foundation
import Combine
import SwiftUI

enum RewardSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large
    var id: Self { self }
    var title: String { localizedTitle() }

    func localizedTitle(locale: Locale = .current) -> String {
        switch self {
        case .small: String(localized: "Small", bundle: AppLocalization.bundle(for: locale), locale: locale)
        case .medium: String(localized: "Medium", bundle: AppLocalization.bundle(for: locale), locale: locale)
        case .large: String(localized: "Large", bundle: AppLocalization.bundle(for: locale), locale: locale)
        }
    }
}

struct RewardItem: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var size: RewardSize
}

struct RewardListText {
    let locale: Locale

    init(locale: Locale = .current) { self.locale = locale }
    var title: String { String(localized: "Reward list", bundle: AppLocalization.bundle(for: locale), locale: locale) }
    var history: String { String(localized: "Past rewards", bundle: AppLocalization.bundle(for: locale), locale: locale) }
    var choose: String { String(localized: "Choose from your reward list and past rewards", bundle: AppLocalization.bundle(for: locale), locale: locale) }
    var add: String { String(localized: "Add", bundle: AppLocalization.bundle(for: locale), locale: locale) }
    var remove: String { String(localized: "Remove", bundle: AppLocalization.bundle(for: locale), locale: locale) }
    var name: String { String(localized: "Reward name", bundle: AppLocalization.bundle(for: locale), locale: locale) }
    var newReward: String { String(localized: "New reward", bundle: AppLocalization.bundle(for: locale), locale: locale) }
}

/// 메뉴 표시와 구분선도 실제로 남은 항목으로 결정하는 순수 구성 함수입니다.
struct NoteFieldMenu {
    struct Group: Identifiable {
        let size: RewardSize
        let items: [RewardItem]
        var id: RewardSize { size }
    }

    let groups: [Group]
    let suggestions: [String]
    var isVisible: Bool { !groups.isEmpty || !suggestions.isEmpty }
    var showsHistoryDivider: Bool { !groups.isEmpty && !suggestions.isEmpty }

    static func make(rewards: [RewardItem], suggestions: [String]) -> NoteFieldMenu {
        let validRewards = rewards.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let groups: [Group] = RewardSize.allCases.compactMap { size in
            let items = validRewards.filter { $0.size == size }
            return items.isEmpty ? nil : Group(size: size, items: items)
        }
        return NoteFieldMenu(groups: groups, suggestions: suggestions)
    }
}

@MainActor
final class RewardListStore: ObservableObject {
    private static let key = "rewardList.v1"
    private let defaults: UserDefaults?
    @Published private(set) var items: [RewardItem]

    init(defaults: UserDefaults?, locale: Locale = .current) {
        self.defaults = defaults
        items = defaults?.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([RewardItem].self, from: $0) } ?? Self.examples(locale: locale)
    }

    private static func examples(locale: Locale) -> [RewardItem] {
        let groups: [(RewardSize, [String])] = [
            (.small, [
                String(localized: "A glass of water", bundle: AppLocalization.bundle(for: locale), locale: locale),
                String(localized: "A song", bundle: AppLocalization.bundle(for: locale), locale: locale),
                String(localized: "A short video", bundle: AppLocalization.bundle(for: locale), locale: locale)
            ]),
            (.medium, [
                String(localized: "A walk", bundle: AppLocalization.bundle(for: locale), locale: locale),
                String(localized: "A meal", bundle: AppLocalization.bundle(for: locale), locale: locale),
                String(localized: "An episode of a show", bundle: AppLocalization.bundle(for: locale), locale: locale)
            ]),
            (.large, [
                String(localized: "A meal out", bundle: AppLocalization.bundle(for: locale), locale: locale),
                String(localized: "Time for a hobby", bundle: AppLocalization.bundle(for: locale), locale: locale),
                String(localized: "Long break", bundle: AppLocalization.bundle(for: locale), locale: locale)
            ])
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
    @Environment(\.locale) private var locale
    @ObservedObject var store: RewardListStore

    var body: some View {
        Section(RewardListText(locale: locale).title) {
            ForEach(RewardSize.allCases) { size in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(size.localizedTitle(locale: locale)).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button { store.add(RewardListText(locale: locale).newReward, size: size) } label: {
                            Image(systemName: "plus")
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderless)
                        .help(RewardListText(locale: locale).add)
                        .accessibilityLabel(Text(verbatim: "\(size.localizedTitle(locale: locale)): \(RewardListText(locale: locale).add)"))
                    }
                    ForEach(store.items(in: size)) { item in
                        HStack {
                            TextField(RewardListText(locale: locale).name, text: Binding(
                                get: { store.items.first(where: { $0.id == item.id })?.name ?? "" },
                                set: { store.rename(item.id, to: $0) }
                            ))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Button { store.remove(item.id) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .fixedSize()
                                .help(RewardListText(locale: locale).remove)
                                .accessibilityLabel(RewardListText(locale: locale).remove)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// 설정에서 고친 목록을 열려 있는 팝오버에도 바로 반영합니다.
struct RewardField: View {
    @Environment(\.locale) private var locale
    @ObservedObject var store: RewardListStore
    @Binding var text: String
    let suggestions: [String]

    var body: some View {
        NoteField(title: String(localized: "A reward for when you finish", bundle: AppLocalization.bundle(for: locale), locale: locale), text: $text, suggestions: suggestions,
                  help: RewardListText(locale: locale).choose, rewards: store.items)
    }
}
