class_name DirectionalGravityField3D
extends Area3D

# The local direction of gravity relative to the Area3D's rotation
@export var local_gravity_direction: Vector3 = Vector3.DOWN

func _ready() -> void:
	# Ensure the area overrides global/default gravity
	gravity = 16
	gravity_space_override = SPACE_OVERRIDE_REPLACE
	update_gravity_direction()

func _physics_process(delta: float) -> void:
	# Update every frame if the Area3D rotates dynamically during gameplay
	update_gravity_direction()

func update_gravity_direction() -> void:
	# Multiply the node's global basis by the local vector to get the rotated global direction
	gravity_direction = global_transform.basis * local_gravity_direction.normalized()
