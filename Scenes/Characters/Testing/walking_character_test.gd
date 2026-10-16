extends Node
## Headless checks for WalkingCharacter3D (stance, and the hitbox that goes with it), for the Player's head and
## perspectives, and for footsteps that come from movement alone.
##
## godot --headless --fixed-fps 60 --path . res://Scenes/Characters/Testing/WalkingCharacterTest.tscn

const WALKING := preload("res://Scenes/Characters/Walking/WalkingCharacter3D.tscn")
const PLAYER_SCENE := preload("res://Scenes/Player/Player.tscn")

var _failures := 0
var _world: Node3D
## A controller that does what the test says.
class Scripted extends CharacterController:
	var move := Vector2.ZERO
	var sprint := false
	var stroll := false
	var crouch := false
	var jump_once := false

	func poll_intent(_delta: float) -> MoveIntent:
		var intent := MoveIntent.new()
		intent.move = move
		intent.sprint = sprint
		intent.stroll = stroll
		intent.crouch = crouch
		intent.jump_pressed = jump_once
		jump_once = false
		return intent


class Rig:
	var body: WalkingCharacter3D
	var controller: Scripted




func _ready() -> void:
	_run()


func _run() -> void:
	var only := OS.get_environment("ONLY")
	for test_name in [
		"stance_hitbox", "ceiling", "player_crouch", "player_head", "player_perspective",
		"footsteps_from_movement", "footsteps_without_head_motion",
		"attributes", "ground", "capabilities", "visual_offset", "player_is_a_walking_character",
	]:
		if only.is_empty() or only == test_name:
			print("-- ", test_name)
			await call("_test_" + test_name)
	if _failures == 0:
		print("Walking character tests passed.")
	else:
		print("Walking character tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# --- Tests -------------------------------------------------------------------

func _test_stance_hitbox() -> void:
	var character := WALKING.instantiate() as WalkingCharacter3D
	add_child(character)
	var stances: Array[int] = []
	character.stance_changed.connect(func(value: int) -> void: stances.append(value))
	var standing := character.collision_shape.shape as CapsuleShape3D
	_check(character.stance == WalkingCharacter3D.STANCE.STANDING and standing != null and is_equal_approx(standing.height, 1.8), "a walking character starts standing, with the standing hitbox")

	_check(character.set_stance(WalkingCharacter3D.STANCE.CROUCHING), "it crouches")
	var crouched := character.collision_shape.shape as SphereShape3D
	_check(crouched != null and is_equal_approx(crouched.radius, 0.4), "and the hitbox becomes the crouched one: a ball 0.8 across")
	_check(character.collision_shape.position.is_equal_approx(Vector3(0, 0.4, 0)), "with the feet where they were")
	_check(stances == [WalkingCharacter3D.STANCE.CROUCHING] and character.is_crouching(), "and says so, once")
	character.set_stance(WalkingCharacter3D.STANCE.CROUCHING)
	_check(stances.size() == 1, "crouching again changes nothing")

	_check(character.set_stance(WalkingCharacter3D.STANCE.STANDING), "it stands up")
	_check(character.collision_shape.shape == standing and is_equal_approx(standing.height, 1.8), "back to the same standing hitbox")
	_check(character.collision_shape.position.is_equal_approx(Vector3(0, 0.9, 0)) and stances.size() == 2, "feet down, and announced")

	character.crouch_dimensions = Vector2(0.6, 1.2)
	character.crouch_shape_type = BaseCharacter3D.ShapeType.CAPSULE
	character.stance = WalkingCharacter3D.STANCE.CROUCHING
	var capsule := character.collision_shape.shape as CapsuleShape3D
	_check(capsule != null and is_equal_approx(capsule.height, 1.2) and is_equal_approx(capsule.radius, 0.3) and capsule != standing, "the crouched hitbox can be any size and shape (and is not the standing one)")
	character.dimensions = Vector2(1.0, 2.0)
	_check(is_equal_approx(capsule.height, 1.2), "changing the standing size leaves the crouched hitbox alone")
	character.stance = WalkingCharacter3D.STANCE.STANDING
	_check(is_equal_approx(standing.height, 2.0) and is_equal_approx(standing.radius, 0.5), "and the standing one is as it was set")
	character.free()

	# What the inspector does: the stance is set as the scene loads, before it is ready.
	var early := WALKING.instantiate() as WalkingCharacter3D
	early.stance = WalkingCharacter3D.STANCE.CROUCHING
	add_child(early)
	_check(early.collision_shape.shape is SphereShape3D, "a character saved crouched has the crouched hitbox when it loads")
	early.free()


func _test_ceiling() -> void:
	_begin_world(false)
	var character := WALKING.instantiate() as WalkingCharacter3D
	_world.add_child(character)
	character.collision_mask = 1
	var ceiling := StaticBody3D.new()
	var ceiling_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 0.2, 4.0)
	ceiling_shape.shape = box
	ceiling.add_child(ceiling_shape)
	ceiling.position = Vector3(0.0, 1.3, 0.0)
	_world.add_child(ceiling)
	await _frames(3)
	_check(not character.can_stand_up(), "under a low ceiling there is no room to stand")
	character.stance = WalkingCharacter3D.STANCE.CROUCHING
	_check(not character.can_stand_up() and not character.set_stance(WalkingCharacter3D.STANCE.STANDING) and character.is_crouching(), "a crouched character stays crouched under it")
	_check(character.collision_shape.shape is SphereShape3D, "with the crouched hitbox")
	ceiling.position = Vector3(0.0, 3.0, 0.0)
	await _frames(3)
	_check(character.can_stand_up() and character.set_stance(WalkingCharacter3D.STANCE.STANDING) and not character.is_crouching(), "with the ceiling gone it stands up")
	_end_world()


func _test_player_crouch() -> void:
	_begin_world(true)
	var player := _new_player()
	_world.add_child(player)
	var controller := player.get_node("PlayerCharacterController") as CharacterController
	await _frames(40)
	_check(player is WalkingCharacter3D and player.get_node_or_null("Head") != null, "the player is a walking character with a head")
	_check(not player.is_crouching() and player.collision_shape.shape is CapsuleShape3D, "it stands")

	Input.action_press("crouch")
	await _frames(20)
	_check(controller.is_crouching() and player.is_crouching(), "the controller crouching puts the player in the crouching stance")
	_check(player.collision_shape.shape is SphereShape3D, "and the hitbox follows")
	await _frames(40)
	Input.action_release("crouch")

	# Under a ceiling, letting go of crouch does not stand them up.
	Input.action_press("crouch")
	await _frames(30)
	var ceiling := StaticBody3D.new()
	var ceiling_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 0.2, 6.0)
	ceiling_shape.shape = box
	ceiling.add_child(ceiling_shape)
	ceiling.position = Vector3(player.global_position.x, 1.3, player.global_position.z)
	_world.add_child(ceiling)
	await _frames(5)
	Input.action_release("crouch")
	await _frames(30)
	_check(player.is_crouching() and not controller.can_stand(), "under a low ceiling they stay crouched")
	ceiling.free()
	await _frames(30)
	_check(not player.is_crouching() and player.collision_shape.shape is CapsuleShape3D, "and stand when it is gone")
	_end_world()


func _test_player_head() -> void:
	_begin_world(true)
	var player := _new_player()
	_world.add_child(player)
	await _frames(60)
	var head := player.head
	_check(is_equal_approx(head.position.y, 1.8 * 0.9) and is_equal_approx(player.get_head_rest_position().y, 1.62), "the head is 90%% of the way up the standing hitbox: %.3f" % head.position.y)
	player.head_height = 0.5
	_check(true, "(head height can be changed)")
	await _frames(60)
	_check(absf(head.position.y - 0.9) < 0.01, "and follows it: %.3f" % head.position.y)
	player.head_height = 0.9
	await _frames(60)

	Input.action_press("crouch")
	await _frames(3)
	_check(head.position.y < 1.62 and head.position.y > 0.72, "crouching lowers the head smoothly, not at once: %.3f" % head.position.y)
	await _frames(60)
	_check(absf(head.position.y - 0.72) < 0.01, "to the same share of the crouched hitbox: %.3f" % head.position.y)
	Input.action_release("crouch")
	await _frames(60)
	_check(absf(head.position.y - 1.62) < 0.01, "and back up again: %.3f" % head.position.y)
	_end_world()


func _test_player_perspective() -> void:
	var player := _new_player()
	var model := player.get_node("Model") as Node3D
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	model.add_child(mesh)
	player.perspective = Player.Perspective.THIRD_PERSON
	add_child(player)
	await _frames(2)
	var arms := player.first_person_root
	var events := []
	player.perspective_changed.connect(func(first: bool) -> void: events.append(first))
	_check(arms != null, "the player has a first person root")
	_check(not player.is_first_person() and mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "seen from outside the model is drawn")
	_check(not arms.visible, "and the first person root is hidden")
	_check(mesh.layers & Player.OWN_BODY_LAYER != 0, "the model is on the own body layer")

	player.perspective = Player.Perspective.FIRST_PERSON
	_check(player.is_first_person() and events == [true], "looking through their eyes, and said so")
	_check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and arms.visible, "the model is only a shadow, and the first person root is shown")
	player.perspective = Player.Perspective.THIRD_PERSON
	_check(not player.is_first_person() and mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and not arms.visible and events == [true, false], "back out again, as it was authored")
	player.perspective = Player.Perspective.AUTO
	_check(player.is_first_person(), "offline, an automatic player is the one at the keyboard")
	player.set_first_person(false)
	_check(not player.is_first_person(), "a spectator can look from outside")
	player.refresh_perspective()
	_check(player.is_first_person(), "and the setting wins when asked")
	var view := player.get_view_transform()
	_check(view.origin.is_equal_approx(player.head.global_position), "the point of view is the head")

	# Facing.
	var yaw := player.get_node("Head/YawPivot") as Node3D
	yaw.rotation.y = 1.2
	await _frames(40)
	_check(absf(angle_difference(model.rotation.y, 1.2)) < 0.01, "the model turns to face where the player looks: %.2f" % model.rotation.y)
	yaw.rotation.y = -2.5
	await _frames(1)
	_check(absf(angle_difference(model.rotation.y, 1.2)) > 0.05 and absf(angle_difference(model.rotation.y, -2.5)) > 0.05, "smoothly, not in one frame")
	await _frames(40)
	_check(absf(angle_difference(model.rotation.y, -2.5)) < 0.01, "all the way round the short way")
	player.free()


func _test_footsteps_from_movement() -> void:
	_begin_world(true)
	var player := _new_player()
	_world.add_child(player)
	var footsteps := player.get_node("FootstepPlayer") as FootstepPlayer
	var steps: Array[Dictionary] = []
	footsteps.stepped.connect(func(foot: int, strength: float) -> void: steps.append({"foot": foot, "strength": strength, "z": player.global_position.z}))
	await _frames(60)
	_check(steps.is_empty(), "no steps standing still")

	var start := player.global_position
	Input.action_press("move_forward")
	await _frames(240)
	Input.action_release("move_forward")
	var distance := start.distance_to(player.global_position)
	var expected := distance / footsteps.walk_step_distance + 1.0
	_check(absf(float(steps.size()) - expected) <= 2.0, "walking, a step comes every %.1f m: %d steps over %.1f m (about %.1f)" % [footsteps.walk_step_distance, steps.size(), distance, expected])
	_check(steps[0]["strength"] > 0.3, "the first came at once, as the character set off")
	var alternates := true
	for index in range(1, steps.size()):
		if steps[index]["foot"] == steps[index - 1]["foot"]:
			alternates = false
	_check(alternates, "and the feet take turns")
	await _frames(60)
	var stopped := steps.size()
	await _frames(60)
	_check(steps.size() == stopped, "stopping stops the steps")

	# Crouched, the steps are shorter and quieter.
	steps.clear()
	start = player.global_position
	Input.action_press("crouch")
	await _frames(30)
	Input.action_press("move_forward")
	await _frames(240)
	Input.action_release("move_forward")
	Input.action_release("crouch")
	var crouch_distance := start.distance_to(player.global_position)
	var crouch_steps := steps.size()
	_check(crouch_steps > 0 and crouch_distance / float(crouch_steps) < footsteps.walk_step_distance, "crouched, the steps are closer together: %d steps over %.1f m" % [crouch_steps, crouch_distance])
	var loudest := 0.0
	for step in steps:
		loudest = maxf(loudest, step["strength"])
	_check(loudest < 0.3, "and much quieter (%.2f)" % loudest)
	await _frames(60)

	# Landing is a step, and there are none in the air.
	steps.clear()
	var jump := InputEventAction.new()
	jump.action = &"jump"
	jump.pressed = true
	Input.parse_input_event(jump)
	Input.action_press("jump")
	await _frames(3)
	Input.action_release("jump")
	await _frames(90)
	_check(steps.size() == 1 and steps[0]["strength"] >= 1.0, "a jump on the spot makes one step, when it lands (%d)" % steps.size())
	_end_world()


## The same, with no head bob at all: footsteps do not need one.
func _test_footsteps_without_head_motion() -> void:
	_begin_world(true)
	var player := _new_player()
	_world.add_child(player)
	player.get_node("HeadMotion").free()
	var footsteps := player.get_node("FootstepPlayer") as FootstepPlayer
	var count := [0]
	footsteps.stepped.connect(func(_foot: int, _strength: float) -> void: count[0] += 1)
	var heard := [0]
	footsteps.step_played.connect(func(_character: AudioStream, _surface: AudioStream, _material: SurfaceMaterial) -> void: heard[0] += 1)
	await _frames(60)
	Input.action_press("move_forward")
	await _frames(180)
	Input.action_release("move_forward")
	_check(count[0] >= 5, "a player with no head motion still takes steps (%d)" % count[0])
	_check(heard[0] == count[0], "and each one is heard (%d)" % heard[0])
	_end_world()


## What a walking character is, apart from anything that drives it: its speed and jump are attributes that the
## inspector values and buffs both change, and they start out right.
func _test_attributes() -> void:
	var character := WalkingCharacter3D.new()
	_check(is_equal_approx(character.movement_speed.value, 3.0) and is_equal_approx(character.sprint_multiplier.value, 1.5), "a new walking character walks at 3 m/s and sprints at 1.5 times that")
	_check(is_equal_approx(character.crouch_multiplier.value, 0.5) and is_equal_approx(character.stroll_multiplier.value, 0.5) and is_equal_approx(character.jump_height.value, 1.0), "crouches and strolls at half speed and jumps a meter, before anything is set")
	character._movement_speed = 7.0
	character._sprint_multiplier = 2.0
	character._crouch_multiplier = 0.25
	character._stroll_multiplier = 0.4
	character._jump_height = 2.5
	_check(is_equal_approx(character.movement_speed.value, 7.0) and is_equal_approx(character.sprint_multiplier.value, 2.0), "what the inspector sets is what the attributes say")
	_check(is_equal_approx(character.crouch_multiplier.value, 0.25) and is_equal_approx(character.stroll_multiplier.value, 0.4) and is_equal_approx(character.jump_height.value, 2.5), "for every one of them")
	character._movement_speed = -4.0
	_check(character.movement_speed.value == 0.0, "and a negative speed is none")
	character._movement_speed = 5.0
	var haste := AttributeModifier.new()
	haste.operation = AttributeModifier.Operation.MULTIPLY_TOTAL
	haste.amount = 100.0
	character.movement_speed.add_attribute_modifier("potion.haste", haste)
	_check(is_equal_approx(character.movement_speed.value, 10.0), "a buff changes the speed without knowing anything about whatever moves the character")
	character.movement_speed.remove_attribute_modifier("potion.haste")
	_check(is_equal_approx(character.movement_speed.value, 5.0), "and takes it away again")
	character.free()

	var player := _new_player()
	_check(is_equal_approx(player.movement_speed.value, 5.0) and is_equal_approx(player.jump_height.value, 1.0), "the player is set up to walk at 5 m/s and jump a meter")
	_check(player.can_run() and player.can_crouch() and player.can_jump() and player.can_walk(), "and can do everything a player does")
	player.free()


## The Ground group is the character's. The controller reads it every tick.
func _test_ground() -> void:
	# Speed comes from the attributes: a faster character, and a buffed one, go faster.
	_begin_world(true)
	var rig := _make_rig(Vector3(0.0, 0.05, 0.0))
	await _frames(30)
	rig.controller.move = Vector2(0.0, -1.0)
	await _frames(40)
	_check(absf(_speed(rig.body) - 5.0) < 0.1, "a character walks at its movement speed (%.2f)" % _speed(rig.body))
	rig.body._movement_speed = 8.0
	await _frames(30)
	_check(absf(_speed(rig.body) - 8.0) < 0.15, "and at a new one when it is changed (%.2f)" % _speed(rig.body))
	var haste := AttributeModifier.new()
	haste.operation = AttributeModifier.Operation.MULTIPLY_TOTAL
	haste.amount = 50.0
	rig.body.movement_speed.add_attribute_modifier("haste", haste)
	await _frames(30)
	_check(absf(_speed(rig.body) - 12.0) < 0.2, "and faster still with a buff (%.2f)" % _speed(rig.body))
	rig.body.movement_speed.remove_attribute_modifier("haste")
	rig.body._movement_speed = 5.0
	rig.controller.sprint = true
	await _frames(40)
	_check(absf(_speed(rig.body) - 7.5) < 0.15, "sprinting multiplies by the sprint multiplier (%.2f)" % _speed(rig.body))
	rig.body._sprint_multiplier = 2.0
	await _frames(40)
	_check(absf(_speed(rig.body) - 10.0) < 0.2, "which the character decides (%.2f)" % _speed(rig.body))
	rig.controller.sprint = false
	rig.controller.stroll = true
	rig.body._stroll_multiplier = 0.2
	await _frames(40)
	_check(absf(_speed(rig.body) - 1.0) < 0.1, "as it does the stroll (%.2f)" % _speed(rig.body))
	_end_world()

	# How eagerly it reaches its speed.
	var times := []
	for acceleration in [30.0, 3.0]:
		_begin_world(true)
		rig = _make_rig(Vector3(0.0, 0.05, 0.0))
		rig.body.ground_acceleration = acceleration
		await _frames(30)
		rig.controller.move = Vector2(0.0, -1.0)
		await _frames(10)
		times.append(_speed(rig.body))
		_end_world()
	_check(times[0] > 3.5 and times[1] < 2.0, "ground acceleration is the character's: %.2f quick, %.2f slow" % [times[0], times[1]])

	# The tallest step it climbs.
	var tops := []
	for step_height in [0.35, 0.05]:
		_begin_world(true)
		var ledge := StaticBody3D.new()
		var ledge_shape := CollisionShape3D.new()
		var ledge_box := BoxShape3D.new()
		ledge_box.size = Vector3(6.0, 0.2, 4.0)
		ledge_shape.shape = ledge_box
		ledge.add_child(ledge_shape)
		ledge.position = Vector3(0.0, 0.1, -4.0)
		_world.add_child(ledge)
		rig = _make_rig(Vector3(0.0, 0.05, 0.0))
		rig.body.step_height = step_height
		await _frames(30)
		rig.controller.move = Vector2(0.0, -1.0)
		var peak := 0.0
		for tick in 150:
			await _frames(1)
			peak = maxf(peak, rig.body.global_position.y)
		tops.append(peak)
		_end_world()
	_check(tops[0] > 0.15 and tops[1] < 0.1, "the tallest step it climbs is the character's: up to %.2f with a high step, %.2f with a low one" % [tops[0], tops[1]])


## What the character may do is the character's. A wish is dropped when it may not.
func _test_capabilities() -> void:
	_begin_world(true)
	var rig := _make_rig(Vector3(0.0, 0.05, 0.0))
	var body := rig.body
	await _frames(30)

	# Running.
	rig.controller.move = Vector2(0.0, -1.0)
	rig.controller.sprint = true
	await _frames(40)
	_check(absf(_speed(body) - 7.5) < 0.15, "a character that can run runs (%.2f)" % _speed(body))
	body.can_run_blocker.add(1, "winded")
	await _frames(40)
	_check(absf(_speed(body) - 5.0) < 0.15 and not rig.controller.is_sprinting(), "not while something blocks it (%.2f)" % _speed(body))
	body.can_run_blocker.remove(1)
	await _frames(40)
	_check(absf(_speed(body) - 7.5) < 0.15, "and again once it does not (%.2f)" % _speed(body))
	body._can_run = false
	await _frames(40)
	_check(absf(_speed(body) - 5.0) < 0.15, "a character that cannot run at all never does (%.2f)" % _speed(body))
	var wish := MoveIntent.new()
	wish.sprint = true
	wish.crouch = true
	wish.jump_pressed = true
	body._can_crouch = false
	body._can_jump = false
	var allowed := rig.controller.prepare_intent(wish)
	_check(not allowed.sprint and not allowed.crouch and not allowed.jump_pressed, "the rules a server applies to a client's wishes drop all three")
	body._can_run = true
	body._can_crouch = true
	body._can_jump = true
	rig.controller.sprint = false
	rig.controller.move = Vector2.ZERO
	await _frames(30)

	# Crouching.
	rig.controller.crouch = true
	await _frames(20)
	_check(body.is_crouching(), "a character that can crouch does")
	body.can_crouch_blocker.add(2, "must stand")
	await _frames(20)
	_check(not body.is_crouching(), "and stands up when it may not any more, with room to")
	await _frames(20)
	_check(not body.is_crouching(), "and stays up while it may not")
	body.can_crouch_blocker.remove(2)
	await _frames(20)
	_check(body.is_crouching(), "and crouches again when it may")
	rig.controller.crouch = false
	await _frames(20)

	# Jumping.
	var jumps := [0]
	rig.controller.jumped.connect(func() -> void: jumps[0] += 1)
	body.can_jump_blocker.add(3, "pinned")
	rig.controller.jump_once = true
	await _frames(40)
	_check(jumps[0] == 0 and body.global_position.y < 0.1, "a character that may not jump does not")
	body.can_jump_blocker.remove(3)
	rig.controller.jump_once = true
	await _frames(40)
	_check(jumps[0] == 1, "and does when it may")

	# Walking: held in place, it still falls.
	await _frames(60)
	var held_at := body.global_position
	body.can_walk_blocker.add(4, "rooted")
	_check(not body.can_walk(), "a blocker takes away walking")
	rig.controller.move = Vector2(0.0, -1.0)
	await _frames(60)
	_check(Vector2(body.global_position.x - held_at.x, body.global_position.z - held_at.z).length() < 0.1, "a rooted character does not walk (%.2f m)" % Vector2(body.global_position.x - held_at.x, body.global_position.z - held_at.z).length())
	body.can_walk_blocker.remove(4)
	await _frames(60)
	_check(Vector2(body.global_position.x - held_at.x, body.global_position.z - held_at.z).length() > 3.0, "and walks again when it is free")
	_end_world()


## The player's view glides when the body is moved without the player having moved: a stair or a correction.
func _test_visual_offset() -> void:
	_begin_world(true)
	var player := _new_player()
	_world.add_child(player)
	await _frames(40)
	var head := player.head
	var rest := player.get_head_rest_position().y
	_check(is_equal_approx(head.position.y, rest), "the head sits at rest")
	player.add_visual_offset(Vector3(0.0, -0.4, 0.0))
	await get_tree().process_frame
	_check(head.position.y < rest - 0.25, "a move of the body that is not the player's own starts the view where it was (%.2f below rest)" % (rest - head.position.y))
	await _frames(60)
	_check(absf(head.position.y - rest) < 0.01, "and glides back to the body")
	player.add_visual_offset(Vector3(0.0, 0.0, 5.0))
	await get_tree().process_frame
	_check(Vector2(head.position.x, head.position.z).length() <= Player.MAXIMUM_VISUAL_OFFSET + 0.01, "by no more than a meter")
	player.clear_visual_offset()
	await get_tree().process_frame
	_check(Vector2(head.position.x, head.position.z).length() < 0.01, "or not at all when it is meant to be a jump")

	# A real stair, walked up through the controller.
	var step := StaticBody3D.new()
	var step_shape := CollisionShape3D.new()
	var step_box := BoxShape3D.new()
	step_box.size = Vector3(6.0, 0.3, 4.0)
	step_shape.shape = step_box
	step.add_child(step_shape)
	step.position = Vector3(0.0, 0.15, -4.0)
	_world.add_child(step)
	await _frames(5)
	var lowest := rest
	var highest := 0.0
	Input.action_press("move_forward")
	for tick in 150:
		await get_tree().physics_frame
		await get_tree().process_frame
		lowest = minf(lowest, head.position.y)
		highest = maxf(highest, player.global_position.y)
	Input.action_release("move_forward")
	_check(highest > 0.25, "the player climbed the step (%.2f)" % highest)
	_check(lowest < rest - 0.15, "and the view glided up it instead of jumping (lowest %.2f of %.2f)" % [lowest, rest])
	_end_world()


## The player is a walking character, made from its scene: nothing a walking character has is repeated in it.
func _test_player_is_a_walking_character() -> void:
	var base := PLAYER_SCENE.get_state().get_base_scene_state()
	_check(base != null and base.get_path().ends_with("WalkingCharacter3D.tscn"), "the player scene is inherited from the walking character scene")
	var player := _new_player()
	_check(player is WalkingCharacter3D and player is BaseCharacter3D, "so the player is a walking character, which is a base character")
	add_child(player)
	for child_name in ["CollisionShape3D", "Model", "Orientator", "FootstepPlayer", "SoftCollision3D"]:
		var found := 0
		for child in player.get_children():
			if child.name == child_name:
				found += 1
		_check(found == 1, "it has one %s, the walking character's (%d)" % [child_name, found])
	_check(player.get_node_or_null("MovementAttribute") == null and player.get_node_or_null("Orientor") == null, "and none of the copies it used to have")
	for child_name in ["Head", "Rotator", "PlayerCharacterController", "HeadMotion", "ItemMotion", "CharacterNetSync", "ItemHolder", "Inventory"]:
		_check(player.get_node_or_null(child_name) != null, "what is only the player's is in its scene: %s" % child_name)
	var controller := player.get_node("PlayerCharacterController") as CharacterController
	_check(controller.get_body() == player and controller.character == null, "the controller moves it, finding it as its parent")
	player.free()

	var walker := WALKING.instantiate() as WalkingCharacter3D
	add_child(walker)
	_check(walker.get_node_or_null("Orientator") != null and walker.get_node_or_null("FootstepPlayer") != null and walker.get_node_or_null("SoftCollision3D") != null, "the walking character scene has what every walking character has")
	_check(walker.get_node_or_null("Head") == null and walker.get_node_or_null("Rotator") == null, "and none of what is the player's")
	walker.free()


# --- Helpers -----------------------------------------------------------------

func _new_player() -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.position = Vector3(0.0, 0.05, 0.0)
	# The scene may be saved with the holder previewing another view.
	(player.get_node("ItemHolder") as ItemHolder).view = ItemHolder.View.AUTO
	return player


func _begin_world(with_floor: bool) -> void:
	_world = Node3D.new()
	add_child(_world)
	if with_floor:
		var field := DirectionalGravityField3D.new()
		var field_shape := CollisionShape3D.new()
		var field_box := BoxShape3D.new()
		field_box.size = Vector3(300.0, 200.0, 300.0)
		field_shape.shape = field_box
		field_shape.position = Vector3(0.0, 80.0, 0.0)
		field.add_child(field_shape)
		_world.add_child(field)
		var floor_body := StaticBody3D.new()
		var floor_shape := CollisionShape3D.new()
		var floor_box := BoxShape3D.new()
		floor_box.size = Vector3(400.0, 1.0, 400.0)
		floor_shape.shape = floor_box
		floor_body.add_child(floor_shape)
		floor_body.position = Vector3(0.0, -0.5, 0.0)
		_world.add_child(floor_body)


func _end_world() -> void:
	_world.free()
	_world = null


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame


func _check(value: bool, message: String) -> void:
	if value:
		return
	_failures += 1
	push_error("WALKING CHARACTER TEST FAILED: " + message)
	print("FAIL: ", message)


## A character the tests move with a scripted controller, in the world already.
func _make_rig(position: Vector3) -> Rig:
	var rig := Rig.new()
	var body := TestCharacter.make("Walker")
	var controller := Scripted.new()
	controller.name = "Controller"
	body.add_child(controller)
	body.position = position
	_world.add_child(body)
	rig.body = body
	rig.controller = controller
	return rig


func _speed(body: CharacterBody3D) -> float:
	return Vector2(body.velocity.x, body.velocity.z).length()
