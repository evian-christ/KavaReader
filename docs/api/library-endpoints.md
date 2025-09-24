# Library API Endpoints (Kavita 어댑터 기준)

Kava iPad 앱은 Synology NAS에서 동작하는 Kavita 서버에 직접 접근하지 않고, 가벼운 어댑터 서비스(향후 `server/kavita-adapter` 모듈로 구현 예정)를 통해 데이터를 조회합니다. 이 어댑터는 Kavita의 공식 REST API를 호출해 응답을 앱이 사용하는 `LibrarySectionsResponse` 구조로 변환합니다.

| 목적 | HTTP | 경로 | 설명 |
| ---- | ---- | ---- | ---- |
| 라이브러리 섹션 목록 | GET | `/api/library/sections` | Kavita 라이브러리/시리즈를 가져와 홈 섹션(최근 추가, 읽던 만화 등)으로 변환 |
| 작품 상세 | GET | `/api/library/series/:seriesId` | 지정된 시리즈 ID의 메타데이터, 챕터, Kavita 시리즈 URL 반환 |
| 페이지 이미지 | GET | `/api/library/series/:seriesId/chapter/:chapterId/page/:pageNumber` | Kavita 이미지 프록시. Kavita의 `Image/reader` 엔드포인트를 통과시켜 스트리밍 |

## 인증

- 어댑터는 `Authorization: Bearer <API_KEY>` 헤더를 요구합니다. 이 키는 Kavita 관리 화면에서 발급한 API 토큰을 어댑터 설정에 저장해 검증합니다.
- 어댑터 ↔ Kavita 통신은 Kavita 세션 토큰(`apiKey`)을 사용하며, 어댑터가 주기적으로 토큰을 재발급합니다.

## 응답 규격

모든 JSON 응답은 snake_case 필드명을 사용합니다. 대표 응답은 아래와 같습니다.

```json
{
  "sections": [
    {
      "id": "d5b2bf87-9c48-4eca-b5c9-1e3baf2f2fee",
      "title": "최근 추가",
      "items": [
        {
          "id": "f4efd3d2-4743-4f26-8ce3-6d66b4775550",
          "title": "은하 해적단",
          "author": "김하늘",
          "cover_color_hexes": ["#FF5F6D", "#FFC371"]
        }
      ]
    }
  ]
}
```

- `items[].id`는 Kavita의 `seriesId`를 UUID로 변환해 사용하며, 추가 호출 시 그대로 전달됩니다.
- `cover_color_hexes`는 Kavita 시리즈 태그/장르를 기반으로 어댑터가 계산한 대표 색상 배열입니다.

## 캐시와 조건부 요청

- 어댑터는 Kavita 응답의 `Last-Modified`/`ETag`를 읽어 동일 헤더를 그대로 전달합니다.
- 클라이언트는 `If-None-Match`와 `If-Modified-Since` 헤더를 설정해 프리페치/오프라인 모드를 구현할 수 있습니다.

## 에러 처리

- 인증 실패: `401 Unauthorized`
- Kavita 응답 오류: `502 Bad Gateway`와 함께 `message`, `kavita_status` 필드를 포함한 JSON 바디를 반환합니다.
- 기타 내부 오류: `500 Internal Server Error`와 함께 `trace_id` 필드 제공

필요 시 어댑터 구현이 확정되는 즉시 구체적인 필드/상태 코드를 본 문서에 추가하세요.
