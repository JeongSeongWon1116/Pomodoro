# Obsidian 연동 가이드

뽀모도로 앱은 별도의 Obsidian 플러그인 설치 없이 데일리 노트에 세션 기록을 자동으로 남길 수 있습니다.
Obsidian은 보관함(Vault)을 일반 폴더의 마크다운 파일로 관리하기 때문에, 앱이 해당 폴더에 직접
마크다운을 기록하면 Obsidian에서 즉시 반영됩니다.

## 설정 방법

1. 메뉴 바의 뽀모도로 아이콘을 클릭해 팝오버를 엽니다.
2. **Obsidian 데일리 노트 기록** 토글을 켭니다.
3. **폴더 선택** 버튼을 눌러 데일리 노트가 저장되는 폴더를 선택합니다.
   - 데일리 노트를 보관함 루트에 저장한다면 보관함 폴더를 선택하세요.
   - `Daily/` 같은 하위 폴더를 쓴다면 그 폴더를 선택하세요.
   - 선택한 폴더는 보안 범위 북마크(security-scoped bookmark)로 저장되어 앱을 재시작해도 유지됩니다.

## 동작 방식

세션(집중/휴식)이 끝날 때마다 해당 날짜의 `yyyy-MM-dd.md` 파일에 아래와 같이 기록됩니다.
파일이 없으면 새로 만들고, 이미 있으면 `## 🍅 뽀모도로` 섹션을 찾아 그 끝에 줄을 추가합니다.
(섹션이 없으면 노트 맨 아래에 섹션을 새로 만듭니다. 노트의 기존 내용은 건드리지 않습니다.)

```markdown
## 🍅 뽀모도로
- 🍅 집중 25분 (09:00–09:25)
- ☕️ 짧은 휴식 5분 (09:25–09:30)
- 🍅 집중 25분 (09:31–09:58)
```

종료 시각에는 일시정지한 시간이 포함되며, 분 단위 숫자는 실제 집중(활동)한 시간입니다.

## Obsidian에서 통계 활용하기 (선택)

[Dataview](https://blacksmithgu.github.io/obsidian-dataview/) 플러그인을 쓰고 있다면,
아무 노트에나 아래 쿼리를 넣어 최근 집중 기록을 모아볼 수 있습니다.

````markdown
```dataviewjs
const pages = dv.pages('"Daily"').sort(p => p.file.name, 'desc').limit(7);
for (const page of pages) {
    const content = await dv.io.load(page.file.path);
    const lines = (content.match(/^- 🍅 집중 (\d+)분.*$/gm) ?? []);
    const total = lines.reduce((sum, l) => sum + parseInt(l.match(/(\d+)분/)[1]), 0);
    dv.paragraph(`**${page.file.name}**: 🍅 ${lines.length}회, 총 ${total}분`);
}
```
````

> `"Daily"` 부분은 데일리 노트 폴더 경로에 맞게 수정하세요.

## 다른 연동 방식과의 비교

| 방식 | 장점 | 단점 |
|------|------|------|
| **폴더 직접 기록 (현재 방식)** | Obsidian이 꺼져 있어도 동작, 플러그인 불필요 | 폴더를 한 번 선택해야 함 |
| Obsidian URI (`obsidian://`) + Advanced URI 플러그인 | 설정이 간단 | 기록 시마다 Obsidian이 활성화됨, 플러그인 필요, 백그라운드 기록 불가 |
| 전용 Obsidian 커뮤니티 플러그인 제작 | Obsidian 내부 UI 제공 가능 | 별도 프로젝트 유지보수 필요, 앱→플러그인 데이터 전달 경로가 결국 파일 기반 |

데일리 노트의 파일명 형식이 `yyyy-MM-dd`(Obsidian 기본값)가 아닌 경우 현재는 지원되지 않습니다.
