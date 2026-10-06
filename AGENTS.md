# 저장소 안내

## 프로젝트 구조

- iOS 앱은 `ios/KavaReader/`에 있습니다. `Library/`, `Reader/`, `Settings/`, `Models/`, `Utils/`로 나뉜 SwiftUI 앱이며 현재 서버 연동은 Kavita 전용입니다.
- 앱 테스트는 `ios/KavaReader/KavaReaderTests/`에 있습니다.
- Kavita API 문서와 앱 구조 설명은 `docs/`에 둡니다.
- `server/`와 `infra/`에는 현재 안내 문서만 있습니다. 백엔드, Docker Compose, Synology 배포 스크립트가 구현되어 있다고 가정하지 않습니다.
- Kavita API 샘플 응답을 추가할 때는 비밀정보를 제거한 fixture만 `tests/fixtures/`에 둡니다.

## 개발 명령

- iOS 앱 빌드: `cd ios/KavaReader && xcodebuild -scheme KavaReader -destination 'platform=iOS Simulator,name=iPad mini (6th generation)' build`
- iOS 테스트: `cd ios/KavaReader && xcodebuild test -scheme KavaReader -destination 'platform=iOS Simulator,name=iPad mini (6th generation)'`
- 현재 서버·인프라용 Gradle 또는 Docker Compose 명령은 없습니다.

## 코드 스타일

- Swift 코드는 저장소의 `.swiftformat` 설정을 따릅니다.
- 기능별 파일과 기존 MVVM·서비스 프로토콜 구조를 유지합니다.
- Kavita API 요청이나 이미지 캐시 흐름이 바뀌면 `docs/architecture.md`를 함께 갱신합니다.
- 앱의 새 버튼은 기본적으로 Apple의 Liquid Glass 스타일을 사용합니다. `Utils/AppGlassButton.swift`의 공통 구성을 우선 사용하고, 기존 버튼을 교체할 때는 정해진 크기를 유지합니다.
- 새로 추가하는 사용자 표시 문구는 한국어와 영어 번역을 함께 제공합니다. 기본 언어는 한국어이며 앱 안의 언어 설정에서 전환합니다.

## 테스트

- NAS 연결 응답에 의존하지 않도록 가능한 경우 `URLSession` 주입과 목 응답을 사용합니다.
- 실제 서버 응답을 fixture로 추가할 때 URL, 계정 정보, API Key, JWT, 쿠키를 반드시 제거합니다.
- 빌드·테스트 실행 여부와 결과를 보고할 때 실제 실행 결과와 문서상 명령을 구분합니다.

## 작업 운영

- Git 커밋과 푸시는 사용자가 명시적으로 요청한 경우에만 합니다.
- 앱 실행 및 수동 테스트는 사용자가 수행하므로, 필요한 경우 확인 방법을 안내합니다.
- 컴파일 및 테스트 빌드도 사용자가 직접 수행합니다. 에이전트는 빌드를 실행하거나 실행 승인을 요청하지 않습니다.
- 사용자에게는 한국어로 설명하고 전문 용어는 필요한 만큼만 사용합니다.
