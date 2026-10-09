# 릴리스와 자동 업데이트

Pomodoro는 GitHub 릴리스로 배포하고, 설치된 앱은 [Sparkle](https://sparkle-project.org)로 스스로 업데이트합니다.

## 어떻게 도는가

- 앱은 `https://github.com/JeongSeongWon1116/Pomodoro/releases/latest/download/appcast.xml`(가장 최근 릴리스에 붙은 업데이트 목록)을 6시간마다 확인합니다. 켤 때도, 마지막 확인에서 6시간이 지났으면 확인합니다.
- 새 버전이 있으면 zip을 받아 **서명(EdDSA)이 앱에 든 공개 키와 맞을 때만** 설치합니다. 공개 키는 프로젝트의 빌드 설정 `POMODORO_ED_PUBLIC_KEY`, 짝이 되는 서명 키는 릴리스를 만드는 Mac의 키체인에 있습니다.
- 설치하면 앱이 꺼졌다 켜집니다. 그래서 받아 둔 업데이트는 **타이머가 완전히 대기 중이고(진행·일시정지·선택 대기·준비해 둔 다음 세션이 없음) 팝오버와 창이 모두 닫힌 상태가 1분쯤 이어졌을 때** 스스로 설치하고 다시 켭니다(`UpdateInstallGate`, `UpdateQuietness`). Dock에 최소화해 둔 창과, 앱을 가리기 전에 열려 있던 창도 열린 창으로 칩니다. 잠든 시간은 조용함으로 세지 않습니다. 설치를 넘기기 직전과 Sparkle이 앱을 끄는 순간에 한 번씩 더 확인해서, 그 사이 집중을 시작했거나 창을 열었으면 미루고 다시 기다립니다. 그 전에 앱을 끄면 그때 설치됩니다.
- 받아 둔 동안에는 설정 > 일반 > 업데이트에 "받아 둔 버전"과 **지금 설치하고 다시 켜기** 단추가 보입니다. 이 동안 Sparkle은 새로 확인하지 않습니다("지금 확인"을 쓸 수 없고, 더 새 버전이 나와도 설치한 뒤에야 찾습니다).
- 설정 > 일반 > 업데이트에서 자동 확인·자동 설치를 끄거나 "지금 확인"을 누를 수 있습니다. 자동 설치를 끄면 새 버전을 받지 않고 알림과 설정 창의 한 줄로 알려 줍니다(앱을 막 켰을 때처럼 창이 앞에 뜰 수 있는 때에는 Sparkle의 안내 창이 뜹니다). 이미 받아 둔 것이 있으면 스스로 설치하지 않고, "지금 설치하고 다시 켜기"를 누르거나 앱을 끌 때 설치됩니다. 자동 설치를 다시 켜면 이어서 스스로 설치합니다.
- Xcode에서 실행한 개발(Debug) 빌드와 단위 테스트는 업데이트를 확인하지 않습니다.

앱은 샌드박스 안에서 돕니다. 업데이트를 위해 더한 권한은 둘입니다(`Pomodoro/Pomodoro.entitlements`): 네트워크로 나가기(`network.client`), Sparkle의 설치 도우미와 말하기(`mach-lookup` 예외 두 개).

## 서명 키 (처음 한 번)

서명 키는 릴리스를 만드는 사람의 키체인에 둡니다. 저장소에는 공개 키만 들어갑니다.

1. 패키지를 받아 도구를 준비합니다(이미 `~/Library/Developer/Pomodoro-build/dd`가 있으면 건너뜁니다).
    ```bash
    cd /Volumes/C/project/Pomodoro && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Pomodoro.xcodeproj -scheme Pomodoro -derivedDataPath ~/Library/Developer/Pomodoro-build/dd -resolvePackageDependencies
    ```
2. 키를 만듭니다. 키체인이 저장을 허락할지 물으면 허용합니다. 출력에 공개 키 한 줄이 나옵니다(비밀이 아닙니다).
    ```bash
    ~/Library/Developer/Pomodoro-build/dd/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
    ```
3. 그 공개 키를 `Pomodoro.xcodeproj/project.pbxproj`의 `POMODORO_ED_PUBLIC_KEY = "";` 두 곳(Debug, Release)에 넣어 커밋합니다. 나중에 공개 키만 다시 보려면 `generate_keys -p`.

릴리스를 처음 만들 때 키체인이 `generate_appcast`(서명하는 도구)가 이 키를 써도 되는지 한 번 물을 수 있습니다. "항상 허용"을 고릅니다.

키를 잃으면 이미 설치된 앱은 새 릴리스를 받아들이지 않습니다(새 키로 만든 앱을 손으로 다시 설치해야 합니다). `generate_keys -x <파일>`로 내보내 안전한 곳에 한 벌 둘 수 있습니다. 그 파일은 저장소나 금고에 넣지 않습니다.

## 릴리스 만들기

1. 버전을 올립니다: `project.pbxproj`의 `MARKETING_VERSION`(보이는 버전)과 `CURRENT_PROJECT_VERSION`(빌드 번호 — **반드시 전보다 커야** 업데이트로 인식됩니다). `CHANGELOG.md`에 `## [버전] - 날짜` 절을 쓰고, `Readme.md`의 현재 버전을 고칩니다. main에 넣습니다.
2. main을 받아 온 깨끗한 작업 폴더에서:
    ```bash
    cd /Volumes/C/project/Pomodoro && bash scripts/release.sh
    ```
    테스트 → Release 빌드(arm64 + x86_64) → zip → 서명한 `appcast.xml`까지 만들어 `build/release/v<버전>/`에 둡니다. 아무것도 올리지 않습니다. 그 전에 세 가지를 확인하고, 어긋나면 멈춥니다: 프로젝트의 공개 키와 키체인의 서명 키가 짝인지, 빌드 번호가 지난 릴리스(가장 최근 `v*` 태그)보다 큰지, 공개 키가 지난 릴리스와 같은지(설치된 앱은 지난 릴리스의 키를 믿습니다. 키를 일부러 바꿨을 때만 `--allow-key-change`).
3. 올립니다.
    ```bash
    cd /Volumes/C/project/Pomodoro && bash scripts/release.sh --publish
    ```
    GitHub 릴리스 `v<버전>`을 만들고 zip과 `appcast.xml`을 붙입니다. 올린 뒤 앱이 보는 주소가 이 버전을 돌려주는지 확인합니다. 설치된 앱은 6시간 안에(또는 "지금 확인"으로) 받아 갑니다.
4. 이 Mac의 `/Applications/Pomodoro.app`을 곧바로 바꾸려면 `--install`을 더합니다. 실행 중인 Pomodoro를 정상 종료시키고(받아 둔 업데이트가 있어 Sparkle이 설치를 시작하면 그것이 끝나기를 기다립니다), 예전 앱은 지우지 않고 `~/Library/Developer/Pomodoro-build/replaced/`로 옮긴 뒤(이름 끝을 `.app-replaced`로 바꿔 macOS가 또 하나의 Pomodoro로 보지 않게 합니다) 새 빌드를 넣고 켭니다. "로그인 시 자동 실행"을 켜 두었다면 설치 뒤 설정 > 일반에서 켜져 있는지 한 번 봅니다. (자동 업데이트가 되는 버전이 한 번 설치된 뒤로는 필요 없습니다.)

스크립트는 `~/Library/Developer/Pomodoro-build/dd`에 빌드합니다(`POMODORO_BUILD_HOME`으로 바꿀 수 있음). Xcode의 기본 DerivedData(Xcode에서 실행 중인 앱이 쓰는 곳)는 건드리지 않습니다. 저장소가 외장 디스크에 있어도 빌드는 내장 디스크에 둡니다 — 아래 "알려진 한계"의 외장 디스크 항목 때문입니다. 저장소에 공유 scheme은 없고, `xcodebuild`가 스스로 만드는 `Pomodoro` scheme에 기댑니다.

## 업데이트가 실제로 도는지 확인하기

```bash
cd /Volumes/C/project/Pomodoro && bash scripts/update-e2e.sh
```

시험용 번들 id와 일회용 키로 세 버전을 빌드해, localhost의 업데이트 목록에서 (1) 새 버전을 스스로 받는 것과, 창이 열려 있으면 받아 두기만 하다가 앱이 끝날 때 설치되는 것(그때 창이 없었으면 스스로 설치하는 쪽으로 지나가며, 어느 쪽이었는지 출력에 적힙니다) (2) 창 없이 켜면 조용한 채로 잠시 지난 뒤 스스로 설치하고 다시 켜지는 것을 봅니다. 업데이트 목록은 릴리스와 같은 선택(전체 zip만)으로 만들고, 시험이 빨리 끝나도록 조용함을 기다리는 시간만 5초로 줄입니다(앱의 사용자 기본값 `UpdateInstallSettleSeconds`). 쓰고 있는 앱, `/Applications`, 키체인, 실제 업데이트 주소는 건드리지 않습니다. 업데이트 쪽 코드나 Sparkle 버전을 바꾼 뒤에 돌립니다. "붙잡아 두었다가 나중에 조용해져서 설치"되는 갈래, "넘기기 직전·끄는 순간에 바빠졌으면 미룸", 자동 설치를 껐다 켜는 것은 단위 테스트(`PomodoroTests/UpdateTests.swift`)로만 봅니다. 왜 설치됐는지(안 됐는지)는 콘솔 앱에서 이 앱의 category `update` 로그로 볼 수 있습니다.

## 알려진 한계

- **Apple 공증이 없습니다**(Developer ID가 없어 임시 서명입니다). 릴리스에서 받은 앱을 처음 열 때 macOS가 막으며, 한 번 허용해야 합니다(`Readme.md`의 설치). Sparkle이 설치하는 업데이트에는 이 물음이 없습니다.
- 임시 서명은 빌드마다 서명이 달라집니다. 그래서 **macOS가 서명에 묶어 기억하는 것**은 업데이트 뒤에 다시 물을 수 있습니다.
  - 기록 저장소(샌드박스 컨테이너)와 Obsidian 폴더 접근(보안 범위 북마크): 작은 시험용 샌드박스 앱으로 확인했습니다 — 같은 번들 id로 서명만 달라진 빌드들이 같은 컨테이너의 파일을 물음 없이 읽고 썼고, 예전 빌드가 만든 폴더 북마크를 그대로 풀어 그 폴더에 썼습니다(macOS 27.0, 2026-10-10). Pomodoro 자체로는 릴리스에서 릴리스로 업데이트해 본 뒤에 확정됩니다.
  - 알림 권한, 로그인 시 자동 실행: 확인하지 못했습니다. 업데이트 뒤에 한 번 봅니다.
- **앱을 외장 디스크에 두고 쓰면 자동 업데이트가 멈출 수 있습니다.** Sparkle의 설치 도우미가 외장 디스크의 앱을 바꾸려 하면 macOS가 "이동식 볼륨의 파일에 접근" 허락을 묻고, 답할 때까지 설치가 멈춥니다. 임시 서명은 빌드마다 달라서 업데이트마다 다시 묻습니다(2026-10-10에 외장 디스크에서 시험하다 확인: 화면이 잠겨 있어 답할 수 없자 설치가 그대로 멈춰 있었음). 앱은 `/Applications`(내장 디스크)에 둡니다. 같은 이유로 단위 테스트와 `update-e2e.sh`도 내장 디스크에서 빌드합니다.
- 드문 경우: 스스로 설치를 시작했다가 끄는 순간에 취소된 뒤에는(그 찰나에 집중을 시작한 경우), 다음에 앱을 끌 때 설치하면서 앱이 다시 켜질 수 있습니다. Sparkle의 설치 도우미가 "다시 켜기"를 기억하기 때문으로 보이며, 실제로 그런지는 확인하지 못했습니다.
- 받아 둔 업데이트가 있는 동안에는 새 버전을 확인하지 않습니다(Sparkle의 동작). 앱을 몇 주 동안 끄지 않고 창도 계속 열어 두면 그동안 업데이트가 멈춰 있습니다 — 설정의 "지금 설치하고 다시 켜기"로 풉니다.
- 설치 자리에 쓸 수 없으면(다른 사용자가 넣은 앱 등) Sparkle이 관리자 암호를 묻습니다.
