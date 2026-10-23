# Architecture and spatial contract

SwiftUI views use a main-actor Store for cloud/local records and errors. Backend owns Supabase authentication and requests; URLSession is injected for tests. ARController owns one ARView/session and the scan → draw transition. Pure value types own spatial validation, scan readiness and alignment calculations. No reconstruction pipeline or realtime layer is involved.

## Coordinates and persistence

Positions are metres in ARKit's right-handed gravity-aligned coordinates. Pose is a column-major 16-float rigid matrix, rejecting scale, reflections and non-finite values. Room data uses spatial_version 1 and an immutable coordinate_id.

- During a new scan, the AR session frame is the room frame. A named `SiteAR.room.<coordinate_id>` anchor at identity is included in the saved ARWorldMap.
- Instructions store roomFromAnnotation plus local vertices. Areas/lines/arrows are real 3D geometry.
- A detected surface stores its ARPlaneAnchor pose and boundary vertices. The optional surfaces field is backward-compatible with older local JSON and is added to cloud rooms by migration 002.
- Saving the scan archives its map and publishes room metadata. The manager continues drawing in that SAME session with an identity room-to-session transform; no second recognition attempt is needed.
- On a revisit, initialWorldMap attempts to recover the saved coordinates. Only a restored matching room anchor, at least two seconds of normal tracking, and extending/mapped world-map evidence allow automatic recovery. Loading a file alone is insufficient.
- Rendering multiplies sessionFromRoom × roomFromAnnotation. Placement converts session-space raycasts with inverse(sessionFromRoom).

Automatic map recovery no longer requires selecting manual dots or tapping confirmation. It uses ARKit's tracking/relocalization evidence, not an assertion of survey accuracy. Users should inspect drawings against the real room, especially before consequential work. Tracking loss hides annotations and starts another recognition attempt. Failed recognition never falls back to an arbitrary identity origin. Sessions time out after 40 seconds and expose continued searching without resetting the AR session, plus an explicit restart. Existing sparse maps remain sparse; no mesh or arbitrary identity transform is used to pretend recognition succeeded.

## Live scanning feedback

ARPlaneAnchor add/update/remove events drive thin boundary outlines in RealityKit, with no filled surface meshes, plus surface/feature counts and an isometric SwiftUI Canvas overview. Merged/removed planes are removed from the overview. Readiness requires normal tracking stable for two seconds, mapped status, at least one detected plane, and multi-view movement evidence: all four horizontal heading sectors plus three observed positions at least 0.5 m apart. Observations count only with normal tracking and extending/mapped status. ScanCoverage is pure, bounded and reset with the map session; it is not a reconstruction or feature-visibility proof. This is readiness to save a useful spatial reference, not a percentage of the room scanned.

Initial placement and Lock view use existingPlaneGeometry only, bounded to 0.15–5 m; no silent estimatedPlane fallback is allowed. The targeted plane is highlighted in mint before a drawing is locked, with orientation/distance in the editor. Explicit measured-distance placement follows the actual crosshair ray instead of the camera forward vector. Boundary simplification tolerance is 5 mm, retaining smaller detected corners. These changes do not remove camera-only plane estimation error or AR tracking drift.

The scan overlay prioritizes the camera with Cancel/Finish, a floating boundary overview, detected-surface counts and map-readiness stages. It never reports a fabricated coverage percentage.

Plane alignment distinguishes vertical/horizontal candidates, not semantic walls/furniture. The overview projects real boundary geometry; it is not a generated miniature building. The app does not require RoomPlan or LiDAR. Scene depth is optional when supported. No Gaussian Splatting, furniture classification or 3D export is implemented.

## Drawing

The creation toolbar exposes drawing, area and image only. Legacy pin/text/arrow records remain readable. A FreehandDraft owns separate paths: touch-down begins, lift/cancel ends, and a single-point tap is discarded. A 3 mm sampling threshold and caps of 32 paths, 256 samples/path and 2,048 total bound storage/rendering. Two Chaikin passes smooth each path independently; RealityKit renders a round tube mesh per path. Areas use tapped coplanar corners without vertex dots. Undo removes one whole stroke.

Images are imported through PhotosPicker or the file picker, normalized with ImageIO to a maximum 2,048-pixel dimension, then saved as PNG in private project/room assets before the annotation record. The record stores path plus physical width/height, preserving aspect ratio. RealityKit uses a two-sided textured quad; frozen editing perspective-warps the same image to the selected plane. Missing assets report an error while the conventional task list stays available. Migration 003 adds optional image/strokes fields; older single-path records decode unchanged.

The bottom Save bar stays outside the scrollable tools. Work details and measured-distance inputs use native forms in sheets to keep the keyboard away from AR controls. Saved entity collisions allow task selection; scan overlays have no selectable collision geometry.

## Optional recovery

The initial scan has no required marker or manual references. A collapsed optional marker workflow imports/generates a unique print, calibrates full-image width and records roomFromMarker. Marker fallback deliberately starts a fresh session WITHOUT initialWorldMap:

`sessionFromRoom = sessionFromMarker × inverse(roomFromMarker)`

This candidate requires explicit confirmation because a physical print may have moved. Its transform is frozen after detection, then world tracking continues without the image staying visible. Older rooms containing two described reference points retain a gravity-aligned manual yaw/translation fallback with explicit confirmation. New rooms require neither dots nor a marker. The two reference points, when present, must have a consistent baseline over 30 cm horizontally.

## Storage and access

Unconfigured iOS Debug builds start empty and save JSON plus real AR map/marker assets in Application Support. Local mode has no account or sharing, and does not create sample content. Configured builds use authenticated Supabase; Release builds require cloud configuration. Local data does not automatically migrate to the backend.

Cloud projects have one owner/manager; memberships grant worker access. RLS/grants protect all tables and private Storage. Workers can read assigned projects and call a narrow task-status RPC; manager-only actions manage geometry/maps/access. Foreign keys bind annotations to the exact room coordinate revision. Published maps and coordinate metadata are immutable; migration 002 also protects persisted surface geometry while making manual references optional.

Maps use secure NSKeyedArchiver archives and ARWorldMap-restricted unarchiving. Assets have unique project/room paths and upload before room publication. Failed uploads can leave private orphan assets; cleanup via the Storage API remains operational work. Publication retry is idempotent if a response is lost. Local JSON and asset writes are atomic.

Tokens use Keychain WhenUnlockedThisDeviceOnly; refresh requests share an in-flight task. Sync is explicit, without realtime conflict resolution/revocation. Drafts survive tracking resets while the AR screen remains open; process termination loses unsaved work. Backgrounding a new scan restarts scanning; revisiting a saved room requires recovery. Keep physical-device Device Hub screen viewing OFF during camera testing: Apple blocks camera/mic access while it is active.

References: [Apple world maps](https://developer.apple.com/documentation/arkit/arworldmap), [world tracking](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration), [RoomPlan and LiDAR](https://machinelearning.apple.com/research/roomplan), [Device Hub camera conflicts](https://developer.apple.com/documentation/xcode/interacting-with-your-app-in-device-hub), [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security).

## Stable drawing

The first successful placement fixes a drawing-plane pose in ROOM coordinates. Later screen rays intersect that same plane instead of reraycasting independently against shifting estimates. Annotation poses retain this plane orientation, with vertices transformed into its local XY coordinates. Images and legacy text retain the selected surface orientation.

Lock view captures ARView's actual camera/scene snapshot and the matching camera view/projection matrices. A Canvas editing overlay projects real room-space draft vertices onto the frozen image. Gestures unproject against the captured camera matrix and intersect the locked plane. ARSession keeps tracking underneath; interruption/tracking loss releases the editing snapshot. Saved output remains normal RealityKit 3D geometry, not a persistent image overlay. Snapshot/projection capture timing and physical tracking accuracy still need hardware validation.

Legacy arrows retain their shaft and triangular head. Freehand line/area control points are not rendered in walkthroughs, and scan guides default off there. Lock view does not guarantee removal of ARKit world-tracking drift. The app's UI remains portrait.
