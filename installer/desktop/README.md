# Bedrock Installer desktop shell

This Tauri 2 shell packages the shared installer interface as native Windows, macOS, and Linux applications. Its bridge exposes only three typed commands:

- choose and cryptographically verify an image;
- list eligible removable targets;
- write a verified image after exact confirmation.

Live removable-drive discovery is connected to the bundled read-only Windows, macOS, and Linux adapters. Native image selection requires a supported Bedrock filename, strict manifest schema, exact size, streaming SHA-256 match, and a detached CMS signature chaining to the public certificate embedded at build time. The native layer retains the trusted path and exposes only an opaque verification-session ID. A write request repeats signature and checksum verification, refreshes the drive list, and requires the exact current erase phrase and adequate capacity. Writing remains disabled after those checks. The shell has no general command runner, shell plugin, or unrestricted filesystem permission.

The native media engine is implemented and tested for ISO streams and compressed raw images. It enforces the signed expanded size, emits progress, flushes the target, rereads the written range, and verifies the signed SHA-256. The finalization layer then requires platform cache synchronization before attempting eject and returns an explicit automatic-eject or safe-manual-removal result. The elevated helper can probe an inventory-derived whole device, but it closes the handle without connecting either layer; physical writing remains disabled.

A separate `bedrock-media-writer` executable now owns the protected-helper preflight. Before reading any request it requires effective UID 0 on Unix/macOS or an elevated Windows process token. It then reads one small, strict, time-limited request, independently re-verifies the release, finds only a packaged platform scanner relative to itself, refreshes drive inventory, and repeats the exact selection checks. Linux launches the exact policy-bound helper through `pkexec`; Windows invokes the helper directly with native `runas`; macOS 13+ registers the launch daemon through SMAppService and exchanges the bounded request over a privileged XPC connection with mutual signing-identifier and Team-ID requirements. Every platform still exits before opening the drive.

`scripts/prepare-release-sidecar.mjs` compiles that helper separately, applies the helper-only UAC manifest to the finished Windows executable, names it with Rust's target triple, and proves the staged copy matches the compiled SHA-256. Applying the Windows manifest after linking avoids conflicting with Tauri's unprivileged main-application manifest. On macOS production builds it also requires the Apple Team ID and signing identity, then signs the helper with its fixed XPC identifier and hardened runtime before staging. Production preparation requires both the production-trust flag and a readable release certificate; development staging must be explicitly requested. `tauri.release.conf.json` is a release-only overlay that bundles the helper, installs the exact Linux polkit policy, places the macOS 13+ launch-daemon declaration inside the app bundle, and leaves the interface without shell-plugin permission.

The Rust response models use the same camel-case fields consumed by `ui/app.js`. GitHub checks the contract and compiles the shell independently on Windows, macOS, and Linux before it can be accepted.

The packaged application uses the official 512-pixel Bedrock app icon from the supplied brand kit.

## Development

Install the Rust toolchain and Tauri 2 prerequisites for the host platform, then run from `installer/desktop/src-tauri`:

```sh
cargo tauri dev
```

Use `cargo tauri build` to create the host platform's signed-package input. Release signing and notarization remain separate release-pipeline requirements.

Production packages must fail their build unless a protected release pipeline injects the public trust certificate:

```sh
BEDROCK_REQUIRE_PRODUCTION_TRUST=1 \
BEDROCK_INSTALLER_TRUST_CERT=/protected/public/bedrock-release.pem \
cargo tauri build
```

Only the public certificate is embedded. Its private signing key must remain offline or inside an approved signing service and must never enter the repository or installer build workspace.
