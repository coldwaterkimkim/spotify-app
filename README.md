# 울트라돌멩의솦티파이리릭

Dock/Menu bar 아이콘 없이 백그라운드에서 작동하는 macOS Spotify 가사 자막 오버레이 앱이다.

## 제품 방향

- Spotify 재생 중이면 화면 하단 중앙에 자막처럼 현재 원문 가사 1줄만 띄운다.
- 번역, 해석, 공부 기능은 넣지 않는다.
- 앱 아이콘은 사용자 사진을 얼굴/파란 안경 중심으로 crop한 이미지다.
- 오버레이에는 별도 drag handle이나 resize grip 없이 lyrics만 둔다.
- 패널 자체를 잡아 움직일 수 있다.
- 패널 위에서 우클릭하면 preference panel을 연다.
- `마우스 통과 모드`가 켜져 있으면 클릭이 앱으로 들어오지 않으므로 우클릭 설정 호출도 비활성화된다.
- 설정 창에서 항상 위, 마우스 통과, 배경 투명도, 자막 크기, 최대 폭, 하단 여백, 싱크 보정을 조절한다.
- `최대 폭`은 자막이 커질 수 있는 상한이고, `자막 크기`는 그 폭 안에서 패널과 글자를 비율 유지 스케일링한다.
- 설정 창은 앱을 직접 열 때 나타나고, 백그라운드 실행에서는 뜨지 않는다.

## Spotify 연결

Spotify 공식 API는 현재 곡, 재생 상태, 재생 위치를 읽는 데만 사용한다. 가사는 Spotify API가 제공하지 않으므로 LRCLIB에서 synced/plain lyrics를 가져온다.

처음 연결 전에 Spotify Developer Dashboard에서 앱을 만들고 Redirect URI에 아래 값을 등록해야 한다.

```text
http://127.0.0.1:43879/callback
```

그 다음 앱 설정 창에 Spotify Client ID를 입력하고 `Spotify 연결`을 누르면 된다.

## 로컬 실행

Codex Run 버튼 또는 아래 명령으로 실행한다.

```bash
./script/build_and_run.sh
```

검증용 실행:

```bash
./script/build_and_run.sh --verify
```

Spotify 연결 전 자막 오버레이 미리보기까지 띄우는 실행:

```bash
./script/build_and_run.sh --demo
```

설정 창 없이 백그라운드로 실행:

```bash
./script/build_and_run.sh --background
```

## 구현 구조

- `Sources/UltraDolmengSpotifyLyric/main.swift`: Dock 없는 AppKit 앱 부팅.
- `Sources/UltraDolmengCore/App`: 앱 delegate와 생명주기.
- `Sources/UltraDolmengCore/Windows`: 설정 창과 자막 오버레이 NSPanel 제어.
- `Sources/UltraDolmengCore/Views`: SwiftUI 설정 화면과 caption overlay.
- `Sources/UltraDolmengCore/Services`: Spotify OAuth/API, LRCLIB, 가사 파서, playback coordinator.
- `Sources/UltraDolmengCore/Stores`: 사용자 설정 저장.
- `Resources/AppIcon.icns`: Finder/app bundle에서 쓰는 macOS 앱 아이콘.
- `Tests/UltraDolmengCoreTests`: LRC 파서와 1줄 caption 선택 테스트.
