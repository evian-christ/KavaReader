# Kava 외부 콘텐츠 이용 권한 확인

확인일: 2026-10-03. 현재 작업 폴더의 코드와 공개된 공식 정책을 대조한 결과입니다. 개별 계약이나 작품별 허가서를 확인한 것은 아닙니다.

사용자 확인: 현재 무료 출시, 추후 인앱 결제 도입 예정. App Store 스크린샷의 만화 콘텐츠는 식별할 수 없도록 블러 처리했다고 설명했습니다. 스크린샷 원본은 이번 검토에서 제공되지 않았습니다.

## 결과

- Kavita: 외부 모바일 앱의 API/OPDS 연동을 공식적으로 지원합니다. Kava의 사용자 지정 서버 연결은 해당 용도와 부합합니다. 서버 소프트웨어의 API 이용 가능 여부가 서버에 저장된 개별 만화의 저작권 허가를 대신하지는 않습니다.
- AniList: 비상업적 사용과 월매출 US$150 미만인 상용 앱의 무료 이용 조건은 확인했습니다. US$150 초과는 상용 라이선스가 필요하다고 명시합니다. 정확히 US$150인 경계는 약관이 명확히 설명하지 않으므로 그 전에 문의하는 편이 적절합니다. 무료라는 조건과 별도로 비보완적 경쟁 서비스 제한이 있습니다. Kava가 개인 서재용 보완 리더에 해당하는지는 서비스 측 확인이 남아 있습니다.
- Wikipedia: 정책을 준수하는 API 이용은 사전 개별 허가가 필요하지 않다고 명시합니다. Kava는 문서 본문이나 이미지를 재게시하지 않고 다른 언어 제목을 찾아 AniList 재검색에 사용합니다. User-Agent에 앱 식별자·문의 주소가 있고 429 응답도 처리합니다. 이 확인은 전체 정책 준수를 보증하거나 모든 문서·이미지의 재사용을 허가한다는 뜻은 아닙니다.
- App Store 홍보 이미지: 블러 처리 사실만으로 원본 작품의 사용 허가나 각 국가에서의 적법성을 확인할 수 없습니다. 직접 제작하거나 해당 홍보 용도로 이용 허가가 명확한 데모 콘텐츠를 실제 앱에 넣어 촬영하면 권리 근거를 더 명확히 할 수 있습니다.

현재 결과만으로 Content Rights의 “I have the necessary rights” 전체를 확인 완료로 처리할 수 없습니다. 제3자 콘텐츠를 실제로 표시하므로 이 불확실성을 이유로 “No”를 선택하는 것도 사실과 맞지 않습니다.

## 코드로 확인한 범위

- `Library/AniListMetadataService.swift`: GraphQL로 제목·장르·태그·작가·연도·표지 URL을 조회합니다. AniList 사용자 계정 연결이나 읽기 기록 동기화는 구현되어 있지 않습니다.
- `Library/AniListConnectionSheet.swift`: 작품 연결 후보에 AniList 표지를 표시하고 출처 및 원본 작품 링크를 제공합니다.
- `Library/LibraryPlusViewModel.swift`: 사용자의 서재에 있는 작품의 분류를 보완해 장르 탐색과 추천에 사용합니다. 자동 조회 성공 데이터의 유효 기간은 365일이며, 만료가 곧 디스크 삭제를 뜻하지는 않습니다.
- `Library/ManualSeriesMetadataStore.swift`, `Library/LocalSeriesMetadataStore.swift`: 사용자 지정 연결에는 자동 만료가 없습니다. AniList의 데이터 수집 제한과 이 저장 방식의 관계는 문의에 포함하는 것이 적절합니다. 이를 곧바로 약관 위반이라고 판정하지는 않았습니다.
- `Library/WikipediaTitleService.swift`: 한국어 제목의 영어 언어 링크만 조회해 재검색에 사용합니다.
- 앱 소스 폴더의 일반 이미지/만화 확장자 검색에서는 앱 아이콘 외에 배포용 만화 파일을 발견하지 못했습니다. 업로드된 스크린샷과 개인 NAS의 실제 자료는 검사하지 않았습니다.

## 공식 근거

1. [Kavita — Build with Kavita](https://www.kavitareader.com/): 외부 앱 및 도구의 API 연동 지원.
2. [AniList API Terms of Use](https://docs.anilist.co/guide/terms-of-use): 이용료, 경쟁 서비스, 대량 수집 및 명칭 조건. 공식 문서의 검색 색인에서 내용을 확인했으며 직접 페이지 열기는 403 응답이었습니다.
3. [AniList API Authentication](https://docs.anilist.co/guide/auth/): 공개 작품 데이터 조회에 사용자 인증이 필수는 아니라는 설명. 이는 모든 콘텐츠의 재사용 권한 보장은 아닙니다.
4. [Wikimedia API Usage Guidelines](https://foundation.wikimedia.org/wiki/Policy:Wikimedia_Foundation_API_Usage_Guidelines/en): User-Agent, 요청 제한 및 재게시 시 라이선스 준수 조건.
5. [Apple App Review Guidelines 5.2](https://developer.apple.com/app-store/review/guidelines/#intellectual-property): 제3자 콘텐츠·서비스 이용 권한 및 요청 시 증빙 요건.

## AniList 문의 초안 — 발송하지 않음

To: contact@anilist.co

Subject: API usage clarification for Kava, a personal comic reader

Hello AniList team,

I'm Chan Kim, developing Kava, an iPhone and iPad comic reader. It reads users' own CBZ/ZIP files and libraries on their self-hosted Kavita servers. It does not provide a hosted manga catalog or distribute manga.

Kava uses AniList metadata to enrich titles already in a user's collection, power genre browsing and recommendations within that collection, and let users manually match a title. Matching results display cover thumbnails and link to AniList. Reading progress and favorites are local or on the user's Kavita server; Kava has no AniList account synchronization.

Automatic metadata matches remain valid for 365 days, and manually selected metadata has no automatic expiry. Kava is currently free, with in-app purchases planned later.

Could you confirm whether this is permitted complementary use, whether the metadata caching and cover display are acceptable, and what licensing would be required for future monetization? Please also clarify whether any separate permissions or attribution are required for the cover images.

Thank you,
Chan Kim
