class_name ARCoreBridge
extends RefCounted
## Thin, fully dynamic wrapper around the GodotVR ARCore plugin, patched with
## plane hit tests and anchors (see tools/arcore_plugin/). Nothing here names a
## plugin class statically, so the project parses and runs on desktop and
## headless where the Android-only GDExtension is absent.

const PLUGIN_SINGLETON: String = "ARCorePlugin"
const INTERFACE_CLASS: String = "ARCoreInterface"
const INTERFACE_NAME: StringName = &"ARCore"
## Methods added by tools/arcore_plugin/agr-arcore.patch. An unpatched
## upstream build lacks them, and AR then falls back to the desktop camera.
const REQUIRED_METHODS: PackedStringArray = [
	"hit_test_plane",
	"create_anchor_at_screen",
	"create_anchor",
	"get_anchor_pose",
	"get_anchor_tracking_state",
	"remove_anchor",
]

var interface: XRInterface
var failure_reason: String = ""
var _plugin: Object
var _added_interface: bool = false


## True when the Android plugin singleton and the GDExtension class exist.
static func plugin_present() -> bool:
	return Engine.has_singleton(PLUGIN_SINGLETON) and ClassDB.class_exists(INTERFACE_CLASS)


## Start an ARCore session and switch `viewport` to XR rendering.
## Returns false (with `failure_reason`) when AR cannot run on this device.
func start(viewport: Viewport) -> bool:
	if not plugin_present():
		failure_reason = "ARCore plugin is not in this build."
		return false
	_plugin = Engine.get_singleton(PLUGIN_SINGLETON)
	interface = XRServer.find_interface(INTERFACE_NAME)
	if interface == null:
		interface = ClassDB.instantiate(INTERFACE_CLASS) as XRInterface
		if interface == null:
			failure_reason = "Could not create the ARCore interface."
			return false
		XRServer.add_interface(interface)
		_added_interface = true
	for method: String in REQUIRED_METHODS:
		if not interface.has_method(method):
			failure_reason = "ARCore plugin lacks %s (unpatched build)." % method
			return false
	_plugin.call("initializeEnvironment")
	interface.call("enable_horizontal_plane_detection", true)
	if not interface.initialize():
		failure_reason = "ARCore did not start (unsupported device, ARCore not installed, or camera permission denied)."
		return false
	viewport.use_xr = true
	return true


func stop(viewport: Viewport) -> void:
	if viewport != null:
		viewport.use_xr = false
	if interface != null:
		if interface.has_method("remove_all_anchors"):
			interface.call("remove_all_anchors")
		if interface.is_initialized():
			interface.uninitialize()
		if _added_interface:
			XRServer.remove_interface(interface)
	if _plugin != null:
		_plugin.call("uninitializeEnvironment")
	interface = null
	_plugin = null


func is_running() -> bool:
	return interface != null and interface.is_initialized()


## XRInterface.TrackingStatus of the device camera.
func tracking_status() -> int:
	if interface == null:
		return XRInterface.XR_UNKNOWN_TRACKING
	return int(interface.get_tracking_status())


## Nearest tracked upward-facing plane under a normalized screen point.
## Returns {"hit": bool, "pose": Transform3D (Godot world)}.
func hit_test(normalized_screen: Vector2) -> Dictionary:
	if not is_running():
		return {"hit": false}
	return interface.call("hit_test_plane", normalized_screen.x, normalized_screen.y) as Dictionary


## Anchor attached to the plane under a normalized screen point.
## Returns {"id": int (-1 on failure), "pose": Transform3D}.
func create_anchor_at_screen(normalized_screen: Vector2) -> Dictionary:
	if not is_running():
		return {"id": -1}
	return interface.call("create_anchor_at_screen", normalized_screen.x, normalized_screen.y) as Dictionary


func create_anchor(pose: Transform3D) -> int:
	if not is_running():
		return -1
	return int(interface.call("create_anchor", pose))


func get_anchor_pose(anchor_id: int) -> Transform3D:
	if interface == null:
		return Transform3D.IDENTITY
	return interface.call("get_anchor_pose", anchor_id) as Transform3D


## 0 tracking, 1 paused, 2 stopped, -1 unknown.
func get_anchor_tracking_state(anchor_id: int) -> int:
	if interface == null:
		return -1
	return int(interface.call("get_anchor_tracking_state", anchor_id))


func remove_anchor(anchor_id: int) -> void:
	if interface != null:
		interface.call("remove_anchor", anchor_id)
