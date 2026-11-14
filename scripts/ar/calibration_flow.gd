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


func restart() -> void:
	step = Step.SCANNING
	scan_seconds = 0.0


## Advance one frame. `surface_found` is the reticle hit test result.
func update(delta: float, info: Dictionary, surface_found: bool) -> void:
	last_info = info
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
