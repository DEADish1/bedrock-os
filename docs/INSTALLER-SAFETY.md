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
- Open only the selected whole-disk target, never a partition or path supplied as free text.
- Refuse system, mounted, read-only, undersized, or non-removable media again after elevation.
- Stream writes with progress, flush all data, reread and hash the completed media, then safely eject when supported.
- Treat interruption, short writes, disappearing media, and verification mismatch as failures with recovery guidance.

## Protected helper boundary

The desktop package contains a separate `bedrock-media-writer` executable. It accepts only a bounded schema-1 request on standard input, requires a valid opaque session identity and a request no more than two minutes old, independently re-verifies the signed image, locates only a packaged platform scanner relative to its own executable, refreshes inventory, and repeats the complete target and confirmation checks. Unknown request fields, caller-provided scanner paths, relative image paths, oversized requests, and expired requests are rejected.

The helper currently stops after preflight. It does not open a physical target until signed package placement, OS-specific elevation, administrator verification, whole-device opening, exclusive access, flush/eject, and real-device acceptance tests are complete.
