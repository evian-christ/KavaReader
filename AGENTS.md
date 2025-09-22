# Repository Guidelines

## Project Structure & Module Organization
- 백엔드 확장은 `server/` 하위에 배치하며, 예시는 `server/komga-extension`과 API 스키마가 담긴 `server/schema/`입니다.
- SwiftUI iPad 앱은 `ios/KavaReader/`에 위치하고, 기능별 폴더(`Library/`, `Reader/`, `Settings/`)와 공용 리소스(`ios/KavaReader/Shared/`)를 유지합니다.
- 문서는 `docs/`에 정리하고, 스트리밍 흐름이나 캐시 전략이 바뀌면 `docs/architecture.md`를 업데이트합니다.
- Dockerfile, 리버스 프록시 템플릿, CI 스크립트 등 배포 관련 파일은 `infra/`에 모아 Synology 배포를 재현 가능하게 만듭니다.

## Build, Test, and Development Commands
- 백엔드 실행: `cd server/komga-extension && ./gradlew bootRun`으로 커스터마이즈된 Komga를 기동합니다.
- 백엔드 빌드: `./gradlew build`가 배포용 JAR을 생성합니다.
- iPad 앱 빌드: `cd ios/KavaReader && xcodebuild -scheme KavaReader -destination 'platform=iOS Simulator,name=iPad mini (6th generation)' clean build`로 최신 SDK에 맞춰 컴파일을 확인합니다.
- 로컬 스택: `docker compose -f infra/docker-compose.yml up --build`로 Synology 환경과 유사한 리버스 프록시 및 TLS 스텁을 구성합니다.

## Coding Style & Naming Conventions
- 백엔드 코드는 Kotlin 공식 스타일(2스페이스 들여쓰기)을 사용하고, 커밋 전 `./gradlew ktlintFormat`을 실행합니다.
- Swift 코드는 SwiftFormat 기본(4스페이스 들여쓰기)을 따르며 `swiftformat .`으로 포맷을 정리합니다.
- 모듈명은 역할을 드러내도록 작성하고(`LibraryGridViewModel`, `PageStreamController`), JSON 필드는 퍼블릭 API와 일관되게 snake_case를 유지합니다.
- 에셋은 도메인 접두사(`lib_`, `reader_`)를 붙여 충돌을 방지합니다.

## Testing Guidelines
- 백엔드 테스트는 `server/komga-extension/src/test`에 위치하며 `./gradlew test jacocoTestReport`로 실행하고 스트리밍 핸들러 커버리지는 80% 이상으로 유지합니다.
- iOS UI·스냅샷 테스트는 `ios/KavaReaderTests/`, `ios/KavaReaderSnapshotTests/`에 두고 `xcodebuild test -scheme KavaReader -destination 'platform=iOS Simulator,name=iPad mini (6th generation)'`로 확인합니다.
- NAS 응답은 가능하면 `tests/fixtures/`에 저장된 목 데이터를 사용해 재현합니다.

## Commit & Pull Request Guidelines
- 커밋 메시지는 Conventional Commits 형식을 따르며 스코프는 모듈로 지정합니다(`feat(server): add epub extractor`).
- PR은 변경 요약, 수행한 테스트, 연결된 이슈, UI 변경 시 스크린샷 또는 영상을 포함합니다.
- 변경 사항은 400라인 이내로 유지하고 모듈 간 영향이 크면 사전에 리뷰어와 조율합니다.
- 스키마·캐시 키·API 계약이 변하면 PR 본문에 마이그레이션 노트를 남깁니다.

## 에이전트 운영 지침
- 깃 커밋 및 푸시는 사용자가 명시적으로 요청했을 때만 수행합니다.
- 앱 실행과 수동 테스트는 사용자가 직접 수행하므로, 관련 확인 단계는 안내만 제공하고 실행하지 않습니다.
