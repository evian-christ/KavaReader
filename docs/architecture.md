# 아키텍처 개요 (Kavita 연동)

## 시스템 구성
- **KavaReader (iOS)**: SwiftUI 기반 iPad 앱. 라이브러리 탐색, 시리즈 상세, 페이지 리더 UI를 제공한다.
- **Kavita Adapter 서비스**: NAS 내 Docker 컨테이너로 배포되는 경량 백엔드(`server/kavita-adapter` 예정). Kavita REST API와 인증을 담당하고, 응답을 앱 전용 포맷으로 정규화한다.
- **Kavita 서버**: 공식 Kavita 패키지를 Docker 또는 Synology 패키지로 운영한다. 메타데이터 스캐닝과 이미지 스트리밍을 담당한다.

## 데이터 흐름
1. 사용자는 iOS 앱 `설정`에서 Kavita Adapter 주소와 API 키를 입력한다.
2. `LibraryServiceFactory`가 입력 정보를 검증한 뒤 `KavitaLibraryService`를 구성한다.
3. 앱이 `/api/library/sections` 요청을 보내면 Adapter는 내부적으로 다음을 수행한다.
   - Kavita API 토큰을 확보 (`POST /api/Account/Login` 또는 API Key 교환)
   - `GET /api/Library` 및 `GET /api/Series/RecentlyUpdated` 등 Kavita 엔드포인트를 호출
   - 결과를 `LibrarySectionsResponse` 구조로 변환 후 `ETag`/`Last-Modified` 헤더와 함께 응답
4. 사용자가 특정 시리즈를 열면 `/api/library/series/:seriesId`를 호출하여 챕터 메타데이터를 조회하고, 페이지 뷰어에서 `/api/library/series/:seriesId/chapter/:chapterId/page/:n` 경로를 통해 이미지를 가져온다.

## 인증 전략
- iOS 앱 ↔ Adapter: Bearer 토큰 기반. 사용자가 설정에 입력한 API 키가 헤더로 전달된다.
- Adapter ↔ Kavita: Kavita의 사용자 API Key 또는 세션 토큰을 사용한다. 토큰 만료를 대비해 어댑터에서 자동 갱신 로직을 구현한다.

## 배포 고려사항
- `infra/docker-compose.yml`에 Adapter와 Kavita 컨테이너를 정의하고, 리버스 프록시(TLS 포함) 설정을 추가한다.
- Synology DSM의 리버스 프록시 기능을 사용해 외부에서는 `https://reader.example.com` → Adapter → Kavita 순으로 접근하도록 구성한다.
- 캐시 및 썸네일 저장소는 NAS 볼륨에 마운트하여 데이터 유실을 방지한다.

## 향후 작업
- Adapter 초기 구현(`server/kavita-adapter`) 추가 및 Gradle/Node 등 런타임 결정
- Kavita API 응답을 기반으로 한 통합 테스트를 `tests/fixtures/kavita/*.json`에 수집
- iOS 앱에서 시리즈 상세/리더 UI를 완성하고, 이미지 스트리밍 로딩 상태/에러 처리를 보강
