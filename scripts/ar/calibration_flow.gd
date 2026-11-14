class_name CalibrationFlow
extends RefCounted
## Pure state machine for placing the AR board (no nodes, unit-tested).
##
##   SCANNING       sweep the phone; live tracking status; after
##                  FALLBACK_OFFER_SECONDS offer "Place in front of me" and
##                  "Play without AR" so the player is never stuck.
##   SURFACE_FOUND  a reticle sits on a surface: "Place board" (or tap).
##   ADJUSTING      drag / pinch / twist the board, then Lock or Re-place.
##   LOCKED         the game runs. Unlock returns to ADJUSTING.
##
## The simulation (ticks and win checks) only runs while LOCKED.

enum Step { SCANNING, SURFACE_FOUND, ADJUSTING, LOCKED }

## Seconds of scanning without a surface before the fallbacks are offered.
const FALLBACK_OFFER_SECONDS: float = 12.0

## ArTrackingState as reported by ARCoreInterface.get_tracking_info().
const CAMERA_TRACKING: int = 0
const CAMERA_PAUSED: int = 1
const CAMERA_STOPPED: int = 2

## ArTrackingFailureReason.
const FAILURE_NONE: int = 0
const FAILURE_BAD_STATE: int = 1
const FAILURE_INSUFFICIENT_LIGHT: int = 2
const FAILURE_EXCESSIVE_MOTION: int = 3
const FAILURE_INSUFFICIENT_FEATURES: int = 4
const FAILURE_CAMERA_UNAVAILABLE: int = 5

var step: Step = Step.SCANNING
## Seconds spent scanning (SCANNING or SURFACE_FOUND) since the last (re)start.
var scan_seconds: float = 0.0
var last_info: Dictionary = {}
## Seconds the camera has reported TRACKING without a break.
var tracking_seconds: float = 0.0
## The board was placed in front of the camera before ARCore tracked; it
## follows the camera until tracking is stable, then becomes a world anchor.
var anchor_pending: bool = false

## Continuous TRACKING needed before a camera-held board is anchored.
const STABLE_TRACKING_SECONDS: float = 1.0


func restart() -> void:
	step = Step.SCANNING
	scan_seconds = 0.0
	anchor_pending = false


## Record the latest tracking diagnostics (call every frame in any step).
func observe(delta: float, info: Dictionary) -> void:
	last_info = info
	if int(info.get("camera_state", -1)) == CAMERA_TRACKING and int(info.get("frames", 0)) > 0:
		tracking_seconds += maxf(0.0, delta)
	else:
		tracking_seconds = 0.0


## True once tracking has held long enough to trust a world anchor.
func tracking_stable() -> bool:
	return tracking_seconds >= STABLE_TRACKING_SECONDS


## Advance one frame. `surface_found` is the reticle hit test result.
func update(delta: float, info: Dictionary, surface_found: bool) -> void:
	observe(delta, info)
	if step == Step.SCANNING or step == Step.SURFACE_FOUND:
		scan_seconds += maxf(0.0, delta)
		step = Step.SURFACE_FOUND if surface_found else Step.SCANNING


func placed() -> void:
	step = Step.ADJUSTING


func set_locked(locked: bool) -> void:
	if step == Step.ADJUSTING or step == Step.LOCKED:
		step = Step.LOCKED if locked else Step.ADJUSTING


func is_calibrating() -> bool:
	return step != Step.LOCKED


func should_run_simulation() -> bool:
	return step == Step.LOCKED


func offers_fallback() -> bool:
	return step == Step.SCANNING and scan_seconds >= FALLBACK_OFFER_SECONDS


func is_tracking() -> bool:
	return int(last_info.get("camera_state", -1)) == CAMERA_TRACKING


## Which HUD controls are visible for the current step.
func controls() -> Dictionary:
	return {
		"place": step == Step.SURFACE_FOUND,
		"place_in_front": offers_fallback(),
		"play_without_ar": offers_fallback(),
		"lock": step == Step.ADJUSTING,
		"replace": step == Step.ADJUSTING or step == Step.LOCKED,
		"unlock": step == Step.LOCKED,
		"magnify": step == Step.LOCKED,
		"recenter": step == Step.ADJUSTING or step == Step.LOCKED,
		"sweep_hint": step == Step.SCANNING,
		"stats": step == Step.SCANNING or step == Step.SURFACE_FOUND,
	}


func title() -> String:
	match step:
		Step.SCANNING:
			return "Step 1 of 3 · Find a surface"
		Step.SURFACE_FOUND:
			return "Step 2 of 3 · Place the board"
		Step.ADJUSTING:
			return "Step 3 of 3 · Adjust, then lock"
		_:
			return ""


func message() -> String:
	match step:
		Step.SCANNING:
			var text: String = tracking_message(last_info)
			if offers_fallback():
				text += "\nNo surface yet? Place the board in front of you instead."
			return text
		Step.SURFACE_FOUND:
			return "Surface found. Tap Place board, or tap the screen."
		Step.ADJUSTING:
			if anchor_pending:
				return "Holding the board in front of you until AR tracking starts. Move the phone slowly; you can Lock and play now."
			return "Drag to move, pinch to resize, twist to rotate. Tap Lock to start playing."
		_:
			return "Walk closer to zoom in. Tap units to select, tap the ground to move."


## Plain-English tracking status from ARCoreInterface.get_tracking_info().
static func tracking_message(info: Dictionary) -> String:
	if info.is_empty() or int(info.get("frames", 0)) <= 0:
		return "Starting the camera…"
	var state: int = int(info.get("camera_state", -1))
	if state == CAMERA_TRACKING:
		if int(info.get("points", 0)) < 20:
			return "Sweep the phone slowly side to side over the table."
		return "Tracking. Keep sweeping over the table until a surface appears."
	if state == CAMERA_STOPPED:
		return "Tracking stopped. Tap Re-place, or restart the app."
	match int(info.get("failure_reason", FAILURE_NONE)):
		FAILURE_INSUFFICIENT_LIGHT:
			return "Tracking lost: too dark. Turn on a light."
		FAILURE_EXCESSIVE_MOTION:
			return "Tracking lost: moving too fast. Move the phone slowly."
		FAILURE_INSUFFICIENT_FEATURES:
			return "Tracking lost: not enough detail. Aim at a textured surface."
		FAILURE_CAMERA_UNAVAILABLE:
			return "Camera unavailable. Close other apps that use the camera."
		FAILURE_BAD_STATE:
			return "AR is recovering. Hold the phone steady for a moment."
		_:
			return "Getting started: move the phone slowly side to side."


const _STATE_NAMES: Dictionary = {-1: "none", 0: "TRACKING", 1: "PAUSED", 2: "STOPPED"}
const _REASON_NAMES: Dictionary = {0: "none", 1: "bad state", 2: "low light", 3: "fast motion", 4: "few features", 5: "camera unavailable"}


## One compact diagnostics line for the on-screen AR debug overlay.
static func debug_line(diag: Dictionary) -> String:
	if diag.is_empty():
		return "AR debug: no data from the ARCore plugin"
	var yes_no: Callable = func(key: String) -> String:
		return "Y" if bool(diag.get(key, false)) else "N"
	var state: int = int(diag.get("camera_state", -1))
	var parts: PackedStringArray = [
		"init %s" % yes_no.call("initialized"),
		"primary %s" % yes_no.call("is_primary"),
		"xr %s" % yes_no.call("use_xr"),
		"resume %d" % int(diag.get("resume_status", 1)),
		"cfg %d" % int(diag.get("configure_status", 1)),
		"update %d (%d ok / %d err)" % [int(diag.get("update_status", 0)), int(diag.get("frames", 0)), int(diag.get("update_errors", 0))],
		"cam %s/%s" % [_STATE_NAMES.get(state, str(state)), _REASON_NAMES.get(int(diag.get("failure_reason", 0)), "?")],
		"tracked %d" % int(diag.get("tracking_frames", 0)),
		"new frames %d" % int(diag.get("timestamp_changes", 0)),
		"pts %d (pc %d)" % [int(diag.get("points", 0)), int(diag.get("point_cloud_status", 0))],
		"planes %d/%d" % [int(diag.get("upward_planes", 0)), int(diag.get("planes_any_state", 0))],
		"tex %d" % int(diag.get("texture_id", 0)),
	]
	var pos: Variant = diag.get("camera_position", null)
	if pos is Vector3:
		var p: Vector3 = pos as Vector3
		parts.append("pos %.2f,%.2f,%.2f" % [p.x, p.y, p.z])
	var display: Variant = diag.get("display", null)
	if display is Vector2i:
		parts.append("disp %dx%d" % [(display as Vector2i).x, (display as Vector2i).y])
	if diag.has("arcore_version"):
		parts.append("ARCore %s" % str(diag["arcore_version"]))
	parts.append("debuggable %s" % yes_no.call("debuggable"))
	return "AR debug · " + " · ".join(parts)
