// 설치 가능하게 하기 위한 최소 서비스워커 — 캐시하지 않음(항상 최신 화면)
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", e => e.waitUntil(self.clients.claim()));
self.addEventListener("fetch", () => {});
