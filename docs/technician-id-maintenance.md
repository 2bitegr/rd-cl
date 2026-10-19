# Technician-only ID maintenance

Windows Settings > Security provides **Generate new ID** only after a current
Office support sign-in has been verified. Existing support administrator and
technician roles qualify; cached role/name text alone does not grant authority.
The card identifies **this computer**, requires unlocked security settings and
explicit confirmation, and refuses unfinished local report drafts/queues.

The native client first negotiates the identity-operation version with the
installed daemon using an existing non-secret Config query. It never sends a
companion credential to an older daemon that lacks the operation. The new main
IPC request is protected by the existing Windows executable/peer authorization;
its Debug representation redacts credentials.

The daemon independently verifies the existing Office
`GET /api/v1/rustdesk-companion/workflow-capabilities` response. That handler
checks the current active support role and unrevoked pairing, including when
workflow-v2 is disabled. `office_user_id` must match the captured sign-in and
`pairing_id` must be a UUID. Only the pinned live Office HTTPS origin is trusted;
redirects, missing endpoints, expired sessions, malformed replies and unverified
identities fail closed. No new Office endpoint, migration or flag is required.

After rechecking the expected ID and absence of remote sessions, the daemon
ends the old pairing through the existing logout route. Uncertain logout is
never replayed and cannot authorize an ID write. The final expected-ID check
also occurs under the Config write lock. A new numeric ID uses the existing
client range, with normal rendezvous registration and the existing device keys.
The Windows service itself is not restarted.

An atomic reservation rejects overlapping resets without holding a mutex across
network awaits. Filesystem/ACL persistence runs on the blocking pool, rechecks
idle state and owns the reservation until completion even if its caller stops
waiting. Existing controlling-session counts reach the daemon through IPC.

Before persistence, an exact main-TOML snapshot is created beside the existing
configuration. Its DACL is protected before any data is written, using the
established private runtime-file policy (SYSTEM, Administrators and process
user); Unix helper fixtures use mode 0600. Symlinks/reparse points, oversized
files and concurrent file changes are rejected. Checked save/readback precedes
the in-memory update. Failed writes attempt byte-verified restoration and retain
the recovery snapshot. Snapshots contain private keys: keep them in their
protected runtime location and never copy them into Desktop reports or Git.
Manual recovery requires stopping the relevant daemon and reviewing/restoring
the exact saved main TOML; it does not restore Office data or reopen a pairing.

Success displays the new local ID and snapshot path, clears only the matching
local companion sign-in and requires a new Office login. The technician must
confirm **Ready** in rd-cl; local persistence is not proof of server acceptance.
An ambiguous reply requires inspection and fresh sign-in, never automatic retry.
The legacy custom-ID UI/CLI remains disabled in the Exantas build; disabled raw
IPC ID writes cannot bypass the Office-authorized operation.

Office customer ownership, past sessions, report/outbox files, device keys and
server settings remain untouched. Existing managed enrollment tokens are still
bound to their old peer and may return peer_id_mismatch after a rotation; the
maintenance operation never silently re-enrolls or transfers a customer device.
No billing, report finalization or email command is part of the operation.

Validation uses synthetic Flutter screens and native transport/config fixtures.
Native installed-service, actual identity rotation, server readiness, private
backup ACL acceptance and new pairing are separate operator acceptance checks.
The source version is unchanged until an explicitly approved release is prepared.
