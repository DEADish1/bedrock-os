# Bedrock 1.0 hardware support policy

Status: approved for 0.1 product definition. This is the minimum support contract, not a promise that every device using these standards will work.

## 1.0 supported platform

- Architecture: 64-bit Intel/AMD (`amd64` / `x86_64`) only.
- Firmware: UEFI boot required; Secure Boot support is a 0.9 release gate.
- CPU: 4 hardware threads minimum; 64-bit virtualization extensions (Intel VT-x or AMD-V) required for VMs.
- Memory: 8 GB minimum for storage-only evaluation; 16 GB recommended; 32 GB recommended when running multiple VMs or ZFS-heavy workloads.
- System drive: dedicated 32 GB minimum; 64 GB or larger recommended. It must not be part of the NAS storage pool.
- Data drives: at least one supported SATA, SAS-through-HBA, or NVMe drive. Redundancy requires multiple drives.
- Software RAID: OpenZFS mirror/RAID-Z and Linux MD RAID 1/5/6/10 are in the 1.0 storage target; exact layouts remain subject to minimum disk counts and recovery testing.
- Hardware RAID: logical volumes from tested controllers are supported when device identity and array state remain stable. Full support requires controller tooling that exposes member-disk, cache/battery, and rebuild health.
- Network: supported wired Ethernet adapter; 1 GbE minimum recommendation. Wi-Fi is not a supported primary server connection for 1.0.
- Display/input: only required for installation and local recovery; normal administration is browser/client based.

## Optional advanced hardware

- GPU passthrough requires CPU/chipset IOMMU support (Intel VT-d or AMD-Vi), firmware enablement, safe IOMMU grouping, and a GPU not required by the host while assigned.
- USB controller/device passthrough depends on stable device identity and isolation.
- Hardware transcoding and vendor-specific accelerators remain compatibility-matrix features, not baseline guarantees.
- ECC memory is recommended for high-value storage but is not required.
- UPS devices will be supported through a tested compatibility list in 0.8.

## Explicitly outside the 1.0 baseline

- 32-bit x86 and ARM.
- Legacy BIOS-only systems.
- Apple Silicon as a Bedrock host.
- ARM64 appliances and single-board computers.
- Untested proprietary RAID controllers, controllers that rewrite logical-disk geometry after import, and controllers without any usable health interface. Such volumes may be detected but are reported as limited/unsupported rather than healthy.
- USB flash drives as the permanent Bedrock system disk.
- Wi-Fi-only servers.

## ARM64 policy

Debian supports ARM64, but ARM systems have substantially more platform variation. Bedrock will revisit ARM64 after the x86-64 1.0 release with a named-device compatibility list and separate images rather than claiming generic ARM support.

## Validation matrix required before 1.0

- Intel and AMD desktop-class systems from multiple generations.
- At least two server/workstation boards with ECC.
- SATA AHCI, NVMe, and IT-mode SAS HBA storage paths.
- Linux MD RAID 1/5/6/10 assembly, degradation, replacement, rebuild, and import.
- At least one tested hardware RAID family with logical-volume discovery, member health, cache/battery state, and rebuild reporting; other controllers are best-effort until added to the matrix.
- Intel, Realtek, and supported server-class Ethernet adapters.
- UEFI boot, Secure Boot, IOMMU, power-loss, thermal, suspend-disabled, and headless boot behavior.
- QEMU virtual hardware, VMware, and Hyper-V as development/test environments; physical-hardware results remain authoritative.

## Inventory contract

At boot, Bedrock writes `/var/lib/bedrock/hardware/inventory.json` with CPU topology and virtualization support, total memory, physical/logical disks, PCI storage and RAID controllers, non-loopback network interfaces, and DRM GPU devices. Storage-controller records identify RAID, SAS, SATA, and NVMe classes so the UI can distinguish direct disks, HBAs, and hardware logical volumes. GPU records identify Intel, AMD, and NVIDIA vendor IDs, the active kernel driver, and an IOMMU group when one is available. This is discovery data for setup and resource assignment; RAID support level and passthrough eligibility still require their deeper checks.

Bedrock also refreshes `/var/lib/bedrock/storage/health.json` through a read-only collector. It records non-waking SMART health and temperature when available, Linux MD member state and recovery progress, imported ZFS pool health when ZFS tools are installed, and PCI hardware RAID controllers. Hardware RAID member, cache/battery, and rebuild health remains explicitly `limited` until a supported vendor adapter is present; a logical volume behind a controller is not proof that its member disks are healthy.

The same refresh writes `/var/lib/bedrock/storage/alerts.json` atomically. It opens alerts for SMART failure, temperatures of 55°C or higher, degraded MD/ZFS storage, and limited hardware RAID visibility; 65°C or higher is critical. Unchanged findings retain their first-seen time without duplicating audit events, while severity changes and resolutions are recorded in a bounded 1,000-event history. These initial temperature thresholds are conservative defaults and require hardware-specific policy work before 1.0.
