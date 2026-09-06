# First test image readiness

This checklist tracks the remaining work required before the first serious Bedrock OS acceptance cycle. Items are checked only after their evidence passes.

- [x] Finish authenticated dashboard telemetry with partial-failure and privacy tests.
- [x] Fix the image-build validation failure in archived image import.
- [x] Pass the complete Linux configuration and authorization test suite.
- [x] Build two independent OS images successfully.
- [x] Prove both OS images are reproducible.
- [x] Generate verified ISO and raw USB image artifacts with checksums.
- [x] Generate the physical/VM acceptance kit.
- [x] Publish the exact test procedure and artifact links for VMware, Hyper-V, Intel, and AMD sessions.

Evidence: [reproducible base-image run 34015349856](https://github.com/DEADish1/bedrock-os/actions/runs/34015349856), [protected-writer acceptance run 34033836329](https://github.com/DEADish1/bedrock-os/actions/runs/34033836329), and `docs/FIRST-TEST-IMAGE.md`.
