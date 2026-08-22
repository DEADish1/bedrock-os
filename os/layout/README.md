# Bedrock system-disk layout

The Bedrock system disk is separate from NAS data drives. It uses GPT and UEFI, two immutable root slots, matching dm-verity hash/signature partitions, and one growing persistent-state partition.

## Boot and update behavior

1. The EFI System Partition stores signed unified kernel images and boot state.
2. The selected unified kernel image contains the expected signed root hash.
3. The root hash identifies and verifies the matching root/verity pair.
4. Updates write only the inactive slot, then install a new boot entry with three allowed attempts.
5. The new slot is promoted only after the Bedrock health target succeeds.
6. Failed attempts automatically return to the previous slot; rollback does not rewrite user storage.

`bedrock-amd64.json` is the machine-readable source of truth. The installer and image composer will consume it instead of duplicating partition sizes or GUIDs.

The layout follows the x86-64 root, root-verity, and root-verity-signature partition types in the Discoverable Partitions Specification. The 32 GB minimum leaves working space beyond the fixed partitions and 8 GB minimum state area.

