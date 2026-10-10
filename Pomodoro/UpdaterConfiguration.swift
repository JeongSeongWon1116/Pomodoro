// File: UpdaterConfiguration.swift
// Description: 이 빌드가 자동 업데이트를 쓸 수 있는지 Info.plist 값으로 판단합니다.
// 업데이트 주소(SUFeedURL)와 서명 공개 키(SUPublicEDKey)는 프로젝트의 빌드 설정에서 들어옵니다.

import Foundation

struct UpdaterConfiguration: Equatable {
    /// 업데이트 목록(appcast)의 주소. 쓸 수 없으면 nil.
    let feedURL: URL?
    /// 쓸 수 없을 때 그 이유 (설정 창에 보여 줍니다). 쓸 수 있으면 nil.
    let disabledReason: String?

    var isUsable: Bool { disabledReason == nil }

    init(info: [String: Any]) {
        let feed = Self.text(info["SUFeedURL"])
        let key = Self.text(info["SUPublicEDKey"])
        let url = Self.webURL(feed)
        feedURL = url

        if url == nil {
            disabledReason = "업데이트 주소가 없는 빌드입니다"
        } else if Data(base64Encoded: key)?.count != 32 {
            // 키가 없으면 받은 업데이트가 진짜인지 확인할 수 없으므로 아예 켜지 않습니다.
            disabledReason = "업데이트 서명 키가 없는 빌드입니다"
        } else {
            disabledReason = nil
        }
    }

    private static func text(_ value: Any?) -> String {
        ((value as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// https 주소만 받습니다. 채워지지 않은 빌드 설정 자리표시("$(...)")는 주소가 아닙니다.
    /// 암호화하지 않은 http 는 중간에서 업데이트 목록을 바꾸거나 막을 수 있으므로, 이 컴퓨터 자신을 가리킬 때만
    /// 받습니다(scripts/update-e2e.sh 의 시험용 빌드).
    private static func webURL(_ text: String) -> URL? {
        guard !text.contains("$("),
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(), !host.isEmpty
        else { return nil }
        switch scheme {
        case "https": return url
        case "http": return ["localhost", "127.0.0.1", "::1"].contains(host) ? url : nil
        default: return nil
        }
    }
}
