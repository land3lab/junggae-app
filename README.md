# 중개사무소 앱

중개사가 공짜로, 한 화면에서 쓰는 실전 도구 7종 (랜드3 연구소).

- `index.html` — 허브(7개 도구 메뉴)
- `lh.html` — ⑤ LH전세 도우미 (회원제, 등기부 PDF 판독 · 공시가격 자동 조회 · 고객 링크)
- 백엔드: Supabase(yangseongi 프로젝트 `lh` 스키마, 공개 RPC `lh_*`)
- 정적 사이트 — 빌드 없음. Vercel에서 Framework "Other"로 그대로 배포.
