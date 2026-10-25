# Physical-device acceptance runbook

Record phone/iOS/app version, room and coordinate IDs, date, lighting and approximate physical error. Include a camera-only iPhone. Keep Device Hub physical-device screen viewing OFF: mirroring blocks camera access. The USB cable/debugger alone does not require mirroring.

## Local scan and drawing

1. Install an unconfigured Debug build through Xcode on the physical phone. The app opens an empty project list without login. Create your own project/room.
2. Choose Map room. Pan slowly over textured walls, floor and furniture. Verify thin white surface boundaries appear without any filled white faces, the live overview updates, counts represent actual detected planes/features, and Scan abschließen remains disabled until map/tracking readiness.
3. Check the floating surface overview and top Cancel/Finish controls. Tap Finish. It must transition directly into drawing in the SAME session. No marker print or reference-dot collection is required.
4. Aim at a wall and choose Lock view. Move/rotate the phone slightly: the editing viewpoint must stay fixed. With **Draw**, draw a curved stroke, lift your finger, then draw elsewhere. There must be no connecting segment, sample dots or angular boxes. Undo must remove only the last stroke. Save and reopen to check both paths persist. Use **Area marking** for three/four coplanar corners. Use **Image**, import a photo and a transparent PNG, adjust width, tap to place and save. Verify proportions and image bytes survive force-quit/reopen and room recovery. Enter a long title/description through Work details and check keyboard dismissal. Try Undo/Clear/Resume camera. Reopen walkthrough and inspect geometry while moving sideways. No filled plane faces or sample dots should obscure the room. Check compact-screen controls, scrolling, large text, sticky Save, import cancellation and leaving with an unsaved draft.
5. Close AR and force-quit the app. Reopen the saved room's walkthrough. From the original viewpoints, look around until Room recognized. Drawings must stay hidden before recovery and then appear automatically, without confirming reference dots.
6. Walk around and compare wall/area placements. Measure approximate error against an agreed target (for example 10 cm); do not infer survey precision. Repeat on another day and under different lighting.
7. Tap a drawing, save In Progress/Completed and refresh/relaunch to verify task persistence. Create/rename/delete unrelated rooms and ensure the saved drawing stays with the correct room.

## Cloud/two-device acceptance

1. Apply migrations 001, 002 AND 003 to a development Supabase project. Configure matching backend settings in both phone builds, register two users, and sign in manager on A and worker on B. Local rooms do not migrate automatically; create a new cloud test project/room.
2. Repeat scan/drawing creation on A. Verify the room's map_path and surfaces metadata and its private map object exist. Share with B's registered email and end the session on A.
3. On B refresh Projects, select the shared room and start walkthrough. Recover the map and inspect the intended wall placement from several positions. Complete a task, refresh on A, and verify the status.
4. Repeat with the camera-only phone as both manager and worker. No depth/RoomPlan dependency should occur. Record cross-device physical error separately from single-device results.

## Recovery and failure tests

- **Timeout:** enter a different room or change lighting significantly. Wait 40 seconds. No drawings should appear at a new arbitrary origin. Return to the original viewpoints, choose Scan room again and recover.
- **Tracking loss:** cover the lens/move too quickly. Drawings must disappear, recognition restarts, and normal tracking plus correct saved-map evidence is required to show them again.
- **Interruption/background:** lock/unlock or background. New scans restart with guidance; saved rooms recover again. Draft drawing points stay room-relative while the screen remains alive. Leaving warns before discarding unsaved work.
- **Optional marker:** during a NEW scan expand Optional recovery marker, print/fix/calibrate/register a unique image and save. Later choose Scan fixed marker. Check the position and explicitly confirm. Test from a different session origin/yaw, then move away so the image leaves view; drawings must remain fixed. A moved print must be rejected.
- **Legacy manual fallback:** existing rooms with two saved references still offer manual recovery. Capture them in order and explicitly confirm. New scans must not require this workflow.
- **Poor planes:** on a textureless wall, a failed raycast must report/skip placement rather than invent a depth. Explicit measured-distance placement must require a real user measurement.
- **Plane merging:** revisit the same wall; merged plane anchors should replace old patches/counts. Counts are not a promise of unique architectural walls or complete room coverage.
- **Black video:** verify camera permission, stop Device Hub screen viewing, close/reopen AR directly on the phone. Do not attempt to verify live AR through mirroring.
- **Persistence failures:** disconnect during cloud upload/task save. Unsaved work remains available for retry. Room metadata publishes only after the assets exist; lost-response retries must not replace coordinates.
- **Invalid data:** corrupt a development map/version only in a disposable test room. Invalid data blocks rendering with an error. Optional marker recovery can still work if present; otherwise task lists remain available.
- **Permissions:** outsider cannot read project/maps/tasks. Workers cannot change drawing geometry or share projects. Revoke worker access and reload; new requests must fail/omit data. Run `supabase test db` too.

Do not mark physical acceptance complete until same-phone persistence and two-phone recognition are recorded. Simulator/Core tests verify state/math/navigation, not camera recognition or physical accuracy. RoomPlan-style classified furniture boxes are not part of the camera-only plane visualization.

## Placement accuracy regression checks

- Aim at an undetected blank wall: placement must wait rather than snap to a guessed depth. Move sideways and inspect the mint highlighted patch before drawing; compare against physical corners.
- Aim the off-centre crosshair at a known measured location and use measured-distance placement. It must follow that crosshair, not the optical centre. Check the result from the side.
- Repeat on a feature-rich wall and a blank/reflective surface. Camera-only ARKit boundaries may remain incomplete or inaccurate; do not treat them as RoomPlan window/furniture recognition. Saving readiness still requires a mapped world map and stable tracking; no shorter scan time is guaranteed.

## Multi-view recognition acceptance (physical testing pending)

1. Create a new room revision. Walk to at least three safe positions 0.5 m apart and view all four horizontal directions. Stand still and rotate first: this must not finish the movement requirement. Scan the same textured details from overlapping viewpoints.
2. Save drawings, end the session and reopen from the entrance, an opposite corner and the middle of the room in separate sessions. Record recovery time and placement error against the same physical marks for each viewpoint; do not label arbitrary-point recognition as accepted.
3. Repeat facing a blank wall, after changed lighting, and after moving furniture. Uncertain recovery must keep drawings hidden. After timeout, continue searching without a session reset, then test the separate restart action.
4. Repeat using an older sparse map. The new capture guidance cannot improve that map retroactively; preserve its annotations and use a new room revision to compare broader capture.

## Animated scan acceptance (not yet run on hardware)

- On first detection, confirm white edges trace in once, with a subtle halo. Continue scanning the same patch: its outline must refine without repeatedly disappearing/restarting. Check thin outlines leave the camera unobstructed.
- Watch the miniature gain only observed patches, with shaded thin surfaces. Turn the phone across the +/-180-degree heading boundary: it should turn smoothly, not spin the long way. Look at floor/wall junctions and check depth ordering from several headings.
- Enable Settings → Accessibility → Motion → Reduce Motion. New surfaces should appear without the growing/reveal effect. Repeat a scan and background/return to check removed/restarted plane geometry does not linger.
- Compare appearance and performance on the iPhone 12 mini. Classifying windows/furniture like Apple's RoomPlan video is not an acceptance claim for this camera-only path; physical registration/recognition must still pass separately.

## Tracking and usability polish acceptance

- Start with a newly detected plane: Lock view must wait for the brief settling gate. Compare the mint target against actual edges; a settled wrong plane must not be accepted as physically correct merely because it is mint.
- Move too fast, face a blank wall, then return to a textured corner. Verify reason-specific advice and recovery. Cover the camera briefly during a stroke: that stroke must end, saved data must remain, and drawing must require a fresh touch after verified alignment.
- Lock view while moving/turning the phone: the snapshot must be rejected with a hold-steady message if camera pose changes appreciably. Hold still and retry, then check the resulting drawing from a second viewpoint.
- Test interruption/recovery and both explicit restart actions. No drawings may remain visible at an unverified origin. New-scan restart must warn before discarding its unsaved scan.
- Test project search, empty/no-result states, room progress (zero/some/all tasks complete), status changes, long titles, large text and save failures. Task status and progress must persist through relaunch.
- Profile FPS/energy and record wall placement/recovery error on the camera-only iPhone before claiming performance/accuracy improvements.

## Long-scan crash/performance acceptance

1. Keep Device Hub screen viewing off. Record iPhone model, iOS, room size, scan duration, thermal state and whether the failure occurs while scanning or saving. Do not delete the app or saved project to diagnose it.
2. Scan the same room for 2, 5 and 10 minutes, repeatedly revisiting surfaces. Profile CPU, memory, frame pacing and allocations with Xcode Instruments; record values rather than inferring performance from simulator timing. Confirm rendering remains capped and old outlines disappear when their geometry is removed/refined.
3. Simulate a memory warning in the simulator; on hardware observe genuine pressure/thermal changes. Reduced detail must release visual resources while preserving tasks/map references. Check that a real targeted surface remains placeable even when omitted from the displayed overview.
4. Finish/save, close, reopen and recover the same room. Verify each instruction's position and task status. ARKit map memory is independent of the display budget; do not treat a building-sized scan as one room.
5. If the app exits, retrieve the SiteAR crash .ips or JetsamEvent report from Xcode/device diagnostics (or iPhone Settings → Privacy & Security → Analytics & Improvements → Analytics Data). Correlate timestamp/process and termination reason. A memory-pressure report, watchdog timeout and exception require different conclusions. Current development cannot label this crash fixed without that evidence and a successful hardware rerun.

## Minimal scan overlay check

Check Cancel/Finish over bright and dark real camera scenes, including disabled Finish. The coaching capsule should stay brief, the miniature should float near the bottom and the lower-left control should open Scan progress, tracking guidance and recovery options. Verify counts remain accessible in that sheet, the reduced-detail leaf has a VoiceOver label, and camera-denied/unsupported states do not incorrectly ask the user to keep moving. Repeat with large text; keep the renderer budgets unchanged.
