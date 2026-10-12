extends Node3D
## A place to try the CameraRig3D by hand. Run CameraRigDemo.tscn (F6 in the editor).
##
## A SpaceShip3D (a rigid body) turns toward wherever the rig aims. Fly down into the green slab's gravity field
## to see the rig level out and limit its pitch, and back out to float again. Hold C (or
## Y on a gamepad) to look around without turning the ship.

const RIG_SCENE := preload("res://Components/Camera/CameraRig.tscn")

var _ship: SpaceShip3D
var _rig: CameraRig3D
var _label := Label.new()


func _ready() -> void:
	_build_environment()
	_build_planet()
	_build_ship()
	_build_label()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_rig.camera.current = true


func _process(_delta: float) -> void:
	_label.text = "%s%s\nWASD thrust    Mouse / right stick look    Q E roll (floating)\nHold Alt / click right stick: look around without turning the ship" % [
		"Floating" if _rig.is_weightless() else "Gravity",
		"    (freecam)" if _rig.is_freecam_active() else "",
	]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_tree().quit()


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.01, 0.01, 0.03)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.4, 0.45, 0.6)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	add_child(sun)

	# Drifting rocks, so there is something to see move.
	var random := RandomNumberGenerator.new()
	random.seed = 7
	for index in 90:
		var rock := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(random.randf_range(2.0, 14.0), random.randf_range(2.0, 14.0), random.randf_range(2.0, 14.0))
		rock.mesh = mesh
		rock.material_override = _color(Color.from_hsv(random.randf(), 0.35, 0.8))
		rock.position = Vector3(random.randf_range(-300.0, 300.0), random.randf_range(60.0, 400.0), random.randf_range(-300.0, 300.0))
		rock.rotation = Vector3(random.randf() * TAU, random.randf() * TAU, random.randf() * TAU)
		add_child(rock)


func _build_planet() -> void:
	var slab := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(600.0, 2.0, 600.0)
	slab.mesh = mesh
	slab.material_override = _color(Color(0.25, 0.5, 0.25))
	slab.position = Vector3(0.0, -120.0, 0.0)
	add_child(slab)

	var field := DirectionalGravityField3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(600.0, 200.0, 600.0)
	shape.shape = box
	field.add_child(shape)
	field.position = Vector3(0.0, -20.0, 0.0)
	add_child(field)


func _build_ship() -> void:
	_ship = SpaceShip3D.new()
	_ship.mass = 20000.0
	_ship.engine_state = true
	_ship.power_state = true
	_ship.fly_without_pilot = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 1.0, 6.0)
	shape.shape = box
	_ship.add_child(shape)

	var hull := MeshInstance3D.new()
	var hull_mesh := BoxMesh.new()
	hull_mesh.size = box.size
	hull.mesh = hull_mesh
	hull.material_override = _color(Color(0.8, 0.8, 0.85))
	_ship.add_child(hull)
	var nose := MeshInstance3D.new()
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(1.0, 1.0, 1.5)
	nose.mesh = nose_mesh
	nose.material_override = _color(Color(0.9, 0.25, 0.2))
	nose.position = Vector3(0.0, 0.6, -2.5)
	_ship.add_child(nose)

	_ship.position = Vector3(0.0, 100.0, 0.0)
	_rig = RIG_SCENE.instantiate() as CameraRig3D
	_rig.position = Vector3(0.0, 1.0, 0.0)
	_ship.add_child(_rig)
	add_child(_ship)


func _build_label() -> void:
	var layer := CanvasLayer.new()
	_label.position = Vector2(16.0, 12.0)
	layer.add_child(_label)
	add_child(layer)


func _color(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
