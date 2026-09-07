# Privacy and telemetry policy

Bedrock is designed for local administration. It does not send product analytics, advertising identifiers, filenames, VM names, disk serial numbers, server names, account details, or usage telemetry to the Bedrock project by default.

Network activity occurs only for an administrator-enabled function: checking configured OS or application update sources, using a configured remote-access relay or identity provider, delivering configured notifications, or writing to a configured remote backup. Each function must be independently disclosed and disableable. Disabling it must stop its requests.

Local operational state includes health summaries, bounded audit events, update state, tasks, paired-device metadata, and configuration. Credentials and private keys are stored separately with restrictive permissions and are excluded from ordinary diagnostic and configuration exports. Diagnostic bundles require an exact consent phrase and must be reviewed before sharing.

Future optional telemetry requires a separate, off-by-default consent flow that names every field, recipient, purpose, retention period, and deletion method before collection. A product update may not silently broaden consent. Crash reports and support bundles are never uploaded automatically.
