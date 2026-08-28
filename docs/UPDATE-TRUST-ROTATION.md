# Update signing certificate rotation

Bedrock images trust `/usr/share/bedrock/update-trust.pem`. The file must contain exactly one or two distinct, unexpired PEM certificates and no other data. Every metadata and bundle verification validates this contract before invoking OpenSSL CMS verification.

## Planned rotation

1. Generate the next signing key in the protected release-signing environment. Never place private signing keys in an image, repository, update bundle, or build artifact.
2. Ship a normally signed release whose trust bundle contains the current and next public certificates. Continue signing updates with the current key.
3. Wait for the documented supported update window and confirm that the supported fleet has installed an overlap release. Systems that skipped the overlap cannot authenticate updates signed only by the next key.
4. Switch release signing to the next key while continuing to ship both public certificates.
5. After another supported update window, ship a release signed by the next key that removes the retired certificate. Later images contain only the next certificate.

Do not reorder or combine the overlap, signer switch, and retirement into one release. A compromised key is an incident-response exception: stop publishing, assess the installed trust population, and use a separately reviewed recovery release or recovery media. Merely deleting a certificate from the download server cannot change trust already embedded in immutable installed images.

## Release checks

- Verify updates signed by either certificate against the overlap bundle.
- Verify the next certificate is rejected by a current-only bundle before overlap.
- Verify the retired certificate is rejected by a next-only bundle after retirement.
- Verify unrelated, duplicate, malformed, symlinked, and three-certificate bundles are rejected.
- Record public-certificate SHA-256 fingerprints and the release generations that introduce overlap, switch signing, and retire the old anchor.
