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

## Protected raw-write stage

`protected-system-writer.rs` adds the first physical stage behind a separate production-trust build gate. Ordinary builds contain only a fail-closed executable. The gated Linux build requires root, a direct `/dev` whole-disk identity, `O_EXCL`/`O_NOFOLLOW`, the exact confirmed capacity from `BLKGETSIZE64`, and an opened copy of the fixed packaged image whose SHA-256 and size still match. It retains that one disk handle while writing, synchronizing, and comparing every source byte with a full reread.

`write-protected-install.sh` does not accept test substitutions. It reruns the independent protected preflight immediately before handing the fixed live-media artifact and freshly confirmed target to the root-owned writer. The raw writer returns the kernel major/minor identity obtained from its exclusively opened handle. `finalize-protected-layout.sh` binds subsequent work to private root-only device nodes created from that identity instead of trusting a reusable `/dev` name. It relocates the backup GPT, recreates partition 8 with its original GUID and canonical type/name, asks the kernel to reread the table, discovers the exact child through sysfs, checks and grows ext4, synchronizes it, and verifies all eight GPT roles.

The existing disposable-file simulator executes the equivalent complete transformation and failure cases. A separate gated CI acceptance test runs the protected writer and finalizer only on a loop device whose sysfs backing file must exactly equal a newly created disposable sparse image. It verifies the completed GPT, state growth, and fixed system content after detaching the loop. Automation never selects or opens a physical disk. A genuine disposable-system-disk installation and boot report is still required, so this checkpoint does not complete the v0.3 on-server installation checklist item.

## Live-image package

`stage-protected-installer.sh` creates the live overlay package with the fixed Linux scanner, canonical layout, planning/request/preflight/finalization scripts, `/usr/sbin/bedrock-install-system`, and the compiled helper. It records exact SHA-256 values for every installed component plus build metadata that states whether the destructive writer was production-enabled. `build-image.sh` stages this overlay only while `live-build` consumes it and then verifies and removes the generated files, preventing build artifacts from dirtying the source tree.

The installed launcher uses only `/usr/lib/bedrock/installer`, `/usr/share/bedrock/installer`, `/usr/lib/bedrock/bedrock-system-writer`, and the fixed live-media package. Before preflight it checks root ownership, package hashes, and `writer_enabled: true`. Development images package a fail-closed helper and metadata value of `false`; production writer builds require both the exact data-loss build token and production-trust gate.

The image workflow exposes a manual `protected_writer_acceptance` option. When selected, both reproducibility replicas compile the gated helper, the completed ISO is opened read-only, its live filesystem is extracted to temporary storage, and every protected-installer component is checked against the embedded manifest. The build manifest records `protected_system_writer_enabled: true`. These artifacts still use explicitly ephemeral development signing and remain acceptance-only, not release-eligible.
