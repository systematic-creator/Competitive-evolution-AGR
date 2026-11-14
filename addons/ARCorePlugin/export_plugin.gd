@tool
extends EditorPlugin
## Adds the ARCore AAR and its Maven dependencies to Gradle-based Android
## exports. Adapted from GodotVR/godot_arcore's export_scripts_template:
## it registers no autoload (ARSessionController talks to the plugin
## dynamically through ARCoreBridge), and it stays inactive until the plugin
## binaries are built, so the plain Android preset keeps working until then.

var export_plugin: AndroidExportPlugin


func _enter_tree() -> void:
	export_plugin = AndroidExportPlugin.new()
	add_export_plugin(export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(export_plugin)
	export_plugin = null


class AndroidExportPlugin extends EditorExportPlugin:
	const PLUGIN_NAME: String = "ARCorePlugin"
	const DEPENDENCIES: PackedStringArray = [
		"com.google.ar:core:1.44.0",
		"androidx.appcompat:appcompat:1.4.0",
	]

	const INSTALLED_MARKER: String = "res://addons/ARCorePlugin/plugin.gdextension"

	# Godot refuses non-Gradle Android exports while any export plugin claims
	# the platform. Claim it only once the plugin binaries are installed by
	# tools/arcore_plugin/build_arcore_plugin.sh; from then on, Android builds
	# must use the Gradle "Android AR" preset.
	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid and FileAccess.file_exists(INSTALLED_MARKER)

	func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		var flavor: String = "debug" if debug else "release"
		return PackedStringArray(["%s/bin/%s/%s-%s.aar" % [PLUGIN_NAME, flavor, PLUGIN_NAME, flavor]])

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return DEPENDENCIES

	func _get_name() -> String:
		return PLUGIN_NAME
