# Bedrock Installer desktop shell

This Tauri 2 shell packages the shared installer interface as native Windows, macOS, and Linux applications. Its bridge exposes only three typed commands:

- choose and cryptographically verify an image;
- list eligible removable targets;
- write a verified image after exact confirmation.

Live removable-drive discovery is connected to the bundled read-only Windows, macOS, and Linux adapters. Native image selection requires a supported Bedrock filename, strict manifest schema, exact size, streaming SHA-256 match, and a detached CMS signature chaining to the public certificate embedded at build time. Writing remains disabled. The shell has no general command runner, shell plugin, or unrestricted filesystem permission.

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
