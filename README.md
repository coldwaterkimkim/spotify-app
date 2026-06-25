# 울트라돌멩의솦티파이리릭

Dock/Menu bar 아이콘 없이 백그라운드에서 작동하는 macOS Spotify 가사 자막 오버레이 앱이다.

## 제품 방향

- Spotify 재생 중이면 화면 하단 중앙에 자막처럼 현재 원문 가사 1줄만 띄운다.
- 가사를 아직 가져오는 중이어도 재생 중이면 자막 패널 자체는 유지한다.
- 번역, 해석, 공부 기능은 넣지 않는다.
- 앱 아이콘은 사용자 사진을 얼굴/파란 안경 중심으로 crop한 이미지다.
- 오버레이에는 별도 drag handle이나 resize grip 없이 lyrics만 둔다.
- 패널 자체를 잡아 움직일 수 있다.
- 패널은 보이는 자막 박스 기준으로 화면 상하좌우 edge까지 붙일 수 있다.
- 패널 위에 hover하면 이전 곡, 재생/일시정지, 다음 곡, 재생목록 버튼이 아이콘만 나타난다.
- 재생목록 버튼을 누르면 Spotify queue의 다음 곡들을 별도 floating panel로 자막 위쪽에 펼쳐 보여준다.
- queue는 가사 패널을 밀지 않고 위로만 펼쳐지며, AppKit 스크롤러를 숨긴 채 스크롤과 row 전체 클릭 재생을 지원한다.
- 패널 위에서 우클릭하면 preference panel을 연다.
- 설정 창에서 항상 위, 배경 투명도, 자막 크기, 최대 폭, 싱크 보정을 조절한다.
- `최대 폭`은 자막이 커질 수 있는 상한이고, `자막 크기`는 그 폭 안에서 패널과 글자를 비율 유지 스케일링한다.
- 설정 창은 앱을 직접 열 때 나타나고, 백그라운드 실행에서는 뜨지 않는다.

## Spotify 연결

Spotify 공식 API는 현재 곡, 재생 상태, 재생 위치, 현재 queue 조회, 이전/다음/재생/일시정지 제어에 사용한다. Spotify API가 `429 Too Many Requests`로 현재 곡 조회까지 막힌 동안에는 로컬 Spotify Mac 앱의 AppleScript 재생 정보를 fallback으로 읽어 자막 패널을 계속 띄운다. 가사는 Spotify API가 제공하지 않으므로 LRCLIB에서 synced/plain lyrics를 가져온다. 가사 조회는 메모리 캐시와 디스크 캐시를 함께 쓰고, LRCLIB exact/search 요청을 레이스시킨다. LRCLIB 응답이 느린 편이라 timeout은 여유 있게 두고, provider 실패와 진짜 not found를 분리한다. synced lyrics가 없고 plain lyrics만 있으면 곡 길이에 맞춰 대략적인 현재 줄을 보여준다.

체감 속도를 줄이기 위해 한 번 받은 가사는 로컬 캐시에 저장한다. 같은 곡을 다시 들으면 네트워크 요청 없이 즉시 표시되고, queue를 읽은 뒤에는 다음 3곡을 백그라운드에서 순차적으로 미리 가져온다. 진짜 not found 결과는 짧게만 캐시하고, timeout/서버 실패는 캐시하지 않고 재시도한다.

처음 연결 전에 Spotify Developer Dashboard에서 앱을 만들고 Redirect URI에 아래 값을 등록해야 한다.

```text
http://127.0.0.1:43879/callback
```

그 다음 앱 설정 창에 Spotify Client ID를 입력하고 `Spotify 연결`을 누르면 된다.

queue 항목 클릭 재생과 hover playback controls에는 `user-modify-playback-state` scope가 필요하므로, 이 기능이 추가되기 전 토큰을 쓰고 있다면 설정 창에서 `다시 연결`을 한 번 눌러 새 권한을 받아야 한다.

Spotify Web API에는 queue의 n번째 항목으로 직접 점프하면서 queue를 보존하는 전용 endpoint가 없다. 그래서 queue row 클릭은 화면에서 먼저 선택 이전 항목을 빼고, 뒤에서 선택 위치만큼 `next` 명령만 조용히 실행해 Spotify의 현재 queue 흐름을 최대한 유지한다.

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

데모 실행은 저장된 Spotify 토큰이나 Keychain을 확인하지 않고, 설정창과 오버레이 UI만 미리 보여준다.

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
- `Tests/UltraDolmengCoreTests`: LRC 파서, 1줄 caption 선택, LRCLIB 조회, 디스크 캐시, Spotify queue 모델 decode 테스트.
