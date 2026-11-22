# 중개사무소 앱

중개사가 공짜로, 한 화면에서 쓰는 실전 도구 7종 (랜드3 연구소).

- `index.html` — 탭형 대시보드(홈 요약 + 도구 탭, 각 도구는 `?embed=1`로 iframe에 표시). 새 도구는 `TOOLS` 배열에 page·state만 추가
- `lh.html` — ⑤ LH 전세임대 사전점검 신호등
- `dabang.html` — ② 다방광고 원클릭 (기기 저장, 주소→건축물대장 자동조회 `junggae_building`)
- `land.html` — ④ 토지 얼마나 해요? (토지특성·공시지가 `sise_land`, 토지 실거래 `sise_trades`, 키 미등록 시 국토부 CSV 업로드)
- `bid.html` — ⑦ 경매 입찰서류 자동작성 (새 기일입찰표 2026.11.2 양식 기준, 위임장·준비 확인서, 자릿수 대조판·이중입력 검사, 서버 없음·기기 저장 `bid.draft`/`bid.history`)
- `gongsil.html` — ⑥ 공실클럽(RSA 동문 전용): 공실 등록·지도(Leaflet/OSM)·문의 일지·14일 신선도, RPC `gs_*`, 동문 확인은 `lh.rsa_roster`(휴대폰 sha256 앞 40자 + 기수·권역) 대조, 미등록자는 관리자 승인. SQL: `sql/gongsil.sql`
- `shorts.html` — ③ AI쇼츠 만들기: ② 매물장(`d1c.listings`·IndexedDB `d1c` 사진) 또는 직접 입력 → 훅·본문·마무리 대본(금지어 검사) → 내 목소리 녹음(선택) → 캔버스 720×1280 렌더 + MediaRecorder(MP4 우선, 안 되면 WebM) → 4개 확인 후 승인 → 공유(유튜브 앱)/저장 + 제목·설명(표시사항 포함)·태그. 서버 없음, 기록 `sh.history`(② 거래완료 시 내림 알림)
- `land3.css` + `img/` — 랜드3 연구소 공통 디자인(명함 로고: 주황 #F77235·차콜 #23292B). 모든 화면이 `<style>` 뒤에 불러와 색 변수·머리글만 덮어씀
- 백엔드: Supabase(yangseongi 프로젝트 `lh` 스키마, 공개 RPC `lh_*`·`sise_*`·`junggae_*`, 공용 로그인)
- 정적 사이트 — 빌드 없음. Vercel에서 Framework "Other"로 그대로 배포.
