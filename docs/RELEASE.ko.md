[English](RELEASE.md)

# Morrowisp — 릴리스와 자동 업데이트

Morrowisp는 GitHub 릴리스로 배포하고, 설치된 앱은 [Sparkle](https://sparkle-project.org)로 새 버전을 스스로 받아 둡니다. 설치는 사용자가 누를 때, 또는 누르지 않은 채 앱을 끌 때 합니다.

## 어떻게 도는가

- 앱은 `https://github.com/JeongSeongWon1116/Morrowisp/releases/latest/download/morrowisp-appcast.xml`(가장 최근 릴리스에 붙은 업데이트 목록)을 6시간마다 확인합니다. 켤 때도, 마지막 확인에서 6시간이 지났으면 확인합니다.
- 새 버전이 있으면 zip을 받아 **서명(EdDSA)이 앱에 든 공개 키와 맞을 때만** 설치합니다. 공개 키는 프로젝트의 빌드 설정 `MORROWISP_ED_PUBLIC_KEY`, 짝이 되는 서명 키는 릴리스를 만드는 Mac의 키체인에 있습니다.
- 설치하면 앱이 꺼졌다 켜집니다. 그래서 **스스로 설치하지 않습니다.** 받아 두면 메뉴 막대 아이콘 오른쪽 위에 빨간 점을 켜고, 아이콘을 눌러 나오는 팝오버 맨 아래에 "새 버전 x.y.z"와 **업데이트** 단추를 보여 줍니다. 누르면 설치하고 다시 켭니다(`HeldUpdate`, `UpdateController.performIndicatedUpdate`). 집중 도중에 눌러도 그대로 하며, 하던 세션은 종료할 때와 같이 기록됩니다. 누르지 않고 앱을 끄면 Sparkle이 그때 설치합니다(설치 도우미가 앱이 끝나기를 기다리고 있다가 합니다. 로그아웃이나 재시동으로 끝날 때에는 도우미가 먼저 끝나 설치되지 않을 수 있는데, 그때는 다음에 켰을 때 다시 받습니다 — 이 경우는 실제로 보지 못했습니다). 1.2.1까지는 타이머가 대기 중이고 창이 모두 닫힌 채로 1분쯤 지나면 스스로 설치하고 다시 켰습니다 — 그 동작은 1.2.2에서 없앴습니다.
- 받아 둔 동안에는 설정 > 일반 > 업데이트에도 "받아 둔 버전"과 **지금 설치하고 다시 켜기** 단추가 보입니다(팝오버의 업데이트와 같은 동작). 이 동안 Sparkle은 새로 확인하지 않습니다("지금 확인"을 쓸 수 없고, 더 새 버전이 나와도 설치한 뒤에야 찾습니다). 설치를 시작했는데 30초가 지나도 앱이 꺼지지 않으면(설치 도우미가 실패한 경우) 단추가 다시 살아납니다.
- 설정 > 일반 > 업데이트에서 자동 확인을 끄거나 "지금 확인"을 누를 수 있습니다. 자동 확인을 끄면 새 버전을 받지도 않습니다(Sparkle의 규칙). 켜져 있으면 늘 받아 둡니다 — 1.2.1까지 있던 "새 버전을 자동으로 받아 설치" 스위치는 없앴고, 꺼 두었던 값이 남아 있으면 앱을 켤 때 켭니다(`preferDownloadingUpdates`).
- 곧바로 설치할 수 없는 업데이트는 같은 점으로 알리고, **업데이트**를 누르면 Sparkle의 안내 창이 앞에 떠서 거기서 이어 갑니다. Sparkle이 스스로 받을 수 없는 업데이트(안내만 하는 업데이트, 큰 판 올림), 설치 도우미가 이미 떠 있어 이어 가는 경우, 관리자 암호가 필요해 미뤄진 경우가 그렇습니다. 앱을 막 켰을 때에도 안내 창을 스스로 띄우지 않습니다.
- Xcode에서 실행한 개발(Debug) 빌드와 단위 테스트는 업데이트를 확인하지 않습니다.

앱은 샌드박스 안에서 돕니다. 업데이트를 위해 더한 권한은 둘입니다(`Morrowisp/Morrowisp.entitlements`): 네트워크로 나가기(`network.client`), Sparkle의 설치 도우미와 말하기(`mach-lookup` 예외 두 개).

## Pomodoro(옛 이름)에서 옮겨 오기

2.0.0(빌드 8)은 SW Square의 새 앱입니다. `Morrowisp.app`을 직접 설치하며 옛 앱의 기록·설정·업데이트는 이어지지 않습니다. 옛 `Pomodoro.app`은 종료한 뒤 지워도 되지만 `~/Library/Containers/Jeong.Pomodoro`는 남습니다. 새 피드는 `morrowisp-appcast.xml`이며 옛 `appcast.xml` 이름으로 배포하지 않습니다. 공개 키는 그대로입니다.

릴리스 스크립트는 지난 태그에 새 프로젝트 경로가 없으면 옛 `Pomodoro.xcodeproj/project.pbxproj`와 `POMODORO_ED_PUBLIC_KEY`를 읽습니다. 2.0.0의 첫 패키징에서도 이전 빌드 번호·공개 키 확인을 유지합니다.

## 서명 키 (처음 한 번 — 이 저장소는 2026-10-10에 마쳤습니다)

서명 키는 릴리스를 만드는 사람의 키체인에 둡니다. 저장소에는 공개 키만 들어갑니다. 아래는 키를 새로 만들어야 할 때(다른 Mac에서 릴리스를 만들게 됐거나 키를 잃었을 때)의 절차입니다.

1. 패키지를 받아 도구를 준비합니다(이미 `~/Library/Developer/Morrowisp-build/dd`가 있으면 건너뜁니다).
    ```bash
    cd ~/work/pomo-i18n && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Morrowisp.xcodeproj -scheme Morrowisp -derivedDataPath ~/Library/Developer/Morrowisp-build/dd -resolvePackageDependencies
    ```
2. 키를 만듭니다. 키체인이 저장을 허락할지 물으면 허용합니다. 출력에 공개 키 한 줄이 나옵니다(비밀이 아닙니다).
    ```bash
    ~/Library/Developer/Morrowisp-build/dd/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
    ```
3. 그 공개 키를 `Morrowisp.xcodeproj/project.pbxproj`의 `MORROWISP_ED_PUBLIC_KEY = "…";` 두 곳(Debug, Release)에 넣어 커밋합니다(지금은 2026-10-10에 만든 키의 공개 쪽이 들어 있습니다). 나중에 공개 키만 다시 보려면 `generate_keys -p`.

릴리스를 만들 때 키체인이 `generate_appcast`(서명하는 도구)가 이 키를 써도 되는지 묻습니다. **"항상 허용"을 고릅니다** — "허용"만 누르면 그 한 번만 통하고, 다음 실행 때 다시 물으며 답할 때까지 스크립트가 "묶음과 appcast" 단계에서 멈춰 있습니다(화면이 잠겨 있으면 그대로 멈춥니다. 2026-10-10 예행에서 확인).

키를 잃으면 이미 설치된 앱은 새 릴리스를 받아들이지 않습니다(새 키로 만든 앱을 손으로 다시 설치해야 합니다). `generate_keys -x <파일>`로 내보내 안전한 곳에 한 벌 둘 수 있습니다. 그 파일은 저장소나 금고에 넣지 않습니다.

## 릴리스 만들기

1. 버전을 올립니다: `project.pbxproj`의 `MARKETING_VERSION`(보이는 버전)과 `CURRENT_PROJECT_VERSION`(빌드 번호 — **반드시 전보다 커야** 업데이트로 인식됩니다). `CHANGELOG.md`에 `## [버전] - 날짜` 절을 쓰고, `Readme.md`의 현재 버전을 고칩니다. main에 넣습니다.
2. main을 받아 온 깨끗한 작업 폴더에서:
    ```bash
    cd ~/work/pomo-i18n && bash scripts/release.sh
    ```
    테스트 → Release 빌드(arm64 + x86_64) → zip → 서명한 `morrowisp-appcast.xml`까지 만들어 `build/release/v<버전>/`에 둡니다. 아무것도 올리지 않습니다. 그 전에 세 가지를 확인하고, 어긋나면 멈춥니다: 프로젝트의 공개 키와 키체인의 서명 키가 짝인지, 빌드 번호가 지난 릴리스(가장 최근 `v*` 태그)보다 큰지, 공개 키가 지난 릴리스와 같은지(설치된 앱은 지난 릴리스의 키를 믿습니다. 키를 일부러 바꿨을 때만 `--allow-key-change`).
3. 올립니다.
    ```bash
    cd ~/work/pomo-i18n && bash scripts/release.sh --publish
    ```
    GitHub 릴리스 `v<버전>`을 만들고 zip과 `morrowisp-appcast.xml`을 붙입니다. 올린 뒤 앱이 보는 주소가 이 버전을 돌려주는지 확인합니다. 설치된 앱은 6시간 안에(또는 "지금 확인"으로) 받아 갑니다.
4. 이 Mac의 `/Applications/Morrowisp.app`을 곧바로 바꾸려면 `--install`을 더합니다. 실행 중인 Morrowisp를 정상 종료시키고(받아 둔 업데이트가 있어 Sparkle이 설치를 시작하면 그것이 끝나기를 기다리고, 그 뒤 다시 켜진 앱이 있으면 한 번 더 끕니다 — 떠 있는 앱도 설치 도우미도 없는 상태가 5초 이어진 뒤에 넘어갑니다), 예전 앱은 지우지 않고 `~/Library/Developer/Morrowisp-build/replaced/`로 옮긴 뒤(이름 끝을 `.app-replaced`로 바꿔 macOS가 또 하나의 Morrowisp로 보지 않게 합니다) 새 빌드를 넣고 켠 다음, 떠 있는 것이 방금 넣은 앱인지 확인합니다. 실행 중인 앱은 번들 id로 찾으므로 Xcode에서 띄운 개발 빌드도 함께 끕니다. "로그인 시 자동 실행"을 켜 두었다면 설치 뒤 설정 > 일반에서 켜져 있는지 한 번 봅니다. (자동 업데이트가 되는 버전이 한 번 설치된 뒤로는 필요 없습니다.)

**올린 뒤에 실패했을 때.** `--publish`가 릴리스를 만든 뒤 그 뒤의 단계(올린 것 확인, `--install`)가 실패하면 릴리스와 태그는 이미 있습니다. 같은 명령을 다시 돌리면 "태그가 이미 있습니다"로 멈춥니다.
- 설치만 다시: `bash scripts/release.sh --install` — 처음부터 다시 빌드해 넣습니다(올린 zip과 서명만 다른 같은 버전이라 업데이트 동작에는 해가 없습니다).
- 첨부 파일만 다시 올리기: `gh release upload v<버전> build/release/v<버전>/Morrowisp-<버전>.zip build/release/v<버전>/morrowisp-appcast.xml --clobber`
- 처음부터 다시(아직 아무도 받지 않았을 때만): `gh release delete v<버전> --cleanup-tag` 뒤 다시 `--publish`.

스크립트는 `~/Library/Developer/Morrowisp-build/dd`에 빌드합니다(`MORROWISP_BUILD_HOME`으로 바꿀 수 있음). Xcode의 기본 DerivedData(Xcode에서 실행 중인 앱이 쓰는 곳)는 건드리지 않습니다. 저장소가 외장 디스크에 있어도 빌드는 내장 디스크에 둡니다 — 아래 "알려진 한계"의 외장 디스크 항목 때문입니다. 저장소의 공유 스킴 `Morrowisp.xcodeproj/xcshareddata/xcschemes/Morrowisp.xcscheme`으로 빌드·시험합니다.

## 업데이트가 실제로 도는지 확인하기

```bash
cd ~/work/pomo-i18n && bash scripts/update-e2e.sh
```

시험용 번들 id와 일회용 키로 세 버전을 빌드해, localhost의 업데이트 목록에서 (1) 새 버전을 스스로 **받아 두되 설치하지는 않는 것**(창 없이 켜고, 앱의 로그에 "holding update"가 찍힌 때부터 90초를 지켜봅니다 — 예전에 스스로 설치하던 조건인 60초와 재는 간격 10초보다 깁니다)과 앱이 끝날 때 설치되는 것 (2) 받아 둔 것을 **업데이트를 누른 것과 같은 길로** 설치하고 다시 켜지는 것을 봅니다. 단추를 실제로 누르지는 못하므로 (2)에서는 시험용 실행 인자 `-UpdateInstallHeldOnArrival YES`를 줍니다: 받아 두자마자 단추와 같은 함수를 부릅니다. 이 인자는 실행 인자로만 읽고 저장된 설정은 보지 않으므로 평소의 앱에서는 켜지지 않습니다. 업데이트 목록은 릴리스와 같은 선택(전체 zip만)으로 만듭니다. 쓰고 있는 앱, `/Applications`, 키체인, 실제 업데이트 주소는 건드리지 않습니다. 업데이트 쪽 코드나 Sparkle 버전을 바꾼 뒤에 돌립니다. 점과 단추가 실제로 보이는지, 단추를 눌렀을 때의 동작, 집중 도중에 눌렀을 때는 화면에서 봐야 합니다(단추가 부르는 함수까지는 단위 테스트 `MorrowispTests/UpdateTests.swift`가 봅니다). 언제 받아 두었고 언제 설치했는지는 콘솔 앱이나 `/usr/bin/log show`에서 이 앱의 category `update` 로그로 볼 수 있습니다(시험도 이 로그를 읽습니다).

## 알려진 한계

- **Apple 공증이 없습니다**(Developer ID가 없어 임시 서명입니다). 릴리스에서 받은 앱을 처음 열 때 macOS가 막으며, 한 번 허용해야 합니다(`Readme.md`의 설치). Sparkle이 설치하는 업데이트에는 이 물음이 없습니다.
- 임시 서명은 빌드마다 서명이 달라집니다. 그래서 **macOS가 서명에 묶어 기억하는 것**은 업데이트 뒤에 다시 물을 수 있습니다.
  - 기록 저장소(샌드박스 컨테이너)와 Obsidian 폴더 접근(보안 범위 북마크): 작은 시험용 샌드박스 앱으로 확인했습니다 — 같은 번들 id로 서명만 달라진 빌드들이 같은 컨테이너의 파일을 물음 없이 읽고 썼고, 예전 빌드가 만든 폴더 북마크를 그대로 풀어 그 폴더에 썼습니다(macOS 27.0, 2026-10-10). Morrowisp 자체로는 릴리스에서 릴리스로 업데이트해 본 뒤에 확정됩니다.
  - 알림 권한, 로그인 시 자동 실행: 확인하지 못했습니다. 업데이트 뒤에 한 번 봅니다.
- **앱을 외장 디스크에 두고 쓰면 자동 업데이트가 멈출 수 있습니다.** Sparkle의 설치 도우미가 외장 디스크의 앱을 바꾸려 하면 macOS가 "이동식 볼륨의 파일에 접근" 허락을 묻고, 답할 때까지 설치가 멈춥니다. 임시 서명은 빌드마다 달라서 업데이트마다 다시 묻습니다(2026-10-10에 외장 디스크에서 시험하다 확인: 화면이 잠겨 있어 답할 수 없자 설치가 그대로 멈춰 있었음). 앱은 `/Applications`(내장 디스크)에 둡니다. 같은 이유로 단위 테스트와 `update-e2e.sh`도 내장 디스크에서 빌드합니다.
- 업데이트를 받아 두고 있는 동안 Sparkle 쪽의 업데이트 주기가 끝나면(설치 도우미의 오류나 연결이 끊긴 경우) 그 설치 동작은 더 쓸 수 없어 점과 단추가 사라집니다. 설치 도우미까지 끝났으면 다음 확인 때 다시 받습니다. 연결만 끊겨 도우미가 남아 있으면 점이 없어도 **앱을 끌 때 설치되고**, 다음 정해진 확인은 6시간보다 늦을 수 있습니다(Sparkle은 설치를 기다리는 동안 확인 간격을 최대 한 주로 늘립니다 — 2.10.0의 `SPUUpdater.m`, `SPUUpdaterSettings.m`). 그때는 설정의 "지금 확인"을 누르면 안내 창에서 이어 갑니다.
- 받아 둔 업데이트가 있는 동안에는 새 버전을 확인하지 않습니다(Sparkle의 동작). 점을 오래 두면 그 사이에 나온 더 새 버전은 받아 둔 것을 설치한 뒤에야 찾습니다 — 그때 점이 한 번 더 켜집니다.
- 점은 앱이 켜져 있는 동안의 상태입니다. 받아 둔 채로 앱을 끄면 그때 설치되므로 다시 켰을 때는 새 버전이고 점이 없습니다. 스스로 받을 수 없는 업데이트를 찾기만 한 경우에는 앱을 다시 켠 뒤 다음 확인(6시간 안)까지 점이 없을 수 있습니다.
- 설치 자리에 쓸 수 없으면(다른 사용자가 넣은 앱 등) Sparkle이 관리자 암호를 묻습니다. `release.sh --install`은 그 경우 앱을 끄기 전에 멈춥니다. 다만 macOS의 "앱 관리" 제한(다른 앱이 앱 묶음을 바꾸는 것을 막는 설정)은 미리 알 수 없어, 거기에 걸리면 앱이 꺼진 채로 옮기기에서 멈춥니다(2026-10-10의 실제 설치에서는 걸리지 않았습니다).
- **앞으로 올리는 모든 정식 릴리스에 `morrowisp-appcast.xml`이 붙어 있어야 합니다.** 앱은 "가장 최근 릴리스"에 붙은 `morrowisp-appcast.xml`을 봅니다. 그것이 없는 릴리스가 가장 최근 것이 되면(GitHub 화면에서 손으로 만든 릴리스 등) 설치된 모든 앱의 확인이 조용히 실패합니다. 릴리스는 `scripts/release.sh --publish`로만 만듭니다.
- 두 스크립트는 어떻게 부르든 macOS의 `/bin/bash`로 다시 실행됩니다. Homebrew의 bash(5.x)로 돌리면 하위 셸이 로캘을 되돌리다가 드물게 죽습니다(2026-10-10 예행에서 한 번: 테스트 직후 종료 코드 139로 끝남. 충돌 기록에 gettext의 `setlocale` → CoreFoundation). 스크립트 안에서는 셸의 로캘 변수를 바꾸지 않습니다(`env LC_ALL=C grep …`처럼 명령에만 줍니다).
