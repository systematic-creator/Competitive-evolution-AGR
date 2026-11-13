class_name ThirdPersonRig
extends Node3D
## Spring-arm follow camera used when a unit is possessed.

var spring: SpringArm3D
var camera: Camera3D
var target: Node3D


func _ready() -> void:
	spring = SpringArm3D.new()
	spring.spring_length = 0.18
	spring.margin = 0.02
	add_child(spring)
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.near = 0.03
	spring.add_child(camera)
	set_physics_process(true)


func attach(unit: Node3D) -> void:
	target = unit
	visible = true
	camera.current = true


func detach() -> void:
	target = null
	camera.current = false
	visible = false


func _physics_process(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	global_position = target.global_position + Vector3(0.0, 0.05, 0.0)
	rotation.y = target.rotation.y
