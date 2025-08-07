// File: DataController.swift
// Description: SwiftData ModelContainer를 관리하는 싱글턴 클래스입니다.
// 앱의 모든 부분에서 동일한 데이터베이스 컨텍스트에 안전하게 접근할 수 있도록 보장합니다.

import Foundation
import SwiftData

class DataController {
    static let shared = DataController()

    lazy var container: ModelContainer = {
        do {
            // FocusLogEntry 모델에 대한 컨테이너를 생성합니다.
            let container = try ModelContainer(for: FocusLogEntry.self)
            return container
        } catch {
            fatalError("SwiftData 컨테이너 생성에 실패했습니다: \(error.localizedDescription)")
        }
    }()

    private init() {}
}
