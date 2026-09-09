# Encrypted backup plans

Bedrock uses restic repositories so every local or remote backup is encrypted and content-addressed before it leaves the server. Plans support local repositories below `/mnt` and bounded SFTP destinations. Remote SSH credentials remain in the operating system's root-only SSH configuration; repository passwords live only in `/var/lib/bedrock/backup/secrets/PLAN.password` with mode `0600` and never appear in plan state, logs, or commands.

Create a request containing a lowercase plan ID, display name, source below `/srv/bedrock`, repository, `local` or `remote` kind, daily or weekly UTC schedule, retention counts, and whether Bedrock should initialize a new repository. Review its canonical SHA-256 and create it with the exact phrase printed by the management interface: `CREATE ENCRYPTED BACKUP PLAN HASH`. Existing repositories are checked without initialization.

The hourly timer runs due plans and applies daily, weekly, and monthly retention only after a successful backup and verified snapshot listing. Administrators can also run a plan with `RUN ENCRYPTED BACKUP PLAN`. The local root command supports a specific snapshot with `RESTORE BACKUP PLAN SNAPSHOT ID`. The authenticated interface offers the safer `RESTORE LATEST BACKUP PLAN` flow, which selects the recorded latest successful snapshot internally so its identity never reaches the browser or API. Both flows restore into a new `/srv/bedrock/restores/PLAN` directory and never overwrite an existing restore.

Keep at least one repository off-server and periodically perform a restore drill. SFTP host keys must be pinned before enabling a remote plan. A successful job is not proof of recoverability until restored files have been verified.
