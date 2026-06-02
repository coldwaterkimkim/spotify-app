# STATUS

## 현재 상태

- SwiftPM 기반 macOS 네이티브 앱 골격 생성 완료.
- Dock/Menu bar 아이콘 없는 accessory 앱으로 설계됨.
- 앱 실행 시 설정 창이 열리고, 평소 사용 화면에는 하단 중앙 caption overlay만 표시됨.
- Spotify OAuth PKCE 루프백 콜백 흐름 구현됨.
- Spotify 현재 재생 상태 polling 구현됨.
- Spotify queue 조회 구현됨. queue는 overlay 버튼을 눌렀을 때 on-demand로 읽음.
- Spotify queue row 클릭 재생 구현됨. row 클릭은 단일 URI 재생이 아니라 화면에서 먼저 선택 이전 항목을 제거하고, 백그라운드에서 선택 위치만큼 `next` 명령을 순차 실행해서 기존 queue 흐름을 최대한 유지함.
- 이전 곡, 재생/일시정지, 다음 곡 hover controls 구현됨. 새 scope인 `user-modify-playback-state`가 필요하므로 기존 연결은 `다시 연결`이 필요할 수 있음.
- LRCLIB synced/plain lyrics 조회와 LRC 파싱 구현됨. 현재 실행 중에는 가사를 메모리 캐시하고, 한 번 받은 가사는 디스크 캐시에 저장함. exact/search 조회를 레이스시키고, LRCLIB 응답이 7~11초 걸리는 케이스를 확인해 timeout을 늘렸으며, provider 실패와 진짜 not found를 분리함. synced lyrics가 없고 plain lyrics만 있으면 곡 길이에 맞춰 대략적인 현재 줄을 보여줌.
- Spotify API가 현재 곡 조회까지 `429 Too Many Requests`로 막힌 동안에는 로컬 Spotify Mac 앱의 AppleScript 재생 정보를 fallback으로 읽어 자막 패널을 계속 띄움. 이 fallback은 queue 조회/재생 제어가 아니라 현재 곡/재생 위치 표시용임.
- queue를 읽으면 다음 3곡 가사를 백그라운드에서 순차 프리패치함. 같은 곡을 다시 듣거나 프리패치된 곡으로 넘어가면 네트워크 요청 없이 즉시 표시됨.
- Spotify Liked Songs 전체를 백그라운드에서 훑는 가사 캐시 워머를 추가함. 앱 시작/Spotify 연결 후 최근 좋아요 구간을 먼저 확인하고, 이전에 멈춘 offset부터 전체 라이브러리 캐시를 이어서 진행함. 완료 후에는 하루 1번 최근 좋아요 구간을 다시 확인함. LRCLIB 가사 조회는 동시 32곡씩 병렬 처리함.
- Spotify API가 `429 Too Many Requests`를 반환하면 `Retry-After`를 읽어 그 시간만큼 쉬고, 좋아요 곡 캐시는 같은 offset에서 이어서 진행함. 재생 상태 polling은 Spotify 부하를 줄이기 위해 2초 간격으로 조정됨.
- 좋아요 곡 캐시에는 새 scope인 `user-library-read`가 필요하므로 기존 연결은 `다시 연결`이 필요할 수 있음.
- 진짜 not found는 짧은 TTL로만 캐시하고, timeout/서버 실패는 캐시하지 않고 5초/15초 간격으로 재시도함.
- 오버레이는 현재 줄 1줄만 표시함.
- 가사 조회 중이라 현재 표시할 줄이 없어도 재생 중이면 오버레이 패널 자체는 유지됨.
- 오버레이 drag handle은 제거됐고, 패널 자체를 잡아 이동하는 방식으로 바뀜.
- 오버레이 패널은 보이는 자막 박스 기준으로 디스플레이 edge까지 붙일 수 있음.
- 오버레이 hover 시 이전 곡, 재생/일시정지, 다음 곡, 재생목록 버튼이 아이콘만 나타남.
- queue는 가사 패널과 별도 NSPanel로 분리되어 가사 패널을 밀지 않고 위로만 확장되며, SwiftUI 옵션과 AppKit `NSScrollView` 스크롤러 suppression을 함께 써서 스크롤바 없는 내부 스크롤을 지원함.
- 오버레이 위 우클릭 또는 control-click으로 preference panel을 열 수 있음.
- 우측 하단 resize grip은 제거됐고, 같은 크기 조절 기능은 preference panel의 `자막 크기` 슬라이더로 이동함.
- `최대 폭` 값은 preference 전용이고, `자막 크기`는 그 최대 폭 안에서 별도 스케일만 바꿈.
- 자막 배경은 반투명 black, 가사 폰트는 light weight로 표시함.
- 설정에서 항상 위, opacity preset/slider, 자막 크기, 폭, pause fade delay, sync offset을 조절함.
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

- LRCLIB에 곡 자체가 없으면 lyrics가 표시되지 않을 수 있음. plain lyrics만 있는 곡은 정확한 싱크가 아니라 곡 길이 기반 근사 줄 표시로 동작함.
- 처음 듣는 곡이고 로컬 캐시가 없으면 LRCLIB 서버 응답 시간만큼 첫 표시가 늦을 수 있음. 캐시와 프리패치는 반복/다음 곡 체감 시간을 줄이는 용도임.
- Liked Songs 5,000곡 규모에서는 첫 전체 캐시가 LRCLIB 응답 속도에 좌우됨. 현재는 완료 시간을 줄이기 위해 동시 32곡씩 병렬 조회함.
- Spotify API polling 기반이라 재생 위치는 주기적으로 보정되며, 완전한 push 실시간 이벤트는 아님.
- Spotify queue는 Spotify가 현재 계산한 다음 재생 항목 기준이라 셔플, 수동 queue, 라디오/자동재생 상태에 따라 “원래 플레이리스트 전체 순서”와 다를 수 있음.
- Spotify에는 queue의 n번째 항목으로 그대로 점프하는 전용 API가 없어, row 클릭은 선택 위치만큼 `next` 명령을 순차 실행하는 방식으로 동작함.
- Spotify Developer 앱이 Development mode라, 다른 Spotify 계정에서 쓰려면 Dashboard의 User Management에 계정을 추가해야 할 수 있음.
