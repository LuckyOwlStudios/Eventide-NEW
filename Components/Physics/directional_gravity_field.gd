class_name DirectionalGravityField3D
extends Area3D

# The local direction of gravity relative to the Area3D's rotation
@export var local_gravity_direction: Vector3 = Vector3.DOWN

func _enter_tree() -> void:
	# A field pulls the bodies in its mask. This default is for gravity out in the world;
	# a field inside a vehicle should be given PhysicsLayers.INTERIOR_GRAVITY_MASK instead,
	# so the vehicle itself is not pulled around by its own interior gravity. Anything a
	# scene set to something other than Godot's stock value of 1 is left alone.
	if collision_layer == 1:
		collision_layer = PhysicsLayers.GRAVITY_FIELDS
	if collision_mask == 1:
		collision_mask = PhysicsLayers.WORLD_GRAVITY_MASK

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
