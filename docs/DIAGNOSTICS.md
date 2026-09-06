# Diagnostic bundles

Bedrock creates diagnostic bundles only after the administrator supplies the exact consent phrase `CREATE REDACTED DIAGNOSTIC BUNDLE` and selects a new `.tar.gz` output path. Existing files are never replaced.

Run as root:

```sh
bedrock-diagnostic-bundle "CREATE REDACTED DIAGNOSTIC BUNDLE" /var/lib/bedrock/diagnostics/support.tar.gz
```

The bundle contains an integrity manifest plus an allowlisted subset of release, hardware, storage-health, alert, virtual-machine, and update state. Missing or invalid sources are recorded as unavailable. Keys and values associated with credentials, hostnames, network addresses, device paths, serial numbers, fingerprints, tokens, and secrets are replaced with `[redacted]`. Arbitrary files, journal logs, user content, pairing state, API tokens, and command arguments are never collected. The resulting archive is owner-readable only; review its contents before sharing it.
