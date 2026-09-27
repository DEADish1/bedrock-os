# Installed management UI

The hosted preview build remains `npm run build`. The OS-oriented entry uses the same `app/page.tsx` client component and `app/globals.css`, but has a separate static build with no Cloudflare/Sites runtime or server-side rendering requirement.

```
npm ci
npm run build:installed-ui
npm run test:installed-ui
npm run typecheck:installed-ui
```

Output is `dist/management-ui/`: HTML, hashed JavaScript/CSS, the lazily loaded noVNC console bundle, and public branding assets. The installed entry uses system font fallbacks and does not download fonts at runtime. Asset checks verify local references, required files, the guest-console chunk, and absence of source maps. They are not browser-rendering or API integration tests.

Do not expose this directory as an unauthenticated substitute for a management gateway. The UI already uses same-origin `/api/v1` requests; the packaged backend currently serves a Unix socket. Checklist 0.6.3 still requires OS image packaging, an HTTP(S)/WebSocket gateway, explicit TLS/trust and local access policy, authentication, origin/CSRF enforcement, limits/timeouts, service lifecycle integration, and clean-installed-server/browser acceptance. No gateway or LAN listener is enabled by this build command.

The installed TypeScript check covers the shared UI, its noVNC declaration, the browser entry, and its build configuration. It does not replace repository-wide checking: on 2026-09-27, `npx tsc --noEmit` reported existing browser-test type errors in `tests/e2e/management.spec.ts` (Playwright Page compatibility at line 156 and narrowed request fields at lines 266-268). These remain open under repeatable management CI, 0.6.9.
