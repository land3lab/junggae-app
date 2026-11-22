# 중개사무소 앱

중개사가 공짜로, 한 화면에서 쓰는 실전 도구 7종 (랜드3 연구소).

- `index.html` — 탭형 대시보드(홈 요약 + 도구 탭, 각 도구는 `?embed=1`로 iframe에 표시). 새 도구는 `TOOLS` 배열에 page·state만 추가
- `lh.html` — ⑤ LH 전세임대 사전점검 신호등
- `dabang.html` — ② 다방광고 원클릭 (기기 저장, 주소→건축물대장 자동조회 `junggae_building`)
- `land.html` — ④ 토지 얼마나 해요? (토지특성·공시지가 `sise_land`, 토지 실거래 `sise_trades`, 키 미등록 시 국토부 CSV 업로드)
- `bid.html` — ⑦ 경매 입찰서류 자동작성 (새 기일입찰표 2026.11.2 양식 기준, 위임장·준비 확인서, 자릿수 대조판·이중입력 검사, 서버 없음·기기 저장 `bid.draft`/`bid.history`)
- `gongsil.html` — ⑥ 공실클럽(RSA 동문 전용): 공실 등록·지도(Leaflet/OSM)·문의 일지·14일 신선도, RPC `gs_*`, 동문 확인은 `lh.rsa_roster`(휴대폰 sha256 앞 40자 + 기수·권역) 대조, 미등록자는 관리자 승인. SQL: `sql/gongsil.sql`
- 백엔드: Supabase(yangseongi 프로젝트 `lh` 스키마, 공개 RPC `lh_*`·`sise_*`·`junggae_*`, 공용 로그인)
- 정적 사이트 — 빌드 없음. Vercel에서 Framework "Other"로 그대로 배포.
