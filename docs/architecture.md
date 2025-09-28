# 아키텍처 개요 (Kavita 연동)

## 시스템 구성
- **KavaReader (iOS)**: SwiftUI 기반 iPad 앱. 라이브러리 탐색, 시리즈 상세, 페이지 리더 UI를 제공한다.
- **KavaReader (iOS)**만 사용하고, 별도 어댑터 서버는 두지 않는다. 앱이 사용자의 Kavita 서버에 직접 연결한다.
- **Kavita 서버**: 공식 Kavita 패키지를 Docker 또는 Synology 패키지로 운영한다. 메타데이터 스캐닝과 이미지 스트리밍을 담당한다.

## 데이터 흐름
1. 사용자는 iOS 앱 `설정`에서 자신의 Kavita 서버 주소와 API 키를 입력한다.
2. `LibraryServiceFactory`가 입력 정보를 검증한 뒤 `KavitaLibraryService`를 구성한다.
3. 앱이 `/api/series/all`, `/api/series/{id}` 등 Kavita REST 엔드포인트를 직접 호출해 라이브러리와 시리즈 데이터를 가져온다.
4. 리더 화면에서는 `/api/reader/image`를 호출해 이미지를 받아 표시한다.

## 인증 전략
- iOS 앱은 사용자가 설정 화면에 입력한 API 키를 HTTP 헤더(`ApiKey`, `Authorization`)로 전달한다.
- API 키를 사용하지 않는 환경이라면, Kavita에서 허용하는 세션·쿠키 방식대로 직접 로그인 후 발급받은 토큰을 저장한다.

## 배포 고려사항
- 별도 어댑터 서버를 두지 않으므로, 사용자는 자신의 NAS 또는 서버에서 운영 중인 Kavita 인스턴스에 직접 접속한다.
- 네트워크 보안(https, 포트 포워딩 등)은 각자의 환경에 맞춰 Kavita 측에서 설정한다.

## 향후 작업
- 단일 사용자 환경을 전제로 하므로, 앱이 직접 Kavita API를 호출하도록 간소화된 구조를 유지
- Kavita API 응답을 기반으로 한 통합 테스트를 `tests/fixtures/kavita/*.json`에 수집
- iOS 앱에서 시리즈 상세/리더 UI를 완성하고, 이미지 스트리밍 로딩 상태/에러 처리를 보강

## 설계 결정 기록
- 2025-03-26: 개인용 만화 뷰어로 사용하려는 요구가 명확해짐에 따라, 별도의 Kavita Adapter 서버를 두지 않기로 결정했다. 사용자는 직접 자신의 Kavita 서버 주소와 API 키를 입력하고, 앱은 해당 REST API를 바로 호출한다. 추가 서버 운용 부담을 줄이고 설정을 단순화하기 위한 선택이다.
