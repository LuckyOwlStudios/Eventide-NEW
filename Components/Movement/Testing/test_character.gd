class_name TestCharacter
extends RefCounted
## Makes a [WalkingCharacter3D] in code for the tests that need a body to move, with the hitbox and the
## numbers the Player has: a capsule 0.8 wide and 1.8 tall, walking at 5 m/s, a jump a meter high, and every
## capability. Add whatever else the test is about (a controller, a jetpack) and put it in the world.

## The body, with a collision shape (the character gives it its shape) and an Orientator.
static func make(
	body_name := "Character",
	layer: int = PhysicsLayers.PLAYERS,
	mask: int = PhysicsLayers.PLAYER_MASK,
) -> WalkingCharacter3D:
	var body := WalkingCharacter3D.new()
	body.name = body_name
	body.collision_layer = layer
	body.collision_mask = mask
	body._movement_speed = 5.0
	body._jump_height = 1.0
	body._can_crouch = true
	body._can_run = true
	body._can_jump = true
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	body.add_child(shape)
	var orientor := Orientator.new()
	orientor.name = "Orientator"
	body.add_child(orientor)
	return body
