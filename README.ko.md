# mq-dir

> 무료·오픈소스 macOS 네이티브 파일 매니저. 여러 프로젝트와 AI 에이전트를 동시에 굴리는 사람을 위해 — 프로젝트당 최대 4개의 독립된 pane, 각 pane이 자기 폴더·정렬·스크롤 위치를 따로 들고 재시작 후에도 그대로 살아 있습니다. 텔레메트리 0, v1에서 영원히.

[![release](https://img.shields.io/github/v/release/h5nam/mq-dir?label=release&color=blue)](https://github.com/h5nam/mq-dir/releases)
[![platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](#요구사항)
[![swift](https://img.shields.io/badge/swift-5.10-orange)](https://swift.org)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)

🌐 [mqdir.com](https://mqdir.com) · 📓 [Releases](https://github.com/h5nam/mq-dir/releases) · 🛠 [Contributing](CONTRIBUTING.md) · 🌏 [English](README.md)

![mq-dir hero](.github/assets/readme_hero.png)

## 왜 만들었나

요즘 작업은 코드 절반, 부산물 절반입니다. 생성한 이미지, 녹화한 데모, PDF, QA 스크린샷, export한 transcript, 받아둔 모델, 디자인 스펙 — 어느 것도 코드 폴더와 같은 자리에 살지 않고, Finder는 이런 분량과 에이전트가 병렬로 쏟아내는 속도를 위해 만들어진 도구가 아닙니다.

mq-dir은 최대 4개의 pane을 나란히 띄워줍니다. 하나는 프로젝트, 하나는 에이전트, 하나는 산출물 dump처럼 쓰면 됩니다. 각 pane은 자기 폴더·정렬·스크롤 위치·컬럼 너비를 따로 들고 있고, 종료나 강제 종료를 거쳐도 그 상태 그대로 다시 떠오릅니다.

## 기능

- 🟦 **1 / 2H / 2V / 4-pane 레이아웃** — 활성 pane으로 라우팅, pane마다 독립 폴더.
- ↹ **Pane별 탭** — Safari 스타일 탭 바, X / +, ⌘T / ⌘W / ⌘⇧T / ⌘1…⌘9 / ⌘⇧[ / ⌘⇧], 드래그로 재정렬, 탭을 즐겨찾기로 끌어다 추가, 우클릭에 Close Other / Close to Right / Duplicate, 마지막 탭 안전장치.
- 🌳 **VS Code 스타일 트리 뷰** — 탭별 토글, 자식 lazy 로드, 셰브론만 펼침/접힘(폴더 이름 클릭은 선택만), Shift / Cmd 멀티선택, 외부 앱으로 파일 드래그 아웃. 새 탭은 폴더에 **⌘+더블클릭** 또는 **⌘+Enter** (리스트뷰와 동일).
- ⌨️ **키보드 네비게이션 + Finder급 우클릭 메뉴** — ↑/↓로 행 이동(꾹 누르면 연속 이동), Shift로 다중 선택 확장, Return으로 열기, ⌘+Return으로 새 탭 열기. **⌘C / ⌘X / ⌘V** 복사 / 잘라내기 / 붙여넣기 — Windows Explorer 스타일 이동 시맨틱(⌘X로 마킹한 선택은 ⌘V에서 복사가 아닌 이동, Finder엔 없는 동작). 우클릭 메뉴에 Open With ▸ (LaunchServices 후보 + Other…), Get Info, Reveal in Finder, Copy / Copy Path, Duplicate, Rename, **Normalize Filename to NFC** (디스크에 NFD(자모분리형)로 저장된 한글 파일명을 Windows / Slack / Discord / Gmail / 웹 업로더가 기대하는 NFC(조합형)로 다시 써줍니다 — 다중 선택 지원, 이미 NFC인 파일은 no-op), Move to Trash. 다중 선택 시 선택 전체에 적용. rename 후 키보드 포커스 복원도 list/tree 양쪽에서 정상.
- ⚙️ **설정 → 단축키** — Preferences(⌘,)에서 17개 액션을 자유롭게 재바인딩, F1…F12 지원. 행별 기본값 리셋.
- 👀 **탭별 미리보기 패널** — pane 헤더에서 토글 (또는 ⌘⇧P). PDF는 PDFKit으로 연속 스크롤 + 페이지 네비게이션, 그 외 이미지·코드·비디오·오디오·오피스 문서(DOCX/PPTX/XLSX)는 Quick Look으로, `.md`는 MarkdownUI로 GFM(테이블, 코드 블록, 리스트) 풀 렌더링. 폴더·다중·빈 선택은 별도 요약. zip 아카이브는 in-pane(목록 + 단일 항목 디코드) 미리보기. 비-PDF 문서나 macOS Quick Look이 generator를 제공하지 않는 포맷(HWP 등)의 다중 페이지 탐색은 ⎵로 floating Quick Look을 띄우거나 ⇧↩으로 시스템 기본 앱(HWP면 한컴 Office Viewer 등)에서 열어 보세요.
- 🏷️ **Finder 태그 표시** — 태그별 색상 점(빨강 / 주황 / 노랑 / 초록 / 파랑 / 보라 / 회색)을 macOS 메타데이터에서 직접 읽어 다중 태그도 모두 렌더링. 사이드바 Tags 섹션에 현재 폴더의 모든 태그 노출. 읽기 전용 — 태그 적용/편집은 Finder에서.
- 📂 **폴더 커스텀 아이콘** — Finder Get Info → 드래그로 지정한 폴더 커스텀 아이콘을 그대로 행에 렌더링.
- ⭐ **편집 가능한 즐겨찾기 사이드바** — 폴더 드래그로 추가(탭을 끌어 떨어뜨려도 OK), 우클릭 Remove / Rename, 드래그로 재정렬, ⌘⇧D로 활성 pane의 폴더를 추가. Finder 폴더 아이콘 그대로, 끊긴 경로는 별도 스타일로 표시.
- 📁 **프로젝트(워크스페이스)** — (레이아웃 + pane 탭 + 활성 pane)을 이름 붙인 스냅샷으로 저장. + 버튼으로 만들고, 클릭으로 전환, 우클릭에서 Rename / Delete, 드래그로 재정렬. 전환할 때 떠나는 프로젝트는 자동 저장됩니다.
- 💾 **상태 영구 저장** — 모든 pane / 탭 / 즐겨찾기 / 프로젝트가 재시작·강제 종료, 심지어 스키마 업그레이드(레거시 `state.json` 자동 마이그레이션)까지 거쳐도 그대로 남습니다.
- 🔎 **Pane별 재귀 검색** — debounce, case-insensitive substring 매치, 현재 폴더 서브트리 전체. ⌘F.
- 🔄 **앱 내 자동 업데이트** — Sparkle 2가 24시간마다 appcast를 polling, 새 릴리즈가 있으면 사이드바에 "Update Available" 버튼이 떠서 표준 install / relaunch 흐름이 진행됩니다.
- 💬 **앱 내 Send Feedback** — 사이드바 footer → 짧은 노트 + 옵션 스크린샷을 메인테이너에게 바로 전송(이메일 클라이언트 우회).
- 🔗 **코딩 앱 선택 연동** — 사이드바에서 cmux, Orca, Paseo, Claude Code Desktop, Codex Desktop을 선택한 뒤 Sync로 로컬 작업 폴더를 불러옵니다. 클릭하면 활성 pane, ⌘-클릭하면 새 탭에서 열립니다. 앱 선택은 재실행 후에도 유지됩니다. [설정 및 지원 범위](docs/integrations.md)를 참고하세요.
- 🎨 **macOS 네이티브 룩** — SwiftUI + AppKit, 시스템 테마 토큰, 손으로 다듬은 앱 아이콘.

**로드맵**

- 3-pane 레이아웃 옵션.
- in-pane 아카이브 포맷 확대 (tar / 7z / rar).
- 아이디어 환영 — 이슈를 열거나 앱 내 Send Feedback으로.

## 상태

**v0.1.2 — 최신 안정 버전.** 모든 태그 빌드는 Developer ID로 서명되고 Apple notarization까지 끝낸 상태로 배포됩니다. 위 기능 세트는 메인테이너와 소수의 얼리 어답터 그룹이 일상 사용 중이며, 일부 사용감 부분에 거친 모서리가 남아 있을 수 있습니다. 릴리즈별 상세는 [Releases 페이지](https://github.com/h5nam/mq-dir/releases)에서 확인하세요.

## 요구사항

- macOS 14 (Sonoma) 이상
- Apple Silicon 또는 Intel
- 빌드용: Xcode 15+, [Homebrew](https://brew.sh)

## 설치

### 사인된 DMG로 (권장)

[Releases](https://github.com/h5nam/mq-dir/releases)에서 최신 `.dmg`를 받아 `mq-dir.app`을 `/Applications`로 드래그하세요. notarize + staple 처리되어 있어 Gatekeeper가 우클릭 트릭 없이 바로 열어줍니다. 설치 후엔 Sparkle이 24시간 주기로 (또는 사이드바의 "Update Available" 버튼을 눌렀을 때) 자동 업데이트합니다.

### Homebrew로

```bash
brew install --cask h5nam/mq-dir/mq-dir
```

`brew`가 처음 실행 시 tap을 자동 설치하므로 별도 `brew tap`은 필요 없습니다. 이후 업데이트는 `brew upgrade --cask mq-dir`. cask는 위와 동일한 사인된 DMG를 가리키며, tap 레포([`h5nam/homebrew-mq-dir`](https://github.com/h5nam/homebrew-mq-dir))는 릴리즈 워크플로가 자동 갱신합니다.

### 소스에서 빌드

```bash
git clone https://github.com/h5nam/mq-dir.git
cd mq-dir
Scripts/bootstrap.sh   # XcodeGen과 xcodes CLI 설치
open mq-dir.xcodeproj
```

`bootstrap.sh`가 `project.yml`을 source of truth로 삼아 `mq-dir.xcodeproj`를 생성합니다 — `.xcodeproj`는 repo에 커밋하지 않습니다.

**테스트만 돌려보고 싶다면** (Xcode 없이 Swift 툴체인만 있어도 됩니다):

```bash
swift test
```

## 프라이버시

Markdown 미리보기의 외부 이미지는 기본 차단됩니다. 문서에서 **Load external images**를 누르면 해당 이미지 서버로 요청이 전송됩니다. 다른 문서를 열면 다시 차단됩니다. 로컬 이미지는 외부 이미지 서버 요청 없이 표시합니다.

**외부로 전화 거는 일 없습니다. Telemetry 0, Crash report 0, Analytics 0. v1에서는 영원히.**

mq-dir은 기본적으로 로컬에서만 돌아갑니다. 외부로 나가는 트래픽은 아래에 설명한 경우로 제한되며, 모두 소스로 검증 가능합니다:

1. **Markdown 외부 이미지** — 위의 명시적 불러오기 동작을 사용한 경우에만 이미지 서버에 요청합니다.
2. **Sparkle 업데이트 체크** — 24시간마다 `https://h5nam.github.io/mq-dir/appcast.xml`을 받아옴. 공개 파일이고 식별 정보는 요청에 붙이지 않습니다.
3. **Send Feedback** — 사이드바 footer에서 *직접* 버튼을 누른 경우에만, 메시지 + 옵션 스크린샷을 메인테이너 Discord 웹훅에 전송. 안 누르면 아무것도 안 나갑니다.

백그라운드 분석, 사용 ping, 크래시 리포트 업로드 없음. 로컬 상태는 `~/Library/Application Support/com.mqdir.app/`에 저장됩니다.

향후 v1.x에서 opt-in crash reporting이 제안된다면, 기본값 OFF인 설정 토글로, 소스가 공개되어 검증 가능한 형태로만 들어갑니다.

## v1에서 다루지 않는 것

클라우드 동기화, 파일 편집, 플러그인, iPadOS / iOS 포팅, 영어 외 로컬라이제이션. 아카이브 *편집*도 제외 (zip 미리보기는 in-pane으로 지원하고, tar / 7z / rar 미리보기는 로드맵에 있지만 쓰기 지원은 아님).

## 기여

PR 환영합니다. 기여는 [DCO](https://developercertificate.org/) 방식으로 받습니다 — 모든 커밋에 `Signed-off-by:` 줄이 있어야 합니다. **CLA 없음.** 워크플로는 [`CONTRIBUTING.md`](CONTRIBUTING.md), 보안 취약점 신고는 [`SECURITY.md`](SECURITY.md), 행동 규범은 [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)을 참고하세요.

## 릴리즈 (메인테이너 전용)

```bash
Scripts/release.sh --dry-run 0.3.0
Scripts/release.sh 0.3.0
```

깨끗한 `main`에서 실행합니다. 스크립트는 버전·빌드 번호를 갱신하고 커밋과 태그를 함께 push합니다. CI가 해당 태그의 테스트·번들 정보를 검증한 뒤 서명·공증·배포합니다. 이미 게시된 버전은 파일을 덮어쓰지 않으며, 재실행 시 게시된 파일을 검증해 appcast/cask 갱신만 복구합니다.

자격 증명, 의존성 잠금, 실패 시 복구 절차는 [릴리스 가이드](docs/releasing.md)를 참고하세요. 앱 프로젝트는 `Scripts/generate-project.sh`로 생성해야 저장소의 의존성 잠금이 적용됩니다.

## 라이선스

MIT — [`LICENSE`](LICENSE) 참고.

## Inspired by

mq-dir의 4-pane 레이아웃은 SoftwareOK / Nenad Hrg가 만든 Windows의 오랜 파일 매니저 **[Q-Dir](https://www.q-dir.com/)**에서 영감을 받았습니다 — 멀티-pane 파일 매니징의 효용을 입증한 작품입니다. mq-dir은 macOS용으로 Swift에서 처음부터 독립적으로 구현한 것이고, **Q-Dir의 소스를 사용하거나 Q-Dir과 제휴 관계에 있지 않습니다.**
