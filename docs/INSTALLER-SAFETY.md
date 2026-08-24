# Bedrock Installer disk-safety contract

Disk selection and disk writing are separate trust boundaries. Enumeration is read-only and unprivileged. Writing is privileged, narrowly scoped, and receives the stable ID of one target that has just been revalidated.

## Inventory contract

Each platform adapter emits schema 1 JSON with a \`generated_at\` timestamp and \`targets\`. Every target contains:

- \`id\`: stable platform identifier, not a UI list position;
- \`path\`, \`model\`, and integer \`size_bytes\` shown to the user;
- \`removable\`, \`system\`, \`mounted\`, and \`read_only\` safety facts.

Raw serial numbers must not be displayed, logged, or stored. A one-way identifier may be derived locally when a platform lacks a safer stable ID.

## Selection rules

The common validator fails closed unless exactly one target matches the requested ID and it is removable, not the system disk, unmounted, writable, and at least 8 GiB. The user must type the complete confirmation phrase printed by the interface:

\`ERASE <model> — <path> — <capacity in bytes>\`

Immediately before writing, the privileged helper must enumerate again and require the same ID, path, model, and capacity. Any device arrival, removal, remount, resize, or identity change cancels the operation.

## Writer requirements

- Verify the signed release manifest and SHA-256 before requesting elevation.
- On Windows, replace the separately built helper's embedded manifest resource after linking; the main application keeps Tauri's unprivileged manifest and only the helper requests UAC.
- Open only the selected whole-disk target, never a partition or path supplied as free text.
- Refuse system, mounted, read-only, undersized, or non-removable media again after elevation.
- Stream writes with progress, flush all data, reread and hash the completed media, then safely eject when supported.
- Treat interruption, short writes, disappearing media, and verification mismatch as failures with recovery guidance.

## Protected helper boundary

The desktop package contains a separate `bedrock-media-writer` executable. It accepts only a bounded schema-1 request on standard input, requires a valid opaque session identity and a request no more than two minutes old, independently re-verifies the signed image, locates only a packaged platform scanner relative to its own executable, refreshes inventory, and repeats the complete target and confirmation checks. Unknown request fields, caller-provided scanner paths, relative image paths, oversized requests, and expired requests are rejected.

The desktop app now serializes one bounded request and starts the installed helper without a shell. Linux uses the exact `/usr/bin/pkexec /usr/bin/bedrock-media-writer` pair covered by the installed policy. Windows uses the native `runas` verb, waits on the returned process handle, and accepts only the helper's dedicated preflight-only exit code. Requests are base64-encoded only to preserve exact argument boundaries; they are not treated as secret or trusted until the elevated helper decodes and validates them.

On macOS 13+, the app registers the bundled launch daemon with `SMAppService` and connects through its privileged Mach service. The client requires the helper's fixed signing identifier and release Team ID; the listener independently requires the main app's fixed identifier and the same Team ID before its delegate sees a connection. Development builds without an injected Team ID reject the operation. Production staging requires the Team ID and explicitly signs the helper with its expected identifier before it enters the outer signed/notarized app bundle. User approval, final bundle signing, and notarization are still required before a packaged daemon can run.

Before reading a request, the helper now verifies its effective security identity. Linux and macOS require effective UID 0. Windows queries the current process access token and requires the operating system's `TokenIsElevated` flag. Missing, unreadable, or non-elevated identity information fails closed.

After preflight, the helper derives the device path only from the freshly validated inventory record. Linux opens a direct `/dev` block device with exclusive, no-follow flags, rejects a sysfs partition identity, and confirms the kernel-reported capacity. Windows opens only an exact `PhysicalDrive` path with no sharing and confirms its length through the disk-control API. macOS converts an exact whole `diskN` identity to its raw `rdiskN` device, takes an atomic exclusive lock, requires a character device, and confirms its block geometry. Any busy device, partition, symlink, identity uncertainty, or capacity change fails closed.

The native finalization layer enforces cache synchronization before any eject attempt. Linux requires both `fsync` and the block-device cache flush, then reports that the media is safe for manual removal because Linux has no universal USB/SD whole-disk eject operation. Windows requires `FlushFileBuffers` before attempting the storage-eject control. macOS requires `fsync`, full device synchronization, and the disk cache-synchronization control before attempting disk eject. A failed synchronization prevents eject; an unsupported eject is reported as safe manual removal rather than falsely reported as ejected.

The end-to-end write pipeline accepts one object that implements streaming read/write/seek plus finalization, preventing verification and finalization from being accidentally performed on different devices. Its virtual-device suite covers ISO and compressed-raw success, progress, reread identity, automatic eject, safe manual removal, checksum failure before finalization, and synchronization failure before eject. These tests exercise the complete sequence without opening host media.

Progress now has a versioned, session-bound, monotonic contract with bounded byte counts and explicit preparing, approval, writing, reread-verification, finalization, completion, and failure phases. The native pipeline reports real written and reread byte counts and the graphical shell no longer displays a fabricated fixed percentage. App-local preparation, approval, completion, and failure events are connected. On Linux, the exact policy-bound helper emits only bounded progress JSON through its inherited one-way standard-output pipe. On Windows, the app creates one local-only inbound named-pipe instance before native elevation, waits interruptibly for either connection or helper exit, and requires Windows to report that the connected client process ID is the exact elevated process returned by the approval launch. The helper accepts only the pipe name derived from its verified request session. Both app paths independently validate the expected session, signed total, next sequence, phase order, byte bounds, and line size before display. Invalid or missing progress is ignored and never cancels or alters the write; even a relayed complete phase is withheld until the helper exits successfully. The macOS privileged byte relay remains intentionally disconnected until its authenticated read-only XPC response stream is implemented.

Linux, Windows, and macOS now have native physical-device adapters that keep the same exclusive handle through streaming write, reread verification, cache synchronization, and finalization. Windows retains its zero-share `PhysicalDrive` handle through allow-removal and eject, while macOS retains its exclusively locked raw-disk descriptor through full synchronization and eject; each closes only when its adapter is dropped. These branches are omitted unless the build receives the exact `BEDROCK_ENABLE_PHYSICAL_WRITER=I_ACCEPT_REAL_DEVICE_DATA_LOSS` token and production trust mode. The macOS build additionally requires the release Team ID, and its authenticated XPC request permits a long-running write only in the gated build. Missing production trust or a different token fails the build or retains the non-writing path. Normal builds test that the gate is disabled. The protected protocol also distinguishes the existing preflight-only exit from a genuine completed write.

Ordinary builds close the exclusive probe immediately and still stop with the dedicated preflight-only exit code. No physical bytes are written. CI separately compiles—but never executes—the gated Linux, Windows, and macOS branches. All three connections are for controlled disposable-drive acceptance only until genuine evidence exists.

Release packaging uses a separate configuration overlay. Windows embeds `requireAdministrator` only in the writer helper while the main interface remains unprivileged. Debian and RPM packages install a polkit action bound to the exact `/usr/bin/bedrock-media-writer` path, requiring fresh active-session administrator authentication with no retained authorization. macOS 13+ packages place the helper and launch-daemon declaration inside the application bundle, apply the fixed helper signing identifier, and use SMAppService/XPC mutual peer requirements. The outer app still requires final Developer ID signing and notarization. The interface receives no sidecar or general shell permission.
