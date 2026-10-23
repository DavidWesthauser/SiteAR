# SiteAR

Native iPhone spatial work instructions, built with SwiftUI, ARKit, RealityKit and Supabase. iOS 17+, A12 or newer recommended; **LiDAR is not required**. Open **`SiteAR.xcodeproj`** and choose the **SiteAR** scheme. There are no third-party iOS dependencies.

The repository contains the application implementation, a reproducible backend and automated tests. **Cross-device AR accuracy has not yet been verified on hardware.** Do not treat compilation or mathematical tests as evidence of real-world localization accuracy. See [verification status](docs/VERIFICATION.md).

## Run without login while Supabase is unconfigured

Unconfigured **Debug builds** open directly into an empty project list. Create your own project and room, then choose **Map room** on a physical iPhone. Real ARWorldMaps, marker images, instructions and task changes are saved in the app's Application Support directory (`SiteAR/local.json` and `SiteAR/assets/`). There is no example project or pre-placed AR content. Relaunching restores your saved data; deleting the app deletes these local files.

The simulator can exercise navigation and room management; it cannot perform camera-based room mapping. Cloud sharing needs Supabase. Configure Supabase and rebuild to restore normal account authentication; local projects are kept separate and are not automatically uploaded. Release builds continue to require backend configuration.

## First-time installation on your own iPhone (including Germany)

You need your Mac, Xcode, an Apple Account, a USB data cable, an internet connection and an ARKit-compatible iPhone running **iOS 17 or later**. LiDAR is not needed. Xcode is already installed at `/Applications/Xcode.app` on the Mac used for this repository.

Germany uses the same direct Xcode development workflow. Developer Mode is a general requirement for this workflow. You can test with a **free Apple Account / Personal Team**; a paid Apple Developer Program membership is not required for this app's initial on-device test. With a Personal Team, provisioning expires after **7 days**: reconnect and run from Xcode again. This matters when testing persistence over several days—reinstall over the existing app rather than deleting it. See [Apple's account and Personal Team guidance](https://developer.apple.com/help/account/basics/about-your-developer-account).

For a local iPhone test, complete steps 1–2 and 5–6; you can skip Supabase steps 3–4 for now. An unconfigured Debug build saves real maps and instructions on your phone without login. Set up Supabase when you want accounts and cross-device sharing.

### 1. Prepare Xcode on the Mac

1. Open **Xcode** from Applications. Accept its licence and let any first-launch component installation finish. If asked which platforms to install, include **iOS**.
2. Open **Xcode → Settings → Apple Accounts** (called **Accounts** in some versions).
3. Click **+**, choose Apple Account if prompted, and sign in. Complete two-factor authentication.
4. Your account should show a **Personal Team**, or your existing paid team. If Apple asks you to accept a developer agreement, follow that prompt; free developer registration is available at [developer.apple.com/account](https://developer.apple.com/account/).
5. For command-line builds, choose this Xcode under **Xcode → Settings → Locations → Command Line Tools**. Clicking Run in Xcode does not require a Terminal command.

### 2. Connect and prepare the iPhone

1. Unlock the iPhone and connect it to the Mac with a **data-capable** USB cable. Keep it unlocked during setup.
2. If the Mac asks whether to allow the accessory to connect, click **Allow**.
3. On the iPhone, accept **Trust This Computer?** / **Diesem Computer vertrauen?**, tap **Trust / Vertrauen**, and enter the iPhone passcode.
4. In Xcode, open **Window → Device Hub**, or **Window → Devices and Simulators** in older versions. Select your iPhone and finish pairing if requested. Let device preparation finish; the first connection may take several minutes.
5. On the iPhone open **Settings → Privacy & Security → Developer Mode**. With German system language: **Einstellungen → Datenschutz & Sicherheit → Entwicklermodus**. It is near the bottom of the page.
6. Turn Developer Mode on and accept the restart. After restarting, unlock the phone, confirm **Enable / Aktivieren**, and enter its passcode if requested.
7. Reconnect/unlock the phone if needed and wait until Xcode shows it ready.

**If Developer Mode is missing:** first initiate pairing in Xcode, then check the iPhone settings again. Apple only exposes the setting after pairing has started or the device was previously paired. Follow [Apple's Developer Mode instructions](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).

### 3. Set up a hosted Supabase development project (optional for local testing)

Using the hosted dashboard is the simplest first test; no Supabase CLI, Docker or local server is needed.

1. Open [Supabase Dashboard](https://supabase.com/dashboard), sign in and create a **new development project**, for example `SiteAR-test`. Choose a nearby European region, such as Frankfurt if offered. Wait for provisioning to finish.
2. Open the project's **SQL Editor** and create a new query.
3. On the Mac, open `supabase/migrations/202610230001_sitear.sql` in a text editor. Copy **the entire file**, paste it into the SQL Editor, and click **Run**. Then run `supabase/migrations/202610230002_scan_and_draw.sql` the same way. Then run `supabase/migrations/202610230003_images_and_strokes.sql`. Run these migrations once each, in order, on the new project. It creates the tables, access policies, functions and private `room-assets` bucket. If it reports an error, resolve that before continuing; do not repeatedly rerun parts at random.
4. In **Table Editor**, check that `projects`, `memberships`, `rooms` and `annotations` exist. In **Storage**, check that `room-assets` exists and is **private**. The bucket starts empty.
5. Open **Authentication → Sign In / Providers** (or **Providers**, depending on the dashboard version), select **Email**, and allow email/password sign-up.
6. For a dedicated first-test project, you can turn **Confirm Email** off and save. This lets you create test accounts without configuring email delivery. For production, enable confirmation and configure SMTP. If confirmation stays on, confirm the email before signing in. See [Supabase's email settings](https://supabase.com/docs/guides/auth/general-configuration).
7. Open the project's **Connect** dialog and copy its **Project URL** and **publishable key**. Alternatively, find the key under **Settings → API Keys**. The URL looks like `https://abcdefghijklmnopqrst.supabase.co`; a new publishable key starts with `sb_publishable_`. See [Supabase's URL/key instructions](https://supabase.com/docs/guides/api/creating-routes).

Do **not** run `supabase/seed.sql` on this hosted project. It is for the local development stack only. Create your test users through the app. Do not copy a database password, secret API key or service-role key into the iOS app.

### 4. Put the backend settings in the app (if using Supabase)

1. In Finder, open this repository, then `SiteAR/Resources`.
2. Duplicate **`Secrets.example.xcconfig`** and name the copy exactly **`Secrets.xcconfig`**. Check that the filename is not `Secrets.xcconfig.txt`. Use a plain-text editor such as Xcode to edit it.
3. Replace the two settings with your actual project values:

   ```xcconfig
   SUPABASE_URL = https:/$()/abcdefghijklmnopqrst.supabase.co
   SUPABASE_ANON_KEY = sb_publishable_REPLACE_WITH_YOUR_ACTUAL_KEY
   ```

   Replace the example project reference and key. **Keep `https:/$()/` exactly as written**: Xcode expands it into `https://`; a literal `//` starts an xcconfig comment. Do not add quotes. The setting name `SUPABASE_ANON_KEY` is retained by this app even when its value is a newer publishable key. A legacy `anon` key is also supported.
4. Save the file. `Config.xcconfig` already includes it; you do not need to add it to Copy Bundle Resources. It is ignored by Git.

### 5. Open the project and configure signing

1. In Finder, double-click **`SiteAR.xcodeproj`** in the repository root. Open the Xcode project, rather than just `Package.swift`.
2. In Xcode's left sidebar, click the blue **SiteAR project** icon. Under **TARGETS**, choose **SiteAR**.
3. Open **Signing & Capabilities**, enable **Automatically manage signing**, and choose your **Personal Team** or existing paid team.
4. Give the app a unique **Bundle Identifier**, for example `de.david.sitear.dev` (substitute your own unique name). This identifies your app to Apple's signing system; you do not need to own that domain for a local test.
5. If you prefer editing the repository setting directly, change `PRODUCT_BUNDLE_IDENTIFIER` in `SiteAR/Resources/Config.xcconfig`. The default `com.example.SiteAR` is a placeholder. The optional Secrets file is included *before* that default, so putting a bundle identifier only in Secrets.xcconfig does not override it.
6. At the top of Xcode, select the **SiteAR** scheme and choose **your physical iPhone's name** as the run destination. Do not choose a simulator or the generic “Any iOS Device” destination.
7. Allow Xcode to register the device/create signing assets if prompted. Ordinary Run builds the app; you only need to configure the test targets' signing too if you later run on-device tests.

Apple documents this [physical-device signing and Run workflow](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices).

### 6. Install and launch

1. Leave the iPhone connected and unlocked. Click Xcode's **▶ Run** button or press **Command-R**.
2. Wait for the build and installation. Xcode should launch **SiteAR** on the phone.
3. If iOS says the developer is untrusted, open **Settings → General → VPN & Device Management** / **Einstellungen → Allgemein → VPN und Geräteverwaltung**. Under the development-app entry, select your own developer account and follow the trust/verification prompts. Then run again. This step only applies if iOS presents that message.
4. Without Supabase, the Debug build opens Projects directly; skip registration. With Supabase configured, turn on **I need an account**, enter an email and password of at least eight characters, and tap **Register**. With email confirmation disabled for the test project, you should enter Projects directly. Otherwise confirm your email, return to the app and sign in.
5. Create a project and a room. Open **Map room**, and allow camera access when asked.
6. Test by looking through and moving the **actual iPhone camera**. Keep Device Hub’s **View Screen** / physical-device mirroring off: Apple disables camera access during that interaction, which produces black AR video. The USB cable and Xcode debugger can remain connected.

Once installed, you can open SiteAR from its Home Screen icon. You can disconnect the USB cable for walking around; keep internet access for cloud loads/saves. If a free team's provisioning expires, reconnect and press Command-R to reinstall over the existing app. Do not delete the app just to renew its signature.

### 7. Scan → draw → recognize the room again

1. In your project add a room, choose **Map room**, and move slowly around textured walls and the floor. The scan screen has Cancel/Finish at the top and a floating live surface overview below. Thin white boundaries mark ARKit-detected plane patches; there are no filled wall/floor faces obscuring the camera. The **Live scan** overview shows vertical/horizontal surface counts, viewing-direction/position counts and map readiness. It is not a percentage of the whole room covered.
2. Walk through the room, looking in all four directions from at least three positions separated by 0.5 m. The overview shows viewing-direction and position counts; spinning in place is insufficient. These are movement checks, not a guarantee of whole-room feature coverage. When those checks pass, tracking is stable, ARKit has a usable world map and at least one plane is detected, tap **Fertig**. This saves the room and continues directly into drawing in the **same AR session**. No manual reference dots, marker print, or separate confirmation is required.
3. Aim at a detected surface and choose **Lock view** to hold the camera image and drawing plane. The editor has three tools: **Zeichnen**, **Fläche**, and **Bild**. For drawing, drag your finger; **lifting your finger ends the stroke**. Drawing elsewhere starts a separate stroke without a connecting line. Rounded, smoothed strokes have no visible sample dots. Undo removes the last stroke. **Fläche** uses tapped coplanar corners.
4. Choose **Bild**, select a photo or PNG/JPEG file, adjust its physical width, then tap the surface to place it. Its aspect ratio is preserved. The real image file and room-relative placement are saved together and restored on reopening. Optional title, description and priority are entered in **Arbeitsanweisung**; these are task details attached to your drawing, area or image. Existing older pin/text/arrow instructions still load, but their creation tools are removed.
5. Tap **Speichern** in the fixed bottom bar. **Resume camera** returns to live AR; tracking continues while the image is frozen, and tracking loss releases it. The first placement locks the surface even in live mode. The aimed plane is highlighted in mint before placement; the editor shows its orientation and distance. Placement requires detected plane geometry within 0.15–5 m: estimated-plane fallback is disabled to avoid silently guessing depth. A boundary is not a window/furniture detector or a guarantee of physical accuracy. If surface detection is poor, use the measured-distance placement settings. Use **Scan more surfaces** to inspect missed walls; outlines show detected patches, not complete coverage. Worker outlines default off.
6. Images, drawings and tasks persist in room coordinates. Drawings allow up to 32 independent strokes, 256 samples per stroke and 2,048 samples total. Save longer drawings as several instructions. Portrait orientation is fixed. Save before closing; force-quitting loses unsaved work.
7. Close AR, force-quit SiteAR, then reopen the saved room and choose **Start AR walkthrough**. Look around from viewpoints used in the original scan. After ARKit recovers the saved map, restores the correct room anchor and provides stable normal tracking, drawings appear automatically. No reference-dot selection is required.
8. Walk around the drawings, open a task and change its status. If tracking is lost, overlays hide while the app attempts to recover the saved room. If recognition times out, choose **Ohne Neustart weitersuchen** to continue the same session. Look at distinctive details from areas visited while mapping; **Scan room again** explicitly restarts recovery. The app does not display drawings at an arbitrary origin.
9. For another user's phone, configure Supabase, install all three migrations, share the project, and open the same room on that device. Local-only rooms stay on their original phone and are not automatically uploaded.

An **optional recovery marker** is available in a collapsed section while scanning. Existing rooms with saved reference points retain manual recovery; creating new rooms does not require them. If fallback marker/manual alignment is used, it still requires explicit confirmation. Never confirm a moved marker.

Apple's RoomPlan demo uses LiDAR to classify and outline room objects. This app uses ARKit plane detection on camera-only iPhones such as the iPhone 12 mini. Its live surface boundaries and shaded miniature represent detected plane patches, **not** classified furniture, a complete architectural model, or proof that every wall is scanned. See [Apple's RoomPlan description](https://machinelearning.apple.com/research/roomplan).

### First-install troubleshooting

| What you see | What to do |
|---|---|
| iPhone absent from Xcode's device list | Unlock it, use a data cable, accept Trust, and open Device Hub / Devices and Simulators to pair. |
| Developer Mode missing or disabled | Initiate Xcode pairing first, then enable it in Datenschutz & Sicherheit, restart and confirm. A managed phone may require its administrator's help. |
| “Signing requires a development team” | SiteAR target → Signing & Capabilities → choose your team and enable automatic signing. |
| Bundle identifier unavailable | Choose a unique identifier instead of `com.example.SiteAR`. |
| Xcode says the iOS version/device support is unavailable | Install an Xcode version that supports the phone's installed iOS and finish its required platform/component downloads. |
| App installed but reports “Configure SUPABASE_URL…” | Check the exact Secrets.xcconfig filename and values, preserve the URL escape, save, then rebuild with Command-R. |
| “Email not confirmed” / no confirmation email | In the development project's Auth settings disable confirmation for initial test accounts, or configure SMTP and complete confirmation. Check existing test users in Authentication → Users. |
| Missing table/function or access-policy errors | Check that the full migration succeeded on the same Supabase project whose URL/key you copied. |
| Camera view is black while controls appear | Stop Device Hub physical-device screen viewing/mirroring, close and reopen AR on the iPhone. [Apple documents that mirroring blocks the camera](https://developer.apple.com/documentation/xcode/interacting-with-your-app-in-device-hub). |
| Camera permission denied | iPhone Settings → Privacy & Security → Camera (Datenschutz & Sicherheit → Kamera) → enable SiteAR. |
| App stops launching after about seven days | Reconnect, select the same team and bundle ID, and Run from Xcode again; free Personal Team provisioning expires. |

For CLI-based backend setup instead of the hosted dashboard, run `supabase login`, `supabase link --project-ref YOUR_PROJECT_REF`, then `supabase db push`. Cloud account and sharing workflows require Supabase. Unconfigured Debug builds support real AR with on-device persistence.

## Run the workflow

**Create project → add room → scan → finish scan & draw → save drawings → return later → scan to recognize room → view drawings and complete tasks.**

Use the step-by-step procedure above. Each room has its own immutable saved map and coordinate system. To replace a map after major physical changes, create a new room revision rather than silently moving existing instructions. Managers can edit/delete drawings and share cloud projects; workers can view drawings and update task statuses. Task lists remain accessible when localization is unavailable.

## Tests

Portable macOS tests (spatial core, backend with URLProtocol fixtures, view models; no credentials needed):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

In a restricted environment set `CLANG_MODULE_CACHE_PATH=/tmp/sitear-module-cache` and `SWIFTPM_MODULECACHE_OVERRIDE=/tmp/sitear-module-cache`, and use `--scratch-path /tmp/sitear-swift-build`. `--disable-sandbox` may be needed for SwiftPM inside an existing sandbox.

Build app and test bundles without running a simulator:

```sh
xcodebuild -project SiteAR.xcodeproj -scheme SiteAR \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/sitear-derived CODE_SIGNING_ALLOWED=NO build-for-testing
```

Run tests with an **installed** simulator runtime, replacing the device name with one from `xcrun simctl list devices available`:

```sh
xcodebuild -project SiteAR.xcodeproj -scheme SiteAR \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

The navigation/CRUD UI test requires a dedicated test account. In **Edit Scheme → Test → Arguments → Environment Variables**, set `SITEAR_TEST_EMAIL` and `SITEAR_TEST_PASSWORD`. It creates and deletes only its uniquely named test project. It skips explicitly when credentials are absent. A previously signed-in account should be signed out before the authentication UI test. Do not use a production account for tests.

Local Supabase (requires CLI and Docker):

```sh
supabase start
supabase db reset
supabase test db
```

The seed creates `manager@sitear.test`, `worker@sitear.test`, `outsider@sitear.test` with password `SiteAR-local-2026!` and an **unmapped** fixture room. These identities are only for the local development stack. Never run seed.sql in production. No fake map or simulated AR event is used in the real application. The pgTAP test supplies synthetic spatial metadata inside a rolled-back SQL transaction exclusively to test access rules.

To connect a physical iPhone to a local Supabase stack, expose it through a trusted HTTPS development endpoint and configure that URL. `localhost` on the phone is the phone itself. Prefer a separate hosted development project for the two-device AR test. Do not disable App Transport Security globally.

## Repository

- `SiteAR/App`: entry point and observable application store.
- `SiteAR/Core`: versioned spatial models, rigid-transform validation, alignment calculations and localization state machine.
- `SiteAR/AR`: ARKit session lifecycle, secure world-map archive, image detection, raycasts, RealityKit geometry and marker printing.
- `SiteAR/Services`: Supabase Auth/REST/Storage client, token refresh and Keychain storage.
- `SiteAR/Views`: authentication, projects/rooms/sharing, AR tools, tasks and settings.
- `supabase`: migration, private bucket/RLS policies, local fixtures and policy tests.
- `SiteARTests`, `SiteARAppTests`, `SiteARUITests`: deterministic and UI tests.
- `scripts/generate_project.py`: deterministic, dependency-free project regeneration when adding/removing Swift files.

See [architecture](docs/ARCHITECTURE.md), [requirements and effort](docs/REQUIREMENTS.md), [hardware acceptance procedure](docs/DEVICE_TESTING.md), and [verification / limitations](docs/VERIFICATION.md).

### Recognizing the room from more places

ARWorldMap already stores a spatial visual-feature map. A separate visible mesh does not supply viewpoint-independent relocalization on a camera-only phone. The initial scan now checks multiple positions and viewing directions before enabling Finish. Walk the room perimeter where safe, include corners, doors and textured objects from both directions, then look back across the room. Old maps do not acquire missing observations automatically: for a broader scan, create a new room revision and place its drawings there. Existing annotations/maps are not silently rebased or replaced.

Recovery can succeed from different **previously observed** areas, but cannot be guaranteed from any point, a blank wall, changed furniture or different lighting. The direction/position counters are coaching heuristics, not recognition confidence. No new 3D reconstruction pipeline or LiDAR dependency has been added.

### Scan appearance and animation

Detected surface outlines draw in over about 0.6 seconds with a subtle white halo; the targeted surface is mint. Plane updates reuse existing outline entities so they do not constantly restart the reveal. The floating miniature shows shaded thickness on actual observed patches, fades/grows new patches, interpolates refinements and turns with the camera heading. Reduce Motion disables reveal/interpolation. This is a live view of ARKit patches, not classified windows, cabinets or furniture.

The supplied RoomPlan clip was reviewed at three timestamps, not extracted frame by frame. Apple's RoomPlan supplies semantic recognition and its own native scanning visuals on LiDAR devices. SiteAR's camera-only implementation does not claim that detector or promotional recognition quality. The animation revision at commit `88d4de7` passed simulator checks, was installed on the iPhone 12 mini and launched successfully. Physical AR accuracy and recovery quality still need testing.
