# Testing

## Desktop concept (OpenXR off)

The main scene is `scenes/main_desktop.tscn`. Scroll the mouse wheel to move
between Orbit / Region / RTS distances. Click a glowing pin (the only
accessible region is Verdant Basin). Rare-resource icons (iron / coal) appear
on the Tier 1 pins only after the player reaches that node's `reveal_era`
(coal at the steam era, iron at era 2). They stay hidden at Stone.
The faint axial hex overlay appears only in Tier 3 when a build or
outpost (claim) order is pending.

Left-click selects a unit, right-click moves or assigns gather. HUD buttons
train units (basic workers/soldiers use only common resources; Ironclads and
Steamwalkers need rare iron/coal) and enter build mode. Space pauses the sim.
P possesses a selected unit (WASD to walk). Esc releases.

**Tier 4 skirmish possession.** Put a soldier in an enemy-held hex of a
revealed rare node and press **Contest (possess)**. The controller possesses
one squad member (the selected unit if it is in the squad) and switches to
the SpringArm3D camera with the touch overlay: joystick bottom-left, Attack
and Auto-resolve bottom-right. Desktop keys: WASD / arrows move
(camera-relative), F or J attack, Q / E turn the camera, Esc auto-resolves.
The strategic tick is held while the fight is live and resumes once the
skirmish is resolved. If nobody can be possessed, the skirmish auto-battles.

If the editor warns that Vulkan is not supported, switch the renderer to
**Compatibility** (`--rendering-method gl_compatibility`).

## Android APK (debug, arm64)

`export_presets.cfg` has an **Android** preset (no Gradle build, arm64-v8a,
Compatibility renderer on mobile, landscape). With the Godot 4.4.1 export
templates installed and the Android SDK / debug keystore set in Editor
Settings:

```bash
godot --headless --path . --export-debug "Android" build/competitive-evolution-agr.apk
```

Touch controls (mobile builds only): pinch to zoom between the tiers,
one-finger drag to orbit, tap a glowing pin to enter the region, tap a unit
to select it, then tap the ground or a resource node to move / gather. HUD
buttons work as on desktop; Tier 4 possession uses the on-screen joystick
and Attack / Auto-resolve buttons.

## Android AR APK (ARCore, Gradle)

1. Install an Android SDK with `platforms;android-33`, `platforms;android-34`,
   `build-tools;33.0.2`, `build-tools;34.0.0`, `cmake;3.22.1` and
   `ndk;23.2.8568313`, plus JDK 17 and `pip install scons`.
2. Build and install the patched plugin (Godot **4.4+** only; 4.3 lacks the
   `CameraFeed` APIs the passthrough needs):
   `ANDROID_HOME=/path/to/sdk GODOT_BIN=/path/to/godot-4.4.1 tools/arcore_plugin/build_arcore_plugin.sh`
   (this creates `addons/ARCorePlugin/bin/` and `plugin.gdextension`).
3. Export the **Android AR** preset (Gradle build, camera permission,
   minSdk 24), e.g. headless:
   `godot --headless --path . --install-android-build-template --export-release "Android AR" build/competitive-evolution-agr-ar.apk`

   **Export release (non-debuggable) builds for phones.** On Samsung phones
   with Google Play Services for AR 1.52+, ARCore barely tracks in a
   *debuggable* app: no feature points, no planes, anchors drift
   (google-ar/arcore-android-sdk#1750, #1757). A Godot debug export is always
   debuggable. For a sideloaded test build, sign the release export with the
   Godot debug keystore through environment variables, so no secrets go in
   the repo:

   ```bash
   export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=~/.local/share/godot/keystores/debug.keystore
   export GODOT_ANDROID_KEYSTORE_RELEASE_USER=androiddebugkey
   export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=android
   ```
   The Linux/Windows editor logs "No GDExtension library found for current
   OS" for this Android-only plugin; that is expected.
   After step 2, the plain **Android** preset no longer exports: a
   GDExtension Android plugin needs a Gradle build.

On the phone the game starts in a three-step calibration. The simulation is
paused and the gameplay HUD is hidden until the board is locked, so no ticks
run and no win can be checked during setup.

1. **Find a surface.** Sweep the phone slowly over a textured table or floor.
   The banner shows live ARCore tracking (too dark, moving too fast, not
   enough detail…) plus feature-point and surface counts, and the detected
   points and surfaces are drawn as a light overlay. After ~12 s without a
   surface, **Place in front of me** (about 0.6 m ahead and 0.35 m below the
   phone) and **Play without AR** are offered.
2. **Place.** When the ring reticle sits on a surface, press **Place board**
   or tap anywhere.
3. **Adjust.** Drag to move, pinch to scale and twist to rotate, then press
   **Lock** to start play. **Re-place** goes back to step 1.

If ARCore is not tracking yet, **Place in front of me** holds the board in
front of the camera (it never slides away) and turns it into a world anchor
after one second of continuous tracking.

Tap the step panel five times to show the AR debug line. It also shows by
itself after the scan timeout and in debuggable builds. It lists, in order:
interface initialized, primary XR interface, `use_xr`, the `ArSession_resume`
and `ArSession_configure` status, the last `ArSession_update` status (with
ok/error counts), the camera tracking state and failure reason, the number of
tracked frames, new camera frames (timestamp changes), feature points and the
point-cloud status, surfaces (upward / any state), the camera texture id, the
camera position, the display size, the ARCore (Play Services for AR) version,
and whether the app is debuggable.

Registration note: Godot 4.4's camera-feed background stretches the whole
camera texture over the screen, with no crop. The patched plugin therefore
gives ARCore a "display" with the camera texture's aspect ratio
(`camtex` / `disp` in the debug line), so the projection and hit tests match
the stretched passthrough. Without this, virtual content came out ~1.6x too
large and swam against the real world.

Once locked, walk closer to zoom from Orbit → Region → RTS.

## Headless tests

```bash
godot --headless --path . --import
godot --headless --path . res://scenes/debug/smoke_test.tscn   # 14 passed
godot --headless --path . res://scenes/debug/sim_tests.tscn    # 165 passed
godot --headless --path . res://scenes/debug/ar_tests.tscn     # 102 passed
```

Both print `PASS` / `FAIL` lines and quit non-zero on failure when headless.

Sim tests cover: faction bootstrap (Humans + Sylvari + Kraal + Cogforged),
AI construction over N ticks, the player command path, common-node
depletion, Sylvari common-node regrowth (rare nodes do not regrow), Kraal
faster depletion, era-gated rare-node reveal (coal at the steam era / index 1,
iron at era 2; visibility is per-faction; AI only targets visible nodes),
rare-cost gating for later era advances and specialized units, Cogforged
extractors boosting rare-node yield, hex ownership and claimed-hex yield
split, full-control capture, the outpost escalation ladder, auto-battle
skirmishes that flip a captured outpost, the possession stub, occupation
blocking enemy claims, and destroying a structure releasing its claim. They also cover per-species era tracks, world-era soft-cap cost scaling, each win condition (plus species subsets), and determinism (same seed + command log => identical state hash).

Tier 4 possession tests cover: the request leaving the skirmish pending,
the capped attacking squad as possession candidates (no enemies, no
workers), starting the live fight (both squads plus the outpost guard),
quantized steering inside the arena, the boosted possessed strike and its
cooldown, the strategic tick being held (and a forced tick fighting the
skirmish out first), a field victory that captures the outpost through
`resolve_skirmish_possessed`, the auto-battle fallback mid-fight, the
timeout verdict, replaying a full possession fight from the command log to
the same state hash, and the SkirmishPossessionController (ignores AI
requests, possesses via CommandService, joystick -> steer sector, Attack ->
strike, Auto-resolve, resolving a finished fight, falling back to
auto-battle when no unit can be possessed).

AR tests (`ar_tests.tscn`) cover: mode selection and the fallback camera
loading when no XR interface is present (desktop rig current, no XR nodes,
identity anchor/pivot), diorama-local transforms and the sim state hash
staying unchanged when the anchor moves / scales / rotates / magnifies,
world hits converting back to diorama-local orders, AnchorService placement,
polling and tracking loss, the Cloud Anchor host/resolve stub (loopback
backend) and the share payload, placement math (lock, clamps, magnify about
the anchor, recenter, persistence), gestures (tap / drag / pinch / twist),
and effective-distance zoom tiers.

## Before AR export (not needed for this concept)

These are intentionally off so the project runs on a desktop or any phone
without an OpenXR runtime:

- `xr/openxr/enabled=true`
- `rendering/viewport/transparent_background=true`
- Install & enable the Godot OpenXR Vendors plugin.
- Point `application/run/main_scene` at `res://scenes/main_ar.tscn`.
