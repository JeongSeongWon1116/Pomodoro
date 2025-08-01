import SwiftUI
import SwiftData

@main
struct PomodoroApp: App {
    // 섹션 1.2.1의 결정에 따라 @StateObject를 사용하여 PomodoroViewModel의 인스턴스를 생성합니다.
    // 이 뷰모델은 특정 뷰가 아닌 앱 자체의 생명주기에 귀속되어, 앱이 실행되는 동안 단 하나의 인스턴스만
    // 안정적으로 유지됩니다. 이는 '단일 진실 공급원(Single Source of Truth)' 원칙의 핵심 구현입니다.[1]
    @StateObject private var viewModel = PomodoroViewModel()

    // 섹션 2.2.1에서 요구하는 AppKit 통합을 위해 AppDelegate를 연결합니다.
    // @NSApplicationDelegateAdaptor는 SwiftUI 앱 생명주기에 AppKit의 델리게이트를 통합하는
    // 공식적인 방법으로, NSStatusItem과 같은 SwiftUI 외부 객체의 생명주기를 관리하는 데 필수적입니다.[1]
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // SwiftData 모델 컨테이너를 설정하여 앱 전체에서 데이터 영속성 계층에 접근할 수 있도록 합니다.
    // 이는 섹션 1.3.2의 구현 계획에 따른 것입니다.[1]
    let container: ModelContainer
    
    init() {
        do {
            container = try ModelContainer(for: FocusLogEntry.self)
            
            // ViewModel에 ModelContext를 주입합니다.
            // AppDelegate가 생성되기 전에 ViewModel에 컨텍스트를 전달해야 하므로 init에서 처리합니다.
            viewModel.setModelContext(container.mainContext)
            
            // AppDelegate에도 ViewModel 인스턴스를 전달하여 AppKit 계층에서
            // 동일한 '단일 진실 공급원'에 접근할 수 있도록 합니다.
            appDelegate.pomodoroViewModel = viewModel
        } catch {
            fatalError("Failed to create ModelContainer for FocusLogEntry. Error: \(error)")
        }
    }

    var body: some Scene {
        // 메인 윈도우 그룹. 섹션 6.2.1의 계획에 따라 로그 뷰를 위한 표준 윈도우를 정의합니다.
        // 이 윈도우는 앱 시작 시 자동으로 열리지 않고, 사용자가 명시적으로 열 때만 나타납니다.
        // SettingsView에서 openWindow(id:)를 통해 호출할 수 있도록 id를 지정합니다.
        WindowGroup("나의 생산성 기록", id: "log-window") {
            LogView()
                //.environmentObject 수정자를 사용하여 뷰 계층 전체에 viewModel을 공유합니다.
                // 이는 섹션 1.2.1에서 설명한 'prop drilling'을 피하고 효율적으로 상태를 전파하는 방법입니다.[1]
              .environmentObject(viewModel)
        }
        // SwiftData의 ModelContainer를 환경에 주입하여 하위 뷰(예: LogView)에서
        // @Query를 통해 데이터에 접근할 수 있도록 합니다.[1]
      .modelContainer(container)
    }
}
