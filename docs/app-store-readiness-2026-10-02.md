# Kava 앱스토어 출시 전 점검

점검일: 2026-10-02. 대상: 현재 작업 디렉터리의 iOS 앱 소스와 프로젝트 설정(미커밋 변경 포함).

**판정: 현재 상태로 제출하기 전에 아래 P1 항목을 해결해야 합니다.**

코드와 설정을 대상으로 한 정적 점검입니다. AGENTS.md에 따라 앱 실행, 컴파일, 테스트 빌드, Archive는 실행하지 않았습니다. App Store Connect 등록 내용과 배포 인증서도 확인하지 않았으므로 실제 배포 성공이나 심사 통과를 검증한 결과는 아닙니다. 기존 앱 코드는 수정하지 않았습니다.

## 출시 전 우선 수정

### 1. [소스 수정 완료 / Archive 확인 필요] 필수 개인정보 API 사용 선언

- `ios/KavaReader/KavaReader/PrivacyInfo.xcprivacy`를 추가했습니다.
- User Defaults: `NSPrivacyAccessedAPICategoryUserDefaults` / `CA92.1`. 앱 자체 설정과 읽기 기록을 `@AppStorage`, `UserDefaults`로 읽고 저장하는 용도입니다. 예: `Settings/KavitaServerSettingsView.swift:162`, `Reader/ReadingStatusStore.swift:21`.
- File Timestamp: `NSPrivacyAccessedAPICategoryFileTimestamp` / `C617.1`. `Reader/PagePreviewCache.swift:104`와 `:109`에서 앱 컨테이너의 미리보기 캐시 수정 시각을 읽고, 오래된 캐시부터 삭제하는 용도입니다.
- 사유 코드는 [Apple 공식 목록](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)의 앱 자체 User Defaults 및 앱 컨테이너 파일 접근 범위에 맞췄습니다.
- 파일은 앱 타깃에 연결된 Xcode 파일 시스템 동기화 그룹 안에 위치합니다. 프로젝트 파일에 별도 수동 참조를 추가할 필요가 없는 구성입니다. plist 구문 검사는 통과했으며, 실제 Release Archive의 `Products/Applications/KavaReader.app/PrivacyInfo.xcprivacy` 포함 여부와 Validate App 결과는 사용자 확인이 필요합니다.
- 이번 변경은 Required Reason API 사용 사유 선언입니다. App Store Connect의 App Privacy 데이터 수집 응답은 아래 데이터 흐름 점검에 따라 별도로 작성해야 합니다.

### 3. [P1] 서버 변경 시 이전 서버의 로그인 토큰 전송 가능

- `Settings/KavitaServerSettingsView.swift:624`는 JWT를 서버 구분 없이 `kavita_api_token`이라는 단일 Keychain 키로 저장합니다.
- `Library/KavitaLibraryService.swift:587`은 API Key가 비어 있으면 이 토큰을 현재 서버의 요청에 붙입니다.
- `Library/CoverImageView.swift:136`은 현재 API Key가 있어도 기존 Keychain JWT를 우선 사용합니다.
- 서버 변경 시 토큰을 지우거나 서버와 대조하는 호출은 확인되지 않았습니다.
- 재현 조건: 서버 A에서 계정 로그인 후 서버 B로 주소 변경. API Key가 없으면 목록 요청에 A의 토큰이 붙고, 표지 요청은 B의 API Key가 있어도 A의 JWT를 선택할 수 있습니다. 이는 인증 실패와 자격 증명 노출 문제입니다.
- 토큰을 서버 origin 및 서버의 경로·계정 범위에 귀속시키고, 다른 서버 요청에는 사용하지 않도록 해야 합니다. 서버 연결 해제와 자격 증명 삭제도 제공하는 것이 좋습니다.

### 4. [P1] 계정 로그인 토큰이 페이지 이미지 요청에 적용되지 않음

- 설정 화면은 사용자명·비밀번호 로그인을 제공합니다(`Settings/KavitaServerSettingsView.swift:96`, `:125`).
- JSON API 요청은 Keychain JWT를 Authorization 헤더로 사용할 수 있습니다.
- 페이지 이미지 URL은 API Key가 있을 때만 쿼리에 키를 붙입니다(`Library/KavitaLibraryService.swift:311`).
- 실제 이미지 다운로드는 `URLSessionPageImageFetcher.fetchImage`에서 `session.data(from: url)`로 수행하여 JWT 헤더를 추가하지 않습니다(`Reader/ReaderViewModel.swift:21`, `:345`). 페이지 미리보기도 같은 문제가 있습니다.
- 따라서 API Key 없이 JWT만 발급된 로그인에서는 목록 조회와 이미지 읽기의 인증 방식이 달라집니다. 세션 쿠키로 별도 인증되는 서버를 제외하면 이미지 요청이 401/403으로 실패할 수 있습니다.
- 이미지·미리보기까지 같은 인증 요청 생성 경로를 사용하거나, 이번 출시에서 계정 로그인 안내와 UI를 제거하고 API Key 연결만 지원해야 합니다. 계정 로그인 기능을 유지한다면 로그인 후 라이브러리 복원과 재실행까지 검증해야 합니다.

### 5. [P2] 비밀번호·API Key의 일반 설정 저장

- `Settings/KavitaServerSettingsView.swift:164`와 `:165`에서 비밀번호와 API Key를 `@AppStorage`로 저장합니다. `SecureField`는 화면 표시를 가릴 뿐 저장 위치를 보호하지 않습니다.
- API Key는 일반 TextField로 표시되고 자동 교정도 비활성화되어 있지 않습니다(`:139`).
- 비밀번호와 API Key를 Keychain으로 이전하고 기존 UserDefaults 값을 제거하는 마이그레이션이 필요합니다. 로그인 이후 비밀번호를 보관할 필요가 있는지도 결정해야 합니다.
- 서버 주소와 비밀 자격 증명의 저장 책임을 분리하되 기존 앱 전체에서 사용하는 서비스 식별자, 캐시 분리, SwiftUI 변경 감지 흐름은 함께 유지해야 합니다.

## 기능·품질 개선 항목

### 6. [P2] API 요청마다 JWT 재발급

- `Library/KavitaLibraryService.swift:582`는 API Key 모드에서 매 요청마다 `authenticateWithAPIKey()`를 호출합니다.
- 최초 목록 갱신도 여러 병렬 요청을 만들고, 메타데이터 색인과 진행률 조회·저장에서도 매번 인증 요청이 추가됩니다.
- NAS 지연과 인증 서버 부하를 늘리는 구조입니다. 서버·계정별 토큰 캐시, 동시에 시작된 인증 요청 합치기, 만료 또는 401 응답 시 갱신이 필요합니다. 성능 수치는 실행하지 않아 측정하지 않았습니다.

### 7. [P2 / 심사 위험] AniList 검색 결과의 성인 콘텐츠 필터 없음

- `Library/AniListMetadataService.swift:249`의 검색 요청과 `:257`의 직접 조회는 `isAdult` 조건이 없고 응답 모델에도 성인 여부가 없습니다.
- `Library/AniListConnectionSheet.swift:182`는 결과 표지를 즉시 표시합니다. 소설 제외 조건은 성인 콘텐츠 제한이 아닙니다.
- 이번 점검에서 실제 성인 표지가 노출되는지 검색·실행하지는 않았습니다. 그러나 현재 코드에는 이를 차단할 수단이 없습니다.
- 첫 출시에서는 AniList 검색과 직접 조회에 비성인 조건을 적용하고, 응답 측에서도 일관되게 제외하는 방식을 권장합니다. 연령 등급만으로 모든 콘텐츠가 허용되는 것은 아닙니다. [Apple 심사 가이드라인 1.1·1.2](https://developer.apple.com/app-store/review/guidelines/)

### 8. [P3] 영어 모드에서 파일 삭제 버튼 번역 누락

- `Library/LocalComicImportView.swift:121`의 `Button("삭제")`에 대응하는 영어 문자열 키가 없습니다. 영어 모드에서도 이 버튼은 한국어로 표시됩니다.
- 문자열 검사에서 나온 장르 별칭, 번역 사전의 한국어 값, Preview 예시는 오류 개수에 포함하지 않았습니다. 한국어 키가 일부 없어도 기본값이 한국어 원문이므로 이를 별도 결함으로 세지 않았습니다.

## 이번 출시 범위에서 제외

### 2. [보류 / 사용자 결정] 로컬 네트워크의 Kavita 서버 연결

- 사용자가 현재 로컬 네트워크의 Kavita 연결을 지원하지 않으므로 이번 출시 점검에서 제외하기로 결정했습니다. 출시 전 필수 수정 항목에 포함하지 않습니다.
- 여기서 로컬 연결은 같은 Wi-Fi의 IP 주소나 `.local` 주소로 Kavita API에 직접 접속하는 기능입니다. 파일 앱에서 CBZ·ZIP을 가져와 오프라인으로 읽는 기능은 계속 출시 범위에 포함됩니다. NAS의 SMB·WebDAV 직접 탐색 기능을 뜻하지 않습니다.
- 추후 로컬 Kavita 연결 지원 시 `NSLocalNetworkUsageDescription`과 한국어·영어 권한 안내를 추가하고, 지원 주소 범위에 맞는 ATS 설정 및 권한 거부·재허용을 실기기에서 확인합니다. [Apple 권한 문서](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription), [Apple ATS 문서](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)
- 현재 코드의 HTTP 주소 허용 여부는 변경하지 않았습니다. 외부 Kavita 연결에 HTTP도 지원할 계획이라면 그 주소 범위의 ATS 동작은 별도로 확인해야 합니다.

## 정상으로 확인한 정적 항목

- Xcode 프로젝트 파일과 한국어·영어 `Localizable.strings`: `plutil -lint` 통과.
- 번역 키: 한국어 314개, 영어 442개. 한국어 파일의 모든 키는 영어 파일에도 존재. 공통 키의 포맷 인자 타입 불일치 없음.
- AppIcon: 1024×1024 PNG, 알파 채널 없음. 이는 원본 자산 검사이며 Archive 자산 검증은 아님.
- `git diff --check`: 통과.
- iOS 앱 지원 플랫폼은 `iphoneos iphonesimulator`, 지원 기기는 iPhone·iPad, 최소 OS는 26.0.
- 앱 안에 개인정보 처리방침과 고객지원 메일 UI가 있음.
- 테스트 소스 파일 17개 존재. 실행 결과는 확인하지 않음.
- 로컬 파일 가져오기에는 security-scoped 접근과 파일 조정, 내용 해시 중복 검사, 압축 해제 크기 제한, CRC 검증이 구현되어 있음. 카탈로그 쓰기는 atomic 방식.
- 서버 카탈로그 저장 시 이미지 URL의 API Key를 제거하고, 표시할 때 다시 구성하는 설계가 있음.
- Git에 추적된 `cookies.txt`는 현재 쿠키 기록이 없는 헤더 파일임. 이번 검사에서 비밀 값은 출력하지 않았음. 향후 인증 쿠키를 기록하는 파일은 저장소 밖에서 관리하는 것이 좋음.

## App Store Connect에서 확인할 사항

아래는 저장소만으로 준비 여부를 판단할 수 없는 항목입니다.

- 공개 HTTPS 개인정보 처리방침 URL과 고객지원 URL. 앱 내부 화면과 이메일만으로 URL 필드를 대신할 수 없습니다. [Apple 제출 안내](https://developer.apple.com/app-store/review/)
- App Privacy 응답: 로컬 저장, 사용자가 지정한 Kavita 서버 전송, AniList 제목·ID 조회, 지원 이메일의 실제 데이터 흐름을 기준으로 판단. SDK가 없다는 이유만으로 모든 항목을 자동으로 “수집 없음” 처리하지 않기.
- 심사용 접속 가능한 Kavita 서버와 제한된 테스트 계정/API Key, 사용 허가가 있는 샘플 만화. 사용자 NAS만 연결 가능한 상태로는 심사자가 서버 기능을 검증할 수 없습니다. 연결 순서와 파일 가져오기 방법을 심사 메모에 제공. [Apple 심사 접근 요건](https://developer.apple.com/app-store/review/guidelines/)
- 지원 OS·기기 범위, 앱 이름, 스크린샷, CBZ·ZIP 및 Kavita 지원 설명. EPUB·CBR·7z·PDF·기기 간 동기화를 지원한다고 표시하지 않기.
- 현재 버전은 0.2, 빌드 번호는 1, 설치 제품명은 KavaReader. 출시 이름 Kava와 의도적으로 맞출지 확인. 이 값 자체가 제출 오류라는 뜻은 아닙니다.
- 현재 제출에는 iOS/iPadOS 26 SDK 이상 빌드가 필요합니다. 배포 대상 26.0 설정만으로 실제 사용 SDK를 증명하지는 않습니다. [2026년 SDK 제출 요건](https://developer.apple.com/news/?id=ueeok6yw)
- 배포 서명, 프로비저닝, 암호화 수출 관련 응답, 가격·배포 지역·연령 등급, Archive의 Validate App 결과.

## 사용자 실행 검증 목록

P1 수정 후 Xcode 테스트와 Release Archive를 수행하고, iPhone과 iPad에서 다음 흐름을 확인하세요.

- [ ] 새 설치, 서버 없이 파일 가져오기·읽기·앱 재실행.
- [ ] HTTPS API Key 연결과 OPDS 연결: 목록·표지·본문·즐겨찾기·진행률.
- [ ] 계정 로그인만으로 동일 기능 동작. 유지하지 않으면 관련 UI와 안내가 제거되어 있는지 확인.
- [ ] 서버 A → B 변경 시 A의 토큰/쿠키/읽기 상태가 B 요청에 섞이지 않는지 확인.
- [ ] 지원하는 외부 Kavita 서버의 리버스 프록시 하위 경로 연결.
- [ ] 첫 페이지·마지막 페이지, RTL·LTR·세로, 양면·첫 페이지 단독, 확대·축소, 이전·다음 권 이동.
- [ ] 읽다가 앱 전환·잠금·재실행 시 위치 복원. 서버 저장 실패와 다른 기기의 진행률 변경 상황 확인.
- [ ] 큰 이미지가 많은 권의 연속 읽기와 페이지 선택창에서 메모리·반응성 확인. 현재 리더는 이미지 개수 기준 캐시(10장)를 사용하므로 실제 메모리 검증 필요.
- [ ] ZIP 저장/Deflate, 손상·암호화·ZIP64·지원하지 않는 파일, 대용량 가져오기, 중단 후 재개, 용량 부족.
- [ ] 로컬 작품 이름 변경·합치기·삭제 후 재실행, 다른 작품 파일이 유지되는지 확인.
- [ ] 네트워크 끊김·서버 중단·잘못된 API Key·토큰 만료 후 오류 안내와 재시도.
- [ ] 한국어↔영어 변경, 고객지원 작성창과 메일 미설정 시 대체 동작, 개인정보 화면.
- [ ] iPhone 작은 화면, iPad 회전·창 크기 변경, 큰 글자·VoiceOver로 주요 버튼 접근.
- [ ] Archive의 생성 Info.plist, 포함된 PrivacyInfo.xcprivacy, 아이콘, 배포 SDK, 서명, Validate App.

권장 순서: 개인정보 선언 Archive 확인 → 서버별 인증 격리 → 이미지 인증 통일 → 비밀정보 저장 → 성인 검색 제한 → 인증 요청 최적화/번역 → 실기기/Archive 검증 → 제출 정보 작성. 로컬 네트워크 연결 설정은 추후 지원 시 진행합니다.
