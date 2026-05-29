# STATUS

## 현재 상태

- SwiftPM 기반 macOS 네이티브 앱 골격 생성 완료.
- Dock/Menu bar 아이콘 없는 accessory 앱으로 설계됨.
- 앱 실행 시 설정 창이 열리고, 평소 사용 화면에는 하단 중앙 caption overlay만 표시됨.
- Spotify OAuth PKCE 루프백 콜백 흐름 구현됨.
- Spotify 현재 재생 상태 polling 구현됨.
- LRCLIB synced/plain lyrics 조회와 LRC 파싱 구현됨.
- 오버레이는 현재 줄 1줄만 표시함.
- 오버레이 drag handle은 제거됐고, 패널 자체를 잡아 이동하는 방식으로 바뀜.
- 오버레이 위 우클릭 또는 control-click으로 preference panel을 열 수 있음.
- 단, `마우스 통과 모드`에서는 클릭 이벤트가 앱으로 들어오지 않으므로 우클릭 설정 호출도 꺼짐.
- 우측 하단 resize grip은 제거됐고, 같은 크기 조절 기능은 preference panel의 `자막 크기` 슬라이더로 이동함.
- `최대 폭` 값은 preference 전용이고, `자막 크기`는 그 최대 폭 안에서 별도 스케일만 바꿈.
- 자막 배경은 반투명 black, 가사 폰트는 light weight로 표시함.
- 설정에서 항상 위, 마우스 통과, opacity preset/slider, 자막 크기, 폭, 하단 여백, pause fade delay, sync offset을 조절함.
- 설정 창은 앱을 직접 열 때만 뜨고, `--background` 실행에서는 숨김.
- 설정 창은 열릴 때만 잠깐 앞으로 끌어올리고, 이후에는 일반 창 레벨로 돌아감.
- 첨부 사진을 얼굴/파란 안경 중심으로 crop해 `Resources/AppIcon.icns` macOS 앱 아이콘으로 연결함.
- Spotify 연결 전에도 `미리보기 켜기`로 오버레이 UI를 확인할 수 있음.
- `./script/build_and_run.sh --demo`로 Spotify 연결 없이 caption overlay까지 바로 띄울 수 있음.
- Spotify Developer Dashboard 앱 생성, Redirect URI 등록, Client ID 저장, OAuth 연결까지 이 Mac에서 완료됨.
- 현재 Keychain에 Spotify refresh/access token이 저장되어 있고, 앱 상태는 `다시 연결 / 연결 해제`로 전환됨.

## Spotify 설정

현재 로컬 설정은 완료되어 있음. 다른 Mac이나 새 Spotify Developer 앱으로 옮길 때는 Redirect URI에 아래 값을 등록하고 앱 설정 창에 Client ID를 넣으면 됨.

```text
http://127.0.0.1:43879/callback
```

## 남은 리스크

- LRCLIB에 없는 곡은 synced lyrics가 표시되지 않을 수 있음.
- Spotify API polling 기반이라 재생 위치는 주기적으로 보정되며, 완전한 push 실시간 이벤트는 아님.
- Spotify Developer 앱이 Development mode라, 다른 Spotify 계정에서 쓰려면 Dashboard의 User Management에 계정을 추가해야 할 수 있음.
