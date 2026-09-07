# Isolated applications

Bedrock applications run as Podman containers and are treated as untrusted workloads. Every installation is pinned to an exact SHA-256 image digest, runs as UID/GID 65532 with a read-only root filesystem, drops all Linux capabilities, enables `no-new-privileges`, and has explicit CPU, memory, and PID limits. Host networking, privileged containers, arbitrary mounts, devices, and runtime arguments are not accepted.

An application may have no network or an isolated bridge. Bridge ports are explicit and cannot bind privileged host ports. Its only writable mount is `/srv/bedrock/apps/APP_ID` at `/data`; removal preserves that directory for recoverability.

Install and update requests are bounded JSON files. Both require a SHA-256 of the canonical request in the exact confirmation phrase. Updates must retain the existing application identity and image repository, pull the newly approved digest, stop the prior container, recreate its sandbox, and restart it. The `manual` policy performs no registry checks. The `notify` policy permits a read-only scheduled comparison of the configured tag with the installed digest; Bedrock never installs a discovered update automatically.

Use `bedrock-apps list`, `check-updates`, `start`, `stop`, `install`, `update`, and `remove`. Start, stop, install, update, and removal are blocked during maintenance mode. A catalog and automatic third-party trust decisions remain outside this runtime boundary.
