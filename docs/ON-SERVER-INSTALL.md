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
