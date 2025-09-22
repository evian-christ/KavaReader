# Library API Endpoints (초안)

| 목적 | HTTP | 경로 | 설명 |
| ---- | ---- | ---- | ---- |
| 라이브러리 섹션 목록 | GET | `/api/library` | 작품 목록 및 섹션 구성 반환 |
| 작품 상세 | GET | `/api/book/:id` | 챕터, 메타데이터 제공 |
| 페이지 이미지 | GET | `/api/book/:id/page/:n` | 주어진 페이지 이미지 스트리밍 |

- 인증: `Authorization: Bearer <API_KEY>` 헤더 사용 (API 키가 비어 있으면 헤더 없음)
- 응답: `application/json` (이미지 스트리밍 제외)
- 캐시 헤더: `ETag`/`Last-Modified`를 활용해 앱 프리로드와 동기화 예정

이 문서는 NetworkLibraryService 구현 시 참고용 초안입니다. 실제 백엔드 구현이 확정되면 업데이트하세요.
