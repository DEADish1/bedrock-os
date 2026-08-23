# Bedrock Installer desktop shell

This Tauri 2 shell packages the shared installer interface as native Windows, macOS, and Linux applications. Its bridge exposes only three typed commands:

- choose and cryptographically verify an image;
- list eligible removable targets;
- write a verified image after exact confirmation.

The native handlers currently fail closed with a clear message. They cannot write disks until the platform-specific protected service is connected and tested. The shell intentionally has no general command runner, shell plugin, or unrestricted filesystem permission.

The Rust response models use the same camel-case fields consumed by `ui/app.js`. GitHub checks the contract and compiles the shell independently on Windows, macOS, and Linux before it can be accepted.

## Development

Install the Rust toolchain and Tauri 2 prerequisites for the host platform, then run from `installer/desktop/src-tauri`:

```sh
cargo tauri dev
```

Use `cargo tauri build` to create the host platform's signed-package input. Release signing and notarization remain separate release-pipeline requirements.
