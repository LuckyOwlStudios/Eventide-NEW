extends Node
## Headless checks for BaseCharacter3D: the shape follows the inspector values, and characters made from one
## scene do not share a shape.
##
## godot --headless --fixed-fps 60 --path . res://Scenes/Characters/Testing/BaseCharacterTest.tscn

const SCENE := preload("res://Scenes/Characters/BaseCharacter.tscn")

var _failures := 0


func _ready() -> void:
	_run()


func _run() -> void:
	var only := OS.get_environment("ONLY")
	for test_name in ["shape", "inspector_order", "own_shape", "subclass_hitbox"]:
		if only.is_empty() or only == test_name:
			print("-- ", test_name)
			await call("_test_" + test_name)
	if _failures == 0:
		print("Base character tests passed.")
	else:
		print("Base character tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _make() -> BaseCharacter3D:
	return SCENE.instantiate() as BaseCharacter3D


## A character whose hitbox is bigger than it says, to see the hooks used.
class Giant extends BaseCharacter3D:
	func _get_hitbox_dimensions() -> Vector2:
		return dimensions * 2.0


func _test_shape() -> void:
	var character := _make()
	add_child(character)
	var shape := character.collision_shape.shape as CapsuleShape3D
	_check(shape != null and is_equal_approx(shape.radius, 0.4) and is_equal_approx(shape.height, 1.8), "the default is a capsule 0.8 wide and 1.8 tall")
	_check(character.collision_shape.position.is_equal_approx(Vector3(0, 0.9, 0)), "standing on the origin")

	character.dimensions = Vector2(1.2, 3.0)
	shape = character.collision_shape.shape as CapsuleShape3D
	_check(is_equal_approx(shape.radius, 0.6) and is_equal_approx(shape.height, 3.0), "changing the dimensions changes the shape")
	_check(character.collision_shape.position.is_equal_approx(Vector3(0, 1.5, 0)), "and keeps the feet down")
	character.dimensions = Vector2(5.0, 1.0)
	shape = character.collision_shape.shape as CapsuleShape3D
	_check(is_equal_approx(shape.radius, 0.5) and is_equal_approx(shape.height, 1.0), "a capsule is never wider than it is tall")

	character.shape_type = BaseCharacter3D.ShapeType.BOX
	character.dimensions = Vector2(1.0, 2.0)
	var box := character.collision_shape.shape as BoxShape3D
	_check(box != null and box.size.is_equal_approx(Vector3(1, 2, 1)), "a box takes the width and height")
	character.shape_type = BaseCharacter3D.ShapeType.SPHERE
	var sphere := character.collision_shape.shape as SphereShape3D
	_check(sphere != null and is_equal_approx(sphere.radius, 1.0), "a sphere is as tall across as the height")
	character.shape_type = BaseCharacter3D.ShapeType.CYLINDER
	var cylinder := character.collision_shape.shape as CylinderShape3D
	_check(cylinder != null and is_equal_approx(cylinder.radius, 0.5) and is_equal_approx(cylinder.height, 2.0), "and a cylinder takes both")
	character.shape_type = BaseCharacter3D.ShapeType.BOX
	_check(character.collision_shape.shape == box, "going back to a kind it had uses the shape it had")
	_check(character.collision_layer == 0 and character.get_collision_mask_value(1) and character.get_collision_mask_value(4) and character.get_collision_mask_value(5), "it is in no layer of its own, and sees the world, vehicles and interiors")
	character.free()


## What the inspector does: values are set on the node as the scene loads, before it is ready.
func _test_inspector_order() -> void:
	var character := _make()
	character.dimensions = Vector2(1.0, 2.5)
	character.shape_type = BaseCharacter3D.ShapeType.CYLINDER
	add_child(character)
	var cylinder := character.collision_shape.shape as CylinderShape3D
	_check(cylinder != null and is_equal_approx(cylinder.height, 2.5), "values set before the scene is ready are used when it is")
	character.free()
	var bare := BaseCharacter3D.new()
	_check(not bare._get_configuration_warnings().is_empty(), "a character with no shape says so")
	bare.free()


func _test_own_shape() -> void:
	var first := _make()
	var second := _make()
	add_child(first)
	add_child(second)
	first.dimensions = Vector2(2.0, 4.0)
	var other_shape := second.collision_shape.shape as CapsuleShape3D
	_check(is_equal_approx(other_shape.height, 1.8), "resizing one character does not resize another made from the same scene")
	var third := _make()
	add_child(third)
	_check(is_equal_approx((third.collision_shape.shape as CapsuleShape3D).height, 1.8), "or the next one")
	first.free()
	second.free()
	third.free()


func _test_subclass_hitbox() -> void:
	var giant := Giant.new()
	var body := CollisionShape3D.new()
	body.name = "CollisionShape3D"
	giant.add_child(body)
	add_child(giant)
	var shape := body.shape as CapsuleShape3D
	_check(shape != null and is_equal_approx(shape.height, 3.6) and is_equal_approx(shape.radius, 0.8), "a subclass answers for the size of its hitbox")
	_check(body.position.is_equal_approx(Vector3(0, 1.8, 0)), "and stands on the origin")
	giant.free()


func _check(value: bool, message: String) -> void:
	if value:
		return
	_failures += 1
	push_error("BASE CHARACTER TEST FAILED: " + message)
	print("FAIL: ", message)
