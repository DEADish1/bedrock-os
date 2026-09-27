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

## Image build integration

`os/scripts/build-image.sh` runs `build-installed-ui.sh` before live-build. The UI is built in a temporary source-only workspace using checksum-pinned Node 24.16.0 Linux x64 and `npm ci` from the repository lockfile; the existing working tree's node_modules is not changed. The Node archive checksum is pinned from the [official release checksums](https://nodejs.org/dist/v24.16.0/SHASUMS256.txt). Network access is required for this build step, not for serving the installed assets.

The generated `/usr/share/bedrock/management-ui/build-manifest.json` records the source commit, Node version, lockfile digest, and each asset's size and SHA-256. Staging refuses to overwrite an existing directory. The image build checks the staged manifest, extracts the UI from the ISO, verifies all files, and compares the embedded manifest with the source build's expected manifest. The raw-image builder uses the same live-build root filesystem. Generated staging and temporary toolchain files are removed after use; the UI remains inside the image. Linux build/ISO/reproducibility validation is pending for this integration.

`os/tests/test-installed-ui-manifest.py` exercises wrong source commits, corrupted contents/sizes, traversal, duplicate entries, unexpected files, and symlinks. The complete test requires Linux symlink support; local Windows verification passed for the real bundle, but the test suite stopped at the restricted symlink operation. Gateway configuration, browser rendering, and final npm license/SBOM qualification remain open.
