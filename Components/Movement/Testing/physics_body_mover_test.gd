extends SceneTree

const PHYSICS_MOVER_SCRIPT := preload("res://Components/Movement/physics_body_mover.gd")


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	await _test_ground_mode_and_jump()
	await _test_zero_gravity_flight()
	print("PhysicsBodyMover tests passed.")
	quit()


func _test_ground_mode_and_jump() -> void:
	var floor := _create_floor()
	root.add_child(floor)
	var body := _create_rigid_body()
	body.position = Vector3(0.0, 3.0, 0.0)
	var mover := PHYSICS_MOVER_SCRIPT.new()
	mover.base_movement_speed = 8.0
	body.add_child(mover)
	root.add_child(body)

	for frame in 120:
		await physics_frame

	var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	assert(state != null)
	assert(mover._is_grounded(state, Vector3.UP))
	assert(body.global_position.y > 0.9 and body.global_position.y < 1.1)

	mover._handle_jump_press()
	await physics_frame
	await physics_frame
	assert(body.linear_velocity.y > 0.0)

	mover.set_boosting(true)
	assert(is_equal_approx(mover.movement_speed.value, 12.0))
	mover.set_boosting(false)
	mover.set_slowing(true)
	assert(is_equal_approx(mover.movement_speed.value, 4.0))

	body.free()
	floor.free()


func _test_zero_gravity_flight() -> void:
	var zero_gravity_area := _create_zero_gravity_area()
	root.add_child(zero_gravity_area)
	var body := _create_rigid_body()
	var mover := PHYSICS_MOVER_SCRIPT.new()
	body.add_child(mover)
	root.add_child(body)

	for frame in 3:
		await physics_frame
	assert(not mover.has_gravity)
	mover.set_flying(true)

	Input.action_press("jump")
	for frame in 20:
		await physics_frame
	Input.action_release("jump")
	assert(body.linear_velocity.y > 0.0)

	Input.action_press("roll_left")
	for frame in 10:
		await physics_frame
	Input.action_release("roll_left")
	assert(absf(body.angular_velocity.z) > 0.01)

	body.free()
	zero_gravity_area.free()


func _create_rigid_body() -> RigidBody3D:
	var body := RigidBody3D.new()
	body.can_sleep = false
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	body.add_child(collision)
	return body


func _create_floor() -> StaticBody3D:
	var floor := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(20.0, 1.0, 20.0)
	collision.shape = shape
	floor.add_child(collision)
	return floor


func _create_zero_gravity_area() -> Area3D:
	var area := Area3D.new()
	area.gravity_space_override = Area3D.SPACE_OVERRIDE_REPLACE
	area.gravity = 0.0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * 20.0
	collision.shape = shape
	area.add_child(collision)
	return area
