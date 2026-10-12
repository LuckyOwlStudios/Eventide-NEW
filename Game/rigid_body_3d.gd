class_name MovingCube
extends RigidBody3D

@export var move_speed: float = 5.0

func _physics_process(_delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	var direction := global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)

	linear_velocity.x = direction.x * move_speed
	linear_velocity.z = direction.z * move_speed
