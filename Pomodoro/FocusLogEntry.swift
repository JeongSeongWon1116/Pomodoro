import Foundation
import SwiftData

// 섹션 6.1.1의 계획에 따라 @Model 매크로를 사용하여 SwiftData 모델 클래스를 정의합니다.[1]
// 이 매크로는 Swift 컴파일러에게 이 클래스가 영속적으로 관리되어야 함을 알리고,
// 필요한 모든 백엔드 로직을 자동으로 생성합니다.
@Model
final class FocusLogEntry {
    
    // 각 집중 세션의 시작 시간을 저장합니다.
    var startTime: Date
    
    // 각 집중 세션의 지속 시간을 초 단위로 저장합니다.
    // TimeInterval은 Double의 타입 별칭(typealias)입니다.
    var duration: TimeInterval
    
    init(startTime: Date, duration: TimeInterval) {
        self.startTime = startTime
        self.duration = duration
    }
}
