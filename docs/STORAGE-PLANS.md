# Storage creation plans

Bedrock's first storage-creation component is deliberately review-only. It validates a proposed ZFS or Linux MD layout and explains destructive effects, estimated usable capacity, capacity lost to differently sized disks, minimum failure tolerance, and hardware RAID visibility. It cannot create a pool or array.

Supported review layouts are ZFS mirror, RAID-Z1, and RAID-Z2 plus Linux MD RAID 1, 5, 6, and 10. Selected disks must be present exactly once in a fresh inventory, unused, writable, unmounted, non-system, non-removable, at least 64 GiB, and use the same logical sector size. Direct disks require known-good health. Hardware RAID logical volumes must remain explicitly unknown in the current contract and can enter only the acknowledged advanced review path. The confirmation text must name the pool, backend, layout, and every selected device path exactly.

The planner rejects mixing direct disks with hardware RAID logical volumes and rejects Linux MD layered on hardware RAID. ZFS review on hardware RAID requires an advanced acknowledgement and carries a warning that physical-member, cache/battery, and rebuild visibility may be hidden.

Every result has `review_only: true`, `execution_material_present: false`, and `ready_for_execution: false`. It contains no command, authorization token, privileged request, or disk-writing path. A future executor must independently refresh inventory, repeat every eligibility and confirmation check, verify authorization, and pass destructive recovery tests before this protection can change.
