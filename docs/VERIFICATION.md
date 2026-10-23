# Verification record — 2026-10-23

## Current drawing, area and image update

- Signed iPhone Debug build: **succeeded** with Xcode 27.1. Installed over the existing app on the physical **iPhone 12 mini (iOS 27.0.1)**, preserving local data.
- macOS deterministic suite: **34 tests passed**, zero failures. Covers transforms, localization evidence, serialization, stroke boundaries, smoothing without overshoot, image metadata, persistence and Store/backend behavior.
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
