# Verified boot inputs

Bedrock boots a signed unified kernel image (UKI). The UKI contains the kernel,
initramfs, OS release data, command line, selected slot, and that slot's dm-verity
root hash. The root hash—not a duplicated GPT label—identifies the immutable
system partition.

`build-uki.sh` deliberately refuses to emit a release artifact without a Secure
Boot private key and certificate. Development keys may be supplied locally, but
release keys must come from protected CI secrets and must never enter source.

The inactive slot is written and verified first. It becomes a one-boot candidate;
three failed health checks select the last known-good slot automatically.

`build-verified-root.sh` produces the immutable EROFS image, detached dm-verity
tree, root hash, DER PKCS#7 signature, and the JSON payload stored in the matching
Discoverable Partitions signature partition. `verify-verified-root.sh` checks
both integrity and signature authenticity before disk assembly.
