extends SceneTree

const ORIENTOR_SCRIPT := preload("res://Components/Orientor/orientor.gd")


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var target := StaticBody3D.new()
	root.add_child(target)
	var orientor := ORIENTOR_SCRIPT.new()
	target.add_child(orientor)
	await process_frame

	orientor.orientation_speed = 0.0
	target.global_basis = Basis(Vector3.FORWARD, PI)
	orientor.orient_to_gravity(Vector3.DOWN)
	_assert_direction(target.global_basis.y, Vector3.UP)

	orientor.orient_to_gravity(Vector3.RIGHT)
	_assert_direction(target.global_basis.y, Vector3.LEFT)

	target.scale = Vector3(2.0, 3.0, 4.0)
	orientor.orient_to_gravity(Vector3.BACK)
	_assert_direction(target.global_basis.y.normalized(), Vector3.FORWARD)
	assert(target.global_basis.get_scale().is_equal_approx(Vector3(2.0, 3.0, 4.0)))

	var basis_before_zero_gravity := target.global_basis
	orientor.orient_to_gravity(Vector3.ZERO)
	assert(target.global_basis.is_equal_approx(basis_before_zero_gravity))

	target.free()
	await _test_rotated_area_gravity()
	await _test_character_body_area_gravity()
	await _test_orientation_demo()
	print("Orientor tests passed.")
	quit()


func _assert_direction(actual: Vector3, expected: Vector3) -> void:
	assert(actual.normalized().dot(expected.normalized()) > 0.9999)


func _test_rotated_area_gravity() -> void:
	var gravity_area := Area3D.new()
	gravity_area.gravity_space_override = Area3D.SPACE_OVERRIDE_REPLACE
	gravity_area.gravity = 12.0
	gravity_area.rotation.z = PI * 0.5
	gravity_area.gravity_direction = gravity_area.basis * Vector3.DOWN
	var area_collision := CollisionShape3D.new()
	var area_shape := BoxShape3D.new()
	area_shape.size = Vector3.ONE * 20.0
	area_collision.shape = area_shape
	gravity_area.add_child(area_collision)
	root.add_child(gravity_area)

	var rigid_body := RigidBody3D.new()
	rigid_body.can_sleep = false
	var body_collision := CollisionShape3D.new()
	body_collision.shape = BoxShape3D.new()
	rigid_body.add_child(body_collision)
	var physics_orientor := ORIENTOR_SCRIPT.new()
	physics_orientor.orientation_speed = 0.0
	rigid_body.add_child(physics_orientor)
	root.add_child(rigid_body)

	for frame in 4:
		await physics_frame

	var expected_gravity := gravity_area.gravity_direction.normalized()
	_assert_direction(physics_orientor.gravity_vector, expected_gravity)
	_assert_direction(rigid_body.global_basis.y, -expected_gravity)

	rigid_body.free()
	gravity_area.free()


func _test_character_body_area_gravity() -> void:
	var gravity_area := Area3D.new()
	gravity_area.gravity_space_override = Area3D.SPACE_OVERRIDE_REPLACE
	gravity_area.gravity = 16.0
	gravity_area.gravity_direction = Vector3.RIGHT
	var area_collision := CollisionShape3D.new()
	var area_shape := BoxShape3D.new()
	area_shape.size = Vector3.ONE * 20.0
	area_collision.shape = area_shape
	gravity_area.add_child(area_collision)
	root.add_child(gravity_area)

	var character := CharacterBody3D.new()
	var body_collision := CollisionShape3D.new()
	body_collision.shape = BoxShape3D.new()
	character.add_child(body_collision)
	var character_orientor := ORIENTOR_SCRIPT.new()
	character_orientor.orientation_speed = 0.0
	character.add_child(character_orientor)
	root.add_child(character)

	for frame in 4:
		await physics_frame

	_assert_direction(character_orientor.gravity_vector, Vector3.RIGHT)
	_assert_direction(character.global_basis.y, Vector3.LEFT)
	character.free()
	gravity_area.free()


func _test_orientation_demo() -> void:
	var demo_scene: PackedScene = load("res://Testing/Orientation/OrientationDemo.tscn")
	assert(demo_scene != null)
	var demo := demo_scene.instantiate()
	root.add_child(demo)
	var cube := demo.get_node("Cube") as RigidBody3D

	for frame in 90:
		await physics_frame

	assert(cube.global_position.x > 1.4 and cube.global_position.x < 1.6)
	assert(absf(cube.global_position.y) < 0.2)
	_assert_direction(cube.global_basis.y, Vector3.LEFT)
	demo.free()
