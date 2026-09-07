# Health notifications

Bedrock can deliver health events to authenticated HTTPS webhooks and TLS-protected SMTP servers. Destination metadata is root-only. Webhook tokens and email credentials are stored separately under `/var/lib/bedrock/notifications/secrets` with mode `0600`; list operations, event payloads, logs, and command arguments never contain those secrets.

Configuration requests are SHA-256-bound and require the exact phrase `CONFIGURE NOTIFICATION ID HASH`. Administrators can verify a destination with `TEST NOTIFICATION ID` and remove one with `REMOVE NOTIFICATION ID`. Webhooks must use HTTPS without embedded credentials, query secrets, or nonstandard ports. Email always uses certificate-verified implicit TLS.

The five-minute delivery timer consumes the bounded storage-alert event history. Notifications include severity, event state, a plain title, and a specific recommended action such as replacing a failing disk or opening pool recovery. Resource paths and raw alert identities are replaced by a one-way notification reference. Successfully delivered destination/event pairs are retained for deduplication; failures remain pending for the next run.
