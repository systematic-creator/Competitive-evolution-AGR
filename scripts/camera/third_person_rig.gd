class_name ThirdPersonRig
extends Node3D
## Spring-arm follow camera used when a unit is possessed (Tier 4).
## By default the rig copies the target's yaw (free possession). Skirmish
## possession sets `follow_target_yaw = false` and drives `yaw` itself so
## WASD / joystick input stays camera-relative.

const FOLLOW_SHARPNESS: float = 12.0

var spring: SpringArm3D
var camera: Camera3D
var target: Node3D
var follow_target_yaw: bool = true
var yaw: float = 0.0
## Downward tilt of the boom (radians, negative looks down on the unit).
var pitch: float = -0.35


func _ready() -> void:
	spring = SpringArm3D.new()
	spring.spring_length = 0.18
	spring.margin = 0.02
	spring.rotation.x = pitch
	add_child(spring)
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.near = 0.01
	spring.add_child(camera)
	set_physics_process(true)


func attach(unit: Node3D) -> void:
	if target is CollisionObject3D and is_instance_valid(target):
		spring.remove_excluded_object((target as CollisionObject3D).get_rid())
	target = unit
	if unit is CollisionObject3D:
		# Don't let the boom collide with the possessed body itself.
		spring.add_excluded_object((unit as CollisionObject3D).get_rid())
	if unit != null:
		global_position = unit.global_position + Vector3(0.0, 0.05, 0.0)
		if follow_target_yaw:
			yaw = unit.rotation.y
		rotation.y = yaw
	visible = true
	camera.current = true


func detach() -> void:
	if target is CollisionObject3D and is_instance_valid(target):
		spring.remove_excluded_object((target as CollisionObject3D).get_rid())
	target = null
	camera.current = false
	visible = false


func _physics_process(delta: float) -> void:
	spring.rotation.x = pitch
	if target == null or not is_instance_valid(target):
		rotation.y = yaw
		return
	var weight: float = clampf(delta * FOLLOW_SHARPNESS, 0.0, 1.0)
	global_position = global_position.lerp(target.global_position + Vector3(0.0, 0.05, 0.0), weight)
	if follow_target_yaw:
		yaw = target.rotation.y
	rotation.y = lerp_angle(rotation.y, yaw, weight)
