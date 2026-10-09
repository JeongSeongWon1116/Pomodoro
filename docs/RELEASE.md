# 릴리스와 자동 업데이트

Pomodoro는 GitHub 릴리스로 배포하고, 설치된 앱은 [Sparkle](https://sparkle-project.org)로 스스로 업데이트합니다.

## 어떻게 도는가

- 앱은 `https://github.com/JeongSeongWon1116/Pomodoro/releases/latest/download/appcast.xml`(가장 최근 릴리스에 붙은 업데이트 목록)을 6시간마다, 그리고 켤 때 확인합니다.
- 새 버전이 있으면 zip을 받아 **서명(EdDSA)이 앱에 든 공개 키와 맞을 때만** 설치합니다. 공개 키는 프로젝트의 빌드 설정 `POMODORO_ED_PUBLIC_KEY`, 짝이 되는 서명 키는 릴리스를 만드는 Mac의 키체인에 있습니다.
- 설치하면 앱이 꺼졌다 켜집니다. 그래서 받아 둔 업데이트는 **타이머가 완전히 대기 중이고 팝오버와 창이 모두 닫혀 있을 때** 설치합니다(`UpdateInstallGate`). 그 전에 앱을 끄면 그때 설치됩니다.
- 설정 > 일반 > 업데이트에서 자동 확인·자동 설치를 끄거나 "지금 확인"을 누를 수 있습니다. 자동 설치를 끄면 새 버전이 있을 때 알림과 설정 창의 한 줄로 알려 줍니다.
- Xcode에서 실행한 개발(Debug) 빌드와 단위 테스트는 업데이트를 확인하지 않습니다.

앱은 샌드박스 안에서 돕니다. 업데이트를 위해 더한 권한은 둘입니다(`Pomodoro/Pomodoro.entitlements`): 네트워크로 나가기(`network.client`), Sparkle의 설치 도우미와 말하기(`mach-lookup` 예외 두 개).

## 서명 키 (처음 한 번)

서명 키는 릴리스를 만드는 사람의 키체인에 둡니다. 저장소에는 공개 키만 들어갑니다.

1. 패키지를 받아 도구를 준비합니다(이미 `build/dd`가 있으면 건너뜁니다).
    ```bash
    cd /Volumes/C/project/Pomodoro && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Pomodoro.xcodeproj -scheme Pomodoro -derivedDataPath build/dd -resolvePackageDependencies
    ```
2. 키를 만듭니다. 키체인이 저장을 허락할지 물으면 허용합니다. 출력에 공개 키 한 줄이 나옵니다(비밀이 아닙니다).
    ```bash
    /Volumes/C/project/Pomodoro/build/dd/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
    ```
3. 그 공개 키를 `Pomodoro.xcodeproj/project.pbxproj`의 `POMODORO_ED_PUBLIC_KEY = "";` 두 곳(Debug, Release)에 넣어 커밋합니다. 나중에 공개 키만 다시 보려면 `generate_keys -p`.

키를 잃으면 이미 설치된 앱은 새 릴리스를 받아들이지 않습니다(새 키로 만든 앱을 손으로 다시 설치해야 합니다). `generate_keys -x <파일>`로 내보내 안전한 곳에 한 벌 둘 수 있습니다. 그 파일은 저장소나 금고에 넣지 않습니다.

## 릴리스 만들기

1. 버전을 올립니다: `project.pbxproj`의 `MARKETING_VERSION`(보이는 버전)과 `CURRENT_PROJECT_VERSION`(빌드 번호 — **반드시 전보다 커야** 업데이트로 인식됩니다). `CHANGELOG.md`에 `## [버전] - 날짜` 절을 쓰고, `Readme.md`의 현재 버전을 고칩니다. main에 넣습니다.
2. main을 받아 온 깨끗한 작업 폴더에서:
    ```bash
    cd /Volumes/C/project/Pomodoro && bash scripts/release.sh
    ```
    테스트 → Release 빌드(arm64 + x86_64) → zip → 서명한 `appcast.xml`까지 만들어 `build/release/v<버전>/`에 둡니다. 아무것도 올리지 않습니다.
3. 올립니다.
    ```bash
    cd /Volumes/C/project/Pomodoro && bash scripts/release.sh --publish
    ```
    GitHub 릴리스 `v<버전>`을 만들고 zip과 `appcast.xml`을 붙입니다. 올린 뒤 앱이 보는 주소가 이 버전을 돌려주는지 확인합니다. 설치된 앱은 6시간 안에(또는 "지금 확인"으로) 받아 갑니다.
4. 이 Mac의 `/Applications/Pomodoro.app`을 곧바로 바꾸려면 `--install`을 더합니다. 실행 중인 Pomodoro를 정상 종료시키고, 예전 앱은 지우지 않고 `build/replaced/`로 옮긴 뒤 새 빌드를 넣고 켭니다. (자동 업데이트가 되는 버전이 한 번 설치된 뒤로는 필요 없습니다.)

스크립트는 `build/dd`에 빌드합니다. Xcode의 기본 DerivedData(Xcode에서 실행 중인 앱이 쓰는 곳)는 건드리지 않습니다.

## 업데이트가 실제로 도는지 확인하기

```bash
cd /Volumes/C/project/Pomodoro && bash scripts/update-e2e.sh
```

시험용 번들 id와 일회용 키로 세 버전을 빌드해, localhost의 업데이트 목록에서 (1) 받아 두었다가 앱이 끝날 때 설치되는 것과 (2) 창이 없을 때 스스로 설치하고 다시 켜지는 것을 봅니다. 쓰고 있는 앱, `/Applications`, 키체인, 실제 업데이트 주소는 건드리지 않습니다. 업데이트 쪽 코드나 Sparkle 버전을 바꾼 뒤에 돌립니다.

## 알려진 한계

- **Apple 공증이 없습니다**(Developer ID가 없어 임시 서명입니다). 릴리스에서 받은 앱을 처음 열 때 macOS가 막으며, 한 번 허용해야 합니다(`Readme.md`의 설치). Sparkle이 설치하는 업데이트에는 이 물음이 없습니다.
- 임시 서명은 빌드마다 서명이 달라집니다. 그래서 **macOS가 서명에 묶어 기억하는 것**은 업데이트 뒤에 다시 물을 수 있습니다: Obsidian 폴더 접근(폴더를 다시 골라야 할 수 있음), 알림 권한, 로그인 시 자동 실행. 실제로 어떤지는 릴리스에서 릴리스로 업데이트해 보며 확인해야 합니다.
- 설치 자리에 쓸 수 없으면(다른 사용자가 넣은 앱 등) Sparkle이 관리자 암호를 묻습니다.
