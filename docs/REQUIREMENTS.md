# Verifiable scope and effort

The current flow is scan → draw → save → recognize the room → restore drawings. Manual dots and printed markers are no longer mandatory. Live plane outlines/counts/overview report detected surfaces, not total room coverage. Implementation is present for the following requirements. Acceptance requires the listed evidence; delivery of code alone does not close hardware or backend acceptance.

| MUST HAVE | Observable acceptance | Verification |
|---|---|---|
| Native iPhone app | Signed installation opens SwiftUI authentication on iOS 17+ | Device install required; simulator build compiled |
| Accounts | Register, confirm email, sign in, relaunch, refresh token, sign out | Mock network tests; live Auth pending |
| Project/room CRUD | Create, rename, refresh, delete; room names remain associated with project | Policy/UI suites supplied; backend execution pending |
| Camera-only mapping | Normal world tracking and mapped status without scene depth; map generated from real camera data | Physical camera-only iPhone required |
| Room world maps | Private file upload and secure unarchive on another launch/device; correct sentinel required | Code compiled; hardware/cloud pending |
| Markers and text | Raycast or explicit measured-distance placement; persisted room-relative pose; task can be edited/deleted | Geometry/serialization tests; device pending |
| Wall/area outlines | Three or more coplanar 3D vertices restore on the intended surface | Geometry tests; device pending |
| Map localization | Search, timeout, automatic map recovery after restored-room/stable-tracking evidence; hide overlays on tracking loss | State tests; device pending |
| Optional fixed marker fallback | Unique printable/importable target, measured dimensions, registration, separate-session alignment | Transform tests; physical detection pending |
| Legacy manual recovery | Existing saved point pairs can recover with confirmed preview; new scans require no manual dots | Math tests; device pending |
| Worker walkthrough | Assigned worker loads map/tasks, walks around, opens tapped instruction | Two-device acceptance pending |
| Task status | Worker saves In Progress/Completed; other task fields protected | Client fixture tests; policy execution pending |
| Secure cloud persistence | Outsider blocked from tables, files and status RPC; manager shares/revokes | Migration and pgTAP suite supplied; execution pending |
| Tests and docs | Deterministic tests pass; iOS suites compile; reproducible setup and hardware runbook | See VERIFICATION.md |

## NICE TO HAVE

Optional scene depth is enabled when supported. Basic lines and arrows are implemented using the same persisted vertex model. Mesh occlusion, advanced drawing, measurements, offline project synchronization, push notifications, realtime collaboration, progress dashboards and sophisticated six-axis manual alignment are deferred. Do not spend effort on these before recording the two-device camera-only acceptance.

## 160–240 hour team budget

A realistic 200-hour plan includes substantial device validation, not just coding:

| Work | Hours |
|---|---:|
| Setup, auth, Keychain and UI navigation | 22 |
| Projects, rooms, sharing and task forms | 26 |
| Map lifecycle, archives and upload flow | 28 |
| Persistent annotations and surface geometry | 24 |
| Relocalization, verification and marker fallback | 34 |
| Manual recovery, interruptions and errors | 16 |
| Backend, policies and integration testing | 22 |
| Two-device testing, documentation and fixes | 28 |
| Total | 200 |

Use small reviewable commits by layer. The working directory belongs to an existing parent Git repository; this delivery does not create a nested repository or alter unrelated repository history. Suggested commits: core/test fixtures; Supabase schema/policies; auth/project UI; AR map/localization/editor; acceptance documentation. Review changes before committing.
