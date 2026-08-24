# Bedrock on-server installation contract

The live Bedrock environment will install to one explicitly selected internal system disk. NAS and VM storage remain separate and must never be silently reused as the operating-system target.

## Safe planning stage

The read-only Linux inventory marks the disk containing `/`, `/run/live/medium`, or Debian's alternate live-media mount as the protected running source. If that source cannot be identified, every disk remains protected. `os/installer/validate-install-target.sh` accepts exactly one inventory identity only when the target:

- is a whole Linux `/dev` disk identity from fresh inventory;
- is not the running system or live installation media;
- is internal rather than removable;
- has no mounted filesystems and is not read-only;
- is at least the 32 GiB minimum declared by `os/layout/bedrock-amd64.json`; and
- matches the complete typed phrase `INSTALL BEDROCK — <model> — <path> — <bytes>`.

`os/installer/create-install-plan.sh` then produces a review-only JSON plan. The plan binds the selected inventory record to the checksum and complete partition summary of the canonical Bedrock layout. It explicitly states that existing data will not be preserved and remains `ready_for_writer: false`.

## Required protected writer

The eventual privileged installer must obtain fresh inventory, match the same ID, path, model, and capacity, repeat every eligibility rule, exclusively open the inventory-derived whole disk, and recheck capacity before any destructive action. It must consume only signed components packaged in the booted Bedrock image.

The protected writer must create GPT and the canonical EFI, A/B verified-root, verity, signature, and growing state partitions; install signed boot artifacts; flush; reread and verify every fixed component; validate the final GPT; and report success only after synchronization. Interruption or any mismatch leaves the installation incomplete and requires restarting from the beginning.

This checkpoint implements only selection validation and a reviewable plan. It does not open or modify a disk, and it does not complete the v0.3 on-server installation checklist item.

## Disposable write simulation

`os/installer/simulate-install-image.sh` exercises the next installation stage only against a regular file directly inside a declared temporary directory. It requires explicit test mode and refuses block devices. The simulator verifies the source checksum and GPT, writes and rereads the planned image, relocates the backup GPT to the simulated disk end, expands partition 8 while preserving its identity and type, grows and checks its ext4 filesystem, and validates the final eight-partition structure.

CI uses a reduced-size layout with the same eight roles and standard partition type GUIDs. It proves successful installation, fixed-system-content preservation, state growth, interruption rejection, corruption rejection, and target-directory confinement without touching host media. This is evidence for the write engine, not physical-installation acceptance.

## Protected request preflight

`create-protected-install-request.sh` converts an approved review plan into a bounded schema-1 request containing a fresh UUID, two-minute timestamp, fixed packaged artifact name, plan/layout checksums, exact target ID and snapshot, and the complete confirmation phrase. It cannot carry a caller-selected image path, package directory, layout path, inventory path, or device path outside that exact target snapshot.

`preflight-protected-install.sh` rejects unknown fields, oversized/stale/future requests, invalid sessions, artifact-name changes, altered layouts, changed target identity or capacity, newly mounted targets, bad packaged checksums, and incompatible image sizes. In normal operation it uses the fixed live-media package directory, canonical layout, current clock, and a fresh result from the packaged Linux inventory adapter. Test substitutions require explicit test mode. Even after every check passes, it returns `ready_for_writer: false` and does not open the target disk.
