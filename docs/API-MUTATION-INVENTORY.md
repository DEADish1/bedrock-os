# Authenticated management mutation inventory

Audit date: 2026-09-22. Sources: `release/1.0-contract.json`, packaged OpenAPI at `os/config/includes.chroot/usr/share/bedrock/api/openapi-v1.json`, the Unix API and root action broker, and `app/page.tsx`. This is a coverage map, not acceptance evidence. API contract tests prove route/schema agreement; existing browser tests mock the backend and do not prove the installed interface can reach it.

## Confirmed contract coverage

All 33 mutating method/path combinations in the packaged OpenAPI have a corresponding Unix API dispatcher and guarded backend path. The following groups are represented in the interface source; each still needs the cross-area real-server and negative-path browser acceptance listed in 0.6.4–0.6.5.

| Area | API mutation paths and operations | Interface source | Remaining acceptance |
| --- | --- | --- | --- |
| Settings | `PUT /settings`: update choice/channel, relay configure/disable | Settings | Real-server save, stale-state, failure recovery |
| Remote trust | `POST /remote/devices/{id}`: rename, expiry, revoke; `POST /remote/pairings/{id}/approve` | Remote access | Pairing/client session and live revocation |
| Applications | `POST /apps/{id}/install`, `/power`, `/update`; `DELETE /apps/{id}` | Apps | Root-staged install and lifecycle on candidate image |
| Backups | `POST /backups/{id}/create`, `/run`, `/restore-latest` | Backup | Encrypted restore and failure-path drill |
| Images | `PUT`/`DELETE /images/{name}/upload`; `POST /images/{name}/import`, `/convert` | Image library | Upload/import/convert against candidate image |
| Storage | `POST /storage` create; `POST /storage/{id}/expand`, `/replace`, `/scrub`, `/export`, `/import` | Storage | Physical media and cross-area state reconciliation |
| NAS identity | `POST /users` create; `POST /groups/{id}/members`; `POST /users/{id}/rotate-credential` | Users | Root-staged credential and real SMB acceptance |
| Virtual machines | `POST /vms` create; `POST /vms/{name}/power`, `/snapshots`, `/clone`, `/resources`, `/images`, `/networks`, `/passthrough`, `/console-sessions`; `DELETE /vms/{name}` | Virtual machines | Linux/Windows guests, real console, passthrough |

The table groups all 33 method/path combinations; actions that share a path have multiple strict request variants. The server must continue to reject fields such as host paths, commands, raw device identities, or arbitrary credentials. OpenAPI route agreement alone does not establish that every UI control sends the right variant.

## Open release-blocking gaps

1. **No packaged browser gateway.** `app/page.tsx` uses same-origin browser `fetch('/api/v1/...')` and a same-origin console WebSocket, while the packaged API listens only on `/run/bedrock-api/api.sock`. `app/` contains no API route, and the OS image does not package an HTTP(S) server/reverse proxy for this UI. The private hosted prototype and mocked Playwright tests therefore are not evidence of a working installed management UI. A production same-origin gateway must be designed, packaged, authenticated, origin/CSRF and WebSocket hardened, and tested against the Unix API before 0.6.2 or the broad 0.6 milestone closes. It must not expose the Unix socket or bearer token to an unauthenticated network listener.
2. **Root-staged setup prerequisites remain outside v1.** Backup plan sources/repositories/passwords, application image digests, and NAS credential staging are deliberately root-only. Either provide a narrowly scoped, reviewed local-console setup flow for each or explicitly document terminal-required administration as a supported 1.0 limitation and obtain scope approval; do not pass secrets through the general read API merely to make the UI appear complete.
3. **Pairing initiation and client connectivity are not complete.** The API exposes administrator approval and trusted-device changes, but the remote client must initiate and redeem pairing through its isolated Noise/gateway path. This is 0.7.1–0.7.7 work, not a missing general management API endpoint.
4. **Hardware and Help are read-only by design.** Hardware diagnostics and help links do not imply arbitrary hardware mutation APIs. Actual storage/passthrough mutations have their own guarded paths.
5. **API-token administration is local-console-only.** `create-api-token` and `manage-api-tokens` are deliberately outside the remote/browser mutation surface. The 1.0 acceptance plan must verify issuance, revocation, rotation, and recovery from a lost token without broadening browser authority.

## Closure criteria for 0.6.2

- [ ] Package and security-test a real browser-to-Unix API bridge (including console WebSocket) on the candidate image.
- [ ] Verify every route/action variant listed above through that bridge with current ETag, exact confirmation, idempotency, authorization rejection, bounded bodies, and secret-free responses.
- [ ] Resolve the three root-staged setup prerequisites with approved local-console workflows or explicit, reviewed 1.0 deferrals.
- [ ] Reconcile any resulting contract additions with the frozen v1 path inventory and OpenAPI tests.
