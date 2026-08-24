# Bedrock Installer desktop shell

This Tauri 2 shell packages the shared installer interface as native Windows, macOS, and Linux applications. Its bridge exposes only three typed commands:

- choose and cryptographically verify an image;
- list eligible removable targets;
- write a verified image after exact confirmation.

Live removable-drive discovery is connected to the bundled read-only Windows, macOS, and Linux adapters. Image selection and writing still fail closed with a clear message until their platform-specific protected services are connected and tested. The shell has no general command runner, shell plugin, or unrestricted filesystem permission.

The Rust response models use the same camel-case fields consumed by `ui/app.js`. GitHub checks the contract and compiles the shell independently on Windows, macOS, and Linux before it can be accepted.

The packaged application uses the official 512-pixel Bedrock app icon from the supplied brand kit.

## Development

Install the Rust toolchain and Tauri 2 prerequisites for the host platform, then run from `installer/desktop/src-tauri`:

```sh
cargo tauri dev
```

Use `cargo tauri build` to create the host platform's signed-package input. Release signing and notarization remain separate release-pipeline requirements.
