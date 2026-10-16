// File: ShortcutRunner.swift
// Description: 단축어 앱의 단축어를 이름으로 실행합니다.
// 집중이 시작하고 끝날 때 방해금지 모드를 켜고 끄는 식으로 쓸 수 있습니다.

import AppKit

/// 이름으로 단축어를 실행하는 것. (테스트에서는 가짜로 바꿔 끼웁니다.)
@MainActor
protocol ShortcutRunning {
    /// completion 은 실행 요청이 단축어 앱 쪽으로 넘어간 뒤(실패했어도) 메인에서 한 번 불립니다.
    /// 단축어가 끝났다는 뜻은 아닙니다.
    func run(named name: String, completion: (() -> Void)?)
}

extension ShortcutRunning {
    func run(named name: String) { run(named: name, completion: nil) }
}

/// `shortcuts://run-shortcut?name=…` 주소를 열어 단축어를 실행합니다.
/// 샌드박스 앱에서도 권한(entitlement)을 더하지 않고 쓸 수 있는 방법입니다.
struct URLShortcutRunner: ShortcutRunning {

    // 기본 인자로 쓸 수 있도록 어디서든 만들 수 있게 합니다. (실행은 메인 액터에서 합니다.)
    nonisolated init() {}

    func run(named name: String, completion: (() -> Void)?) {
        // 단위 테스트가 실제 단축어를 실행하지 않도록 합니다.
        guard !DataController.isRunningTests, let url = Self.url(forShortcutNamed: name) else {
            completion?()
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        // 주소를 여는 것만으로 단축어 앱을 앞으로 가져오지는 않게 합니다.
        // (단축어 앱이 스스로 창을 띄우는 것까지 막지는 못합니다.)
        configuration.activates = false
        NSWorkspace.shared.open(url, configuration: configuration) { _, error in
            if let error { print("단축어 실행 실패(\(name)): \(error)") }
            if let completion {
                DispatchQueue.main.async { completion() }
            }
        }
    }

    /// 단축어를 실행하는 주소. 이름이 비어 있으면 nil.
    /// 이름에 든 `&`, `+`, `#` 같은 글자가 주소의 일부로 읽히지 않도록 글자·숫자 외에는 모두 바꿔 넣습니다.
    /// 한글은 자모가 풀린 형태(NFD)로 붙여 넣어도 단축어 앱의 이름과 맞도록 합친 형태(NFC)로 맞춥니다.
    nonisolated static func url(forShortcutNamed name: String) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard !trimmed.isEmpty else { return nil }
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: unreserved) else { return nil }
        return URL(string: "shortcuts://run-shortcut?name=\(encoded)")
    }
}
