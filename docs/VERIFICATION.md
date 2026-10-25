# Verification record — latest update 2026-10-25

## Current scan presentation refinement

- Simplified the live overlay toward the supplied promotional reference: plain controls, a short coaching capsule, lighter miniature faces/contact shadow and one compact live-status label. Detailed progress moved to Options; the visual budgets and real geometry contract are unchanged.
- Deterministic suite: **46 passed**, zero failures. Initial renderer/layout/navigation run: **7 passed** (six AR fixtures including the 600-surface stress case plus one scan UI workflow). Final layout/startup-error/navigation checks were repeated after finishing control states, and the scan UI test passed with explicit assertions that Directions/Positions remain accessible in Options. Compact and large-text scan screenshots were visually reviewed.
- These changes are **not installed on the phone**. Camera appearance, readability over real scenes and physical performance still require hardware acceptance; this is not a claim of RoomPlan recognition parity.

## Current long-scan fix and project polish

- User reported lag followed by a crash during extended room scanning on iPhone 12 mini. Code review identified unbounded per-edge render entities, recursive edge lookups, repeated visibility sweeps and continuous miniature geometry/sort allocations. **No crash/Jetsam report was retrieved:** devicectl reported the phone unavailable, so the actual termination cause remains unconfirmed.
- Replaced live visualization with bounded batched meshes and a cached, throttled miniature. Memory/thermal fallback releases only visuals. Actual AR maps and annotation coordinates are unchanged. Follow-up review separated active raycast stability from the display cache and fixed stale outlines after invalid geometry.
- macOS deterministic tests: **46 passed**, zero failures. Includes rendering budgets, reveal/geometry validity, stable placement, capture request ordering, spatial/localization math, real disk persistence and backend fixtures.
- Simulator renderer/layout suite: **6 passed**, zero failures. The long-scan fixture feeds **600 surfaces with 256 input vertices each** and verifies 128 cached metadata patches, 24 outline anchors/48 drawables normally, and 12 anchors/12 drawables after memory fallback, with instructions retained and off-cache placement stability working.
- Three interactive local UI flows passed: project rename/relaunch, room rename/delete/relaunch, and scan entry with an explicitly asserted unsupported-AR error. Empty project input is rejected. Auth and configured-cloud UI tests **explicitly skipped**; these are not evidence of live Auth/cloud success.
- UI polish includes searchable projects, room progress, readable statuses, native tips, English main controls, busy feedback and capture-race prevention. Expanded layout fixtures export 42 screenshots; final reduced-detail/accessibility and empty-project sizing are visually reviewed after correction. Tests do not substitute for VoiceOver or physical AR verification.
- Current changes have **not been installed on the iPhone**. Earlier installation evidence below applies to commit 88d4de7, not this revision. Hardware performance/accuracy and hosted backend acceptance remain pending.
- Course requirement audit and AI-use notes are in COURSE_AUDIT.md and AI_USAGE.md. Team size two is user-reported; lecturer approval and individual understanding/contributions are not asserted.

## Earlier records — 2026-10-23

## Latest iPhone installation

Source commit `88d4de7` built and signed successfully, installed over the existing app on the connected iPhone 12 mini, and launched successfully using devicectl. Existing app data was preserved. This supersedes the earlier simulator-only deployment notes below; physical AR accuracy, animation performance and room-recovery acceptance still require testing.

## Current animated scan update

- Reviewed the supplied 6.5-second RoomPlan promotional clip at **three timestamps** (0.6, 3.2 and 5.8 seconds). No video/frames are included in the repository. The local Floor Planner app was inspected and is a separate 2D web tool, not an AR scanner.
- Added progressive RealityKit outline tracing/halos, stable outline-entity reuse, and a shaded, camera-oriented miniature with patch appearance/refinement animations and Reduce Motion support.
- Deterministic suite: **38 tests passed**, zero failures, including slab geometry/pose preservation and shortest-angle turning. Simulator: **4 tests passed**, zero failures: 30 compact/large-text layout captures, image/stroke persistence/rendering, outline anchor reuse/refinement, and a pixel-level check that the miniature renders without animation ticks. Final scan screenshots were visually reviewed.
- Visual review found and fixed an initially invisible miniature: pre-existing geometry now renders immediately, with appearance animation reserved for new detections. A pixel regression test covers the first frame.
- This revision has **not been deployed to the phone**. Live animation quality, performance, physical boundary alignment and recognition quality remain hardware checks. Animated patches are not RoomPlan window/furniture recognition.

## Multi-view recognition update

- Capture now requires four heading sectors and three positions at least 0.5 m apart, in addition to map/tracking/surface readiness. Regression tests distinguish walking with one viewing direction from spinning in place; neither alone completes capture.
- Deterministic suite: **36 passed**, zero failures. Simulator layout/rendering and project/room/scan navigation: **3 focused tests passed**; the final layout-only rerun also passed, with compact and large-text scan screenshots visually checked after the last display adjustment.
- Recovery offers continued searching without resetting the session. No mesh-based matching or viewpoint-independent recognition is claimed. Existing sparse maps are preserved, not automatically expanded.
- At the user's request this revision is **not installed or tested on the phone**. A signing attempt for the earlier scan-screen changes failed with macOS errSecInternalComponent; simulator compilation/testing is independent of that keychain issue.

## Scan and placement update

- Removed the silent estimated-surface fallback, corrected measured-distance placement to use the actual screen ray, retained finer boundary corners and added a targeted-surface preview.
- Replaced the scan dashboard with a camera-first Cancel/Finish overlay and floating live surface overview. This remains camera-only ARKit plane detection, not RoomPlan semantic geometry.
- Deterministic suite: **36 tests passed**, including the new off-centre measured-distance fixture. Simulator layout/rendering and navigation checks are recorded below; live wall accuracy and scan duration cannot be verified in the simulator.

## Drawing, area and image update

- Signed iPhone Debug build: **succeeded** with Xcode 27.1. Installed over the existing app on the physical **iPhone 12 mini (iOS 27.0.1)**, preserving local data.
- macOS deterministic suite: **36 tests passed**, zero failures. Covers transforms, localization evidence, serialization, stroke boundaries, smoothing without overshoot, image metadata, persistence and Store/backend behavior.
- Simulator: **four focused tests passed** across the final two runs: layout states, image/separate-stroke persistence and rendering, legacy shape rendering, and local project/room/scan navigation. The final layout/persistence rerun passed both tests after the last edits.
- **30 layout screenshots** were exported and visually reviewed: empty projects, login, settings, task views, placement/work-detail forms, scanning, recognition, tracking loss, recovery, worker view and all three editor tools. Includes compact 375-point widths, 667/812-point heights and accessibility text sizes. Fixes include a fixed Save bar, compact header, adaptive controls, keyboard-safe sheets and a crosshair in the unobstructed camera region. These fixtures cannot prove every possible interactive or keyboard state.
- A real normalized PNG and two independent paths were saved, the local Store reopened, bytes/metadata checked, texture decoded and separate RealityKit entities rendered. Simulator fixtures do not validate real camera capture, touch-to-wall accuracy or frozen-view projection on hardware.
- The user reported earlier scan/draw builds mostly working. Full physical scan → draw/image → close → recover acceptance of this update still requires the checks in DEVICE_TESTING.md. Cross-device alignment and cloud behavior remain unverified.
- Supabase is unconfigured. Apply **all three migrations** and run the **28-assertion pgTAP suite** against a development backend; no CLI/PostgreSQL/Docker server was available here. Compiled client code is not proof of server policy behavior.
- Keep Device Hub physical-device screen viewing OFF during AR testing; it previously coincided with a black camera and blocks camera access. Keep Developer Mode and pairing enabled.

## Known limits

- ARWorldMap recovery is probabilistic. Stable normal tracking plus matching restored room anchor and extending/mapped evidence gates automatic display. It is not survey-grade recognition. Users should inspect physical drawing placement; tracking loss hides annotations and retries recovery.
- New room scans require no dots/print. Optional marker fallback still needs explicit confirmation because a moved print produces a wrong transform. Legacy two-point manual recovery is gravity-aligned yaw/translation, not six-axis precision alignment.
- Live boundaries, counts and the isometric overview show detected ARKit plane patches. No whole-room coverage percentage, classified furniture boxes, reconstructed room model or RoomPlan capability is claimed on the camera-only iPhone 12 mini.
- Area drawings are planar outlines with non-collinear first three vertices. Freehand drawings have up to 32 independent paths, 256 samples per path and 2,048 total samples. Legacy single paths retain their older format. Explicit distance placement depends on measurement; no automatic guessed depth or depth occlusion is provided.
- Published spatial maps/metadata are immutable. Remapping requires a new room revision; annotations are not automatically migrated between coordinate systems.
- Local Debug data remains on one device and does not automatically upload when Supabase is configured. Cloud mode uses explicit refresh, with no offline synchronization queue or realtime revocation/conflict resolution.
- Force-quitting loses unsaved scans/drawing/form drafts. Backgrounding a new scan restarts it; saved rooms must recover again.
- Failed uploads/deleted rooms may leave private orphan Storage objects requiring administrative cleanup through the Storage API. Never delete only storage metadata in SQL.
- Cloud lists use the backend row limit (local config: 1,000). Large-project pagination, account deletion/password recovery UI and operational monitoring remain follow-up work.

Follow DEVICE_TESTING.md to record same-phone and two-phone physical acceptance. This is not yet a hardware-accepted release.
