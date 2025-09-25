# Kavita API 통합 분석 및 진행 상황

## 문제 상황
- iOS 앱에서 Kavita 서버의 만화 목록이 표시되지 않음
- `/api/library/libraries` 엔드포인트는 작동하지만 series 관련 엔드포인트들이 JSON 대신 HTML 반환
- Paperback 및 Kavya 앱은 동일한 서버에서 정상 작동

## 핵심 발견 사항

### 1. SPA 라우팅 문제
- **문제**: Kavita의 SPA(Single Page Application) 라우팅이 거의 모든 API 엔드포인트를 인터셉트
- **증상**: API 요청에 대해 JSON 대신 HTML 웹페이지 반환
- **영향받는 엔드포인트**:
  - `/api/series*` (모든 series 관련 엔드포인트)
  - `/Plugin/authenticate` (인증 엔드포인트)
  - 기타 대부분의 API 엔드포인트

### 2. 성공한 앱들의 인증 방식
- **Paperback 설정**: 서버주소, API key, page size, username & password
- **Kavya (ACK72) 방식**: GitHub 분석 결과
  - API Key를 직접 헤더나 query parameter로 사용하지 않음
  - `/api/Plugin/authenticate` 엔드포인트로 API Key → Bearer JWT 변환
  - 모든 API 요청에 `Authorization: Bearer <token>` 헤더 사용

### 3. URL 경로 패턴 분석
- **Kavya 소스코드에서 발견된 엔드포인트들**:
  - `/Library/libraries` (Kavya 소스)
  - `/Series/all` (Kavya 소스)
  - `/Plugin/authenticate` (Kavya 소스)

- **실제 작동하는 엔드포인트 패턴**:
  - `/api/library/libraries` ✅ (유일하게 작동)
  - `/api/collection` ✅ (작동하지만 빈 배열 반환)

### 4. 브라우저 테스트 결과
사용자가 직접 테스트한 결과:
- `https://yjinsa.synology.me:12600/Library/libraries?apiKey=...` → HTML 웹페이지 반환
- `https://yjinsa.synology.me:12600/api/Library/libraries?apiKey=...` → 401 Unauthorized

## 구현한 해결 시도들

### 1단계: URL 파라미터 인코딩 문제 해결
- **문제**: Query parameter가 `?libraryId=1`이 아닌 `%3FlibraryId=1`로 인코딩됨
- **해결**: URLComponents 사용으로 올바른 URL 구성

### 2단계: Kavya 방식의 API 패턴 적용
- **시도**: `/api/` 접두사 제거하여 Kavya 소스코드와 일치시키기
- **결과**: 여전히 SPA 라우팅에 걸림

### 3단계: 인증 방식 변경
- **기존**: JWT 로그인 방식 (username/password)
- **변경**: API Key 방식 구현
- **시도한 방법들**:
  - X-API-Key 헤더 사용
  - Query parameter로 API Key 전달
  - API Key → Bearer JWT 변환 (Kavya 방식)

### 4단계: 설정 UI 개선
- API Key 입력 필드 추가: "API Key (선택사항)"
- 로그인 조건 수정: username/password 또는 API Key 둘 중 하나만 있으면 됨
- ContentView, SeriesDetailView에 API Key 전달 로직 추가

### 5단계: 헤더 최적화
- **기존**: `XMLHttpRequest`, `Cache-Control` 등 다수 헤더
- **변경**: `User-Agent: Paperback` 등 최소한의 헤더로 SPA 감지 회피 시도

## 현재 구현 상태

### 인증 플로우
```
1. 설정에서 API Key 입력
2. `/api/Plugin/authenticate?apiKey=...&pluginName=KavaReader` 호출
3. Bearer JWT 토큰 받기
4. `Authorization: Bearer <token>` 헤더로 API 요청
```

### 코드 변경 사항
- `makeRequest()` 함수를 `async`로 변경
- API Key → Bearer token 변환 로직 구현 (`authenticateWithAPIKey()`)
- JWT 토큰 캐싱 시스템 (키체인 저장)
- 모든 `makeRequest()` 호출부에 `await` 추가

## 남은 문제

### 1. `/api/Plugin/authenticate` 엔드포인트 이슈
- **현재 상황**: 여전히 HTML 반환 (SPA 인터셉트)
- **시도할 경로**:
  - `/api/Plugin/authenticate` (현재 시도 중)
  - POST vs GET 메서드 테스트
  - 헤더 조정

### 2. Series 엔드포인트 접근 불가
- 모든 `/api/series*` 엔드포인트가 HTML 반환
- `/api/Series/all`, `/api/Series/recently-updated-series` 등 모두 실패

## 다음 단계 계획

1. **인증 엔드포인트 해결**:
   - `/api/Plugin/authenticate` 경로 확인
   - HTTP 메서드 변경 (POST → GET)
   - 추가 헤더 조정

2. **대안 API 엔드포인트 탐색**:
   - 다른 작동하는 엔드포인트 찾기
   - OPDS 엔드포인트 활용 가능성 검토

3. **Reverse Proxy 설정 검토**:
   - 사용자 서버의 nginx/apache 설정이 API 경로를 차단하고 있을 가능성

4. **네트워크 디버깅**:
   - Wireshark/Charles Proxy로 Paperback과의 실제 통신 패턴 분석

## 중요한 교훈

1. **SPA 라우팅의 강력한 인터셉트**: 현대 웹 애플리케이션의 라우팅은 API 호출까지 가로챌 수 있음
2. **성공하는 앱의 정확한 패턴 분석 필요**: 소스코드 분석만으로는 부족, 실제 네트워크 트래픽 확인 필요
3. **인증 플로우의 복잡성**: 직접 API Key 사용이 아닌 토큰 교환 방식이 표준
4. **URL 경로의 미묘한 차이**: `/api/` 접두사 유무가 라우팅에 결정적 영향

## 참고 자료

- [ACK72/kavya-paperback GitHub](https://github.com/ACK72/kavya-paperback)
- [Kavita API 문서](https://www.kavitareader.com/docs/api/)
- [Paperback-iOS 조직](https://github.com/Paperback-iOS)

---

## 🎉 중대한 돌파구 (최종 업데이트 후)

### ✅ 성공한 것들:
- **API Key → Bearer JWT 인증**: `/api/Plugin/authenticate` 완벽 작동
- **라이브러리 API**: `/api/Library/libraries` JSON 응답 성공
- **Collection API**: `/api/Collection` 성공 (빈 데이터)
- **JWT 토큰 캐싱**: Bearer 토큰 재사용으로 성능 최적화

### 작동하는 엔드포인트:
```
✅ /api/Plugin/authenticate (API Key → JWT)
✅ /api/Library/libraries (라이브러리 정보)
✅ /api/Collection (컬렉션 목록)
❌ /api/Series/* (모든 series 엔드포인트 여전히 SPA 차단)
```

### 성공 로그 예시:
```
[KavitaLibraryService] Authentication response: {"username":"flflvm97","token":"eyJ..."}
[KavitaLibraryService] Successfully got Bearer token
GET https://yjinsa.synology.me:12600/api/Library/libraries
[fetchSections] JSON (pretty): [{"id":1,"name":"만화",...}]
```

---

## 🔍 최종 상태 (저녁)

### ✅ 완전히 해결된 부분:
- **API Key → Bearer JWT 인증**: 완벽 작동
- **라이브러리 정보 조회**: JSON 응답 성공
- **인증 토큰 캐싱**: 성능 최적화 완료

### ❌ 여전히 미해결:
- **모든 `/api/Series/*` 엔드포인트가 SPA 라우팅에 차단됨**
- 시도한 엔드포인트들:
  ```
  ❌ /api/Series/on-deck
  ❌ /api/Series/recently-updated
  ❌ /api/Series/newly-added
  ❌ /api/Series/recently-added
  ❌ /api/account/dashboard
  ❌ /api/Series/all
  ```

### 🔬 다음 단계:
1. **브라우저 Network 탭 분석**: Kavita 홈페이지에서 실제 API 호출 확인
2. **Paperback 네트워크 분석**: 실제 사용 엔드포인트 파악
3. **서버 설정 검토**: reverse proxy가 Series API를 차단하고 있을 가능성

---

## 🎉 **완전한 성공!** (최종 해결)

### ✅ 100% 완료된 기능들:
- **API Key → Bearer JWT 인증**: 완벽 작동 ✅
- **POST 방식 Series API**: 성공적으로 JSON 응답 받음 ✅
- **만화 목록 표시**: 앱에서 만화들이 정상적으로 나타남 ✅
- **다중 엔드포인트 지원**: 여러 API 엔드포인트에서 데이터 수집 ✅

### 🔑 핵심 돌파구: 브라우저 네트워크 분석

**결정적 발견**: 사용자의 브라우저 네트워크 탭 분석을 통해 정확한 API 패턴 발견
```
POST https://yjinsa.synology.me:12600/api/series/recently-updated-series
Content-Type: application/json
Content-Length: 2
Authorization: Bearer <token>
Body: {}
```

### 📊 성공한 엔드포인트들:

```
✅ /api/series/recently-updated-series (POST + {})
✅ /api/series/recently-added (POST + {})
✅ /api/series/all (POST + {})
❌ /api/series/newly-added (여전히 SPA 차단)
```

### 🔧 최종 성공 구현:

#### 1. POST 방식 + Empty JSON Body
```swift
let emptyJsonBody = "{}".data(using: .utf8)!
let request = try await makeRequest(path: endpoint, method: "POST", body: emptyJsonBody)
```

#### 2. 실제 API 구조에 맞는 DTO 생성

**KavitaRecentlyUpdatedSeriesDTO** (recently-updated-series용):
```json
{
  "seriesId": 454,
  "seriesName": "그리스 로마 신화",
  "created": "2025-09-18T00:00:05.0541565"
}
```

**KavitaFullSeriesDTO** (recently-added/all용):
```json
{
  "id": 456,
  "name": "짱뚱이의 시골생활",
  "primaryColor": "#92D1F0",
  "secondaryColor": "#41372E",
  "pages": 178
}
```

#### 3. 동적 디코딩 로직
```swift
if endpoint.contains("recently-updated") {
    // 간단한 구조 사용
    decode([KavitaRecentlyUpdatedSeriesDTO].self)
} else {
    // 풀 구조 사용
    decode([KavitaFullSeriesDTO].self)
}
```

### 📈 최종 결과:
- **"그리스 로마 신화"**, **"짱뚱이의 시골생활"**, **"100억의 사나이"** 등 실제 만화 데이터 표시
- **Recently Added** 및 **All Series** 섹션으로 구성
- **실제 커버 색상** 사용 (primaryColor/secondaryColor)
- **중복 제거** 및 **에러 처리** 완료

---

## 📝 중요한 교훈들

### 1. SPA 라우팅 극복 방법
- **HTTP 메서드가 핵심**: GET → POST 변경으로 SPA 차단 우회
- **Request Body 중요**: 빈 JSON 객체 `{}`가 필요
- **엔드포인트별 차이**: 같은 서버에서도 엔드포인트마다 다른 동작

### 2. 브라우저 네트워크 분석의 중요성
- **소스코드 분석만으로는 한계**: 실제 네트워크 트래픽이 정답
- **개발자 도구가 최고의 도구**: Headers, Method, Body 모든 정보 확인 가능
- **기존 작동 앱 분석**: Paperback, Kavya 등 성공 사례 참조

### 3. API 구조의 다양성
- **엔드포인트별 다른 JSON 구조**: 하나의 DTO로 모든 걸 처리할 수 없음
- **필드 가용성 차이**: author, coverURL 등이 없는 엔드포인트들
- **동적 처리 필요**: 엔드포인트에 따른 분기 로직 구현

### 4. 실전 디버깅 접근법
1. **인증 먼저**: Bearer JWT 토큰이 올바른지 확인
2. **네트워크 로그**: 실제 요청/응답 확인
3. **작동하는 앱 분석**: 같은 서버에서 작동하는 다른 앱 참조
4. **브라우저 비교**: 웹에서의 실제 API 호출 패턴 확인
5. **단계별 접근**: 하나씩 해결해나가기

---

## 🏆 최종 상태

**날짜**: 2025년 9월 25일 늦은 저녁
**진행률**: **100% 완료** 🎉
**상태**: **만화 목록 정상 표시, 모든 핵심 기능 작동**

### 작동하는 기능들:
- ✅ API Key 인증
- ✅ Bearer JWT 토큰 변환
- ✅ POST 방식 Series API 호출
- ✅ 만화 목록 로딩 및 표시
- ✅ 다중 섹션 구성 (Recently Added, All Series)
- ✅ 실제 커버 색상 적용
- ✅ 에러 처리 및 fallback

**결론**: SPA 라우팅 차단 문제를 HTTP 메서드 변경(GET→POST)과 적절한 Request Body로 완전히 해결했습니다. 브라우저 네트워크 분석이 결정적인 해결책을 제공했습니다.