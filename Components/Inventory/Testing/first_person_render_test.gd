extends Node
## Looks at real pixels to check how an item in the holder's own hands is drawn: over a wall it is
## inside of, lit like any world item, with a field of view of its own. It needs a window, so it does
## nothing when the display is headless.
##
## godot --path . --windowed --resolution 1280x720 res://Components/Inventory/Testing/FirstPersonRenderTest.tscn
## SHOTS=<folder> saves the screenshots there. ONLY=<name> runs one test, such as ONLY=lighting.

const PLAYER_SCENE := preload("res://Scenes/Player/Player.tscn")
const FLASHLIGHT: Item = preload("res://Game/Registry/Items/Flashlight/flashlight_item.tres")

var _failures := 0
var _shots := ""
var _world: Node3D


func _ready() -> void:
	_run()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("First person render tests skipped: they need a window.")
		get_tree().quit()
		return
	_shots = OS.get_environment("SHOTS")
	var only := OS.get_environment("ONLY")
	for test_name in ["on_top", "lighting", "field_of_view", "beam", "wall", "cost"]:
		if only.is_empty() or only == test_name:
			print("-- ", test_name)
			await call("_test_" + test_name)
	if _failures == 0:
		print("First person render tests passed.")
	else:
		print("First person render tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# --- Tests -------------------------------------------------------------------

## The point of it all: a held item is drawn over a wall it is inside of. (A player cannot stand closer
## to a wall than the radius of the capsule, 0.4 m, so this is about as close as the camera ever gets.)
func _test_on_top() -> void:
	var setup := _make_world(0.45)
	var holder: ItemHolder = setup["holder"]
	holder.avoid_walls = false
	await _frames(6)
	var empty := await _capture("on_top_1_empty_hand")

	holder.equip_item(_give_flashlight(setup))
	await _frames(8)
	var held := await _capture("on_top_2_item_in_hand_inside_the_wall")
	var mask := _changed_mask(empty, held, 0.03)
	var covered := _count(mask)
	var total := mask.get_width() * mask.get_height()
	_check(covered > total / 100, "the item shows over the wall, taking up part of the screen (%.1f%%)" % (100.0 * covered / total))
	var corner := _share_in(mask, Rect2i(int(mask.get_width() * 0.5), int(mask.get_height() * 0.4), int(mask.get_width() * 0.5), int(mask.get_height() * 0.6)))
	_check(corner > 0.95, "in the lower right, where a hand holds it (%.0f%% of it)" % (100.0 * corner))
	var elsewhere := _mean_difference(empty, held, Rect2i(0, 0, empty.get_width(), int(empty.get_height() * 0.5)))
	_check(elsewhere < 0.002, "and nothing else on screen changed (%.4f)" % elsewhere)

	# For contrast: the same item drawn as a world item, completely behind the wall, is not seen at all.
	holder.unequip_item()
	await _frames(6)
	var behind_pose := (setup["camera"] as Node3D).global_transform * Transform3D(Basis.IDENTITY, Vector3(0.3, -0.25, -1.0))
	var world_item := FLASHLIGHT.spawn_in_world(_give_flashlight(setup), _world, behind_pose)
	world_item.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	world_item.freeze = true
	(world_item.get_node("InteractableObject3D") as InteractableObject3D).show_distance_dot = false
	await _frames(8)
	var behind := await _capture("on_top_3_a_world_item_behind_the_wall")
	var lower_right := Rect2i(int(empty.get_width() * 0.5), int(empty.get_height() * 0.4), int(empty.get_width() * 0.5), int(empty.get_height() * 0.6))
	var hidden := _mean_difference(empty, behind, lower_right)
	_check(hidden < 0.004, "(a world item behind the wall is not seen: %.4f)" % hidden)
	_end_world()


## A held item is lit like any other thing in the world: drawn in hand and drawn as a world item in the
## same place, with the same field of view, it looks the same.
func _test_lighting() -> void:
	var setup := _make_world(50.0)
	var holder: ItemHolder = setup["holder"]
	var camera: Camera3D = setup["camera"]
	holder.avoid_walls = false
	await _frames(6)
	var empty := await _capture("lighting_1_empty_hand")
	var instance := _give_flashlight(setup)
	holder.equip_item(instance)
	var actor := holder.equipped_actor
	await _frames(8)
	var held := await _capture("lighting_2_in_hand")
	var mask := _changed_mask(empty, held, 0.03)
	var pose := actor.global_transform
	holder.unequip_item()
	await _frames(3)

	var lying := FLASHLIGHT.spawn_in_world(instance, _world, pose)
	lying.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	lying.freeze = true
	var pickup := lying.get_node("InteractableObject3D") as InteractableObject3D
	pickup.show_distance_dot = false
	pickup.show_interaction_selector = false
	await _frames(8)
	var world := await _capture("lighting_3_as_a_world_item")
	var difference := _mean_difference_on(held, world, mask)
	var worst := _percentile_difference(held, world, mask, 0.98)
	_check(_count(mask) > 2000, "the item is on screen (%d pixels)" % _count(mask))
	_check(difference < 0.01, "an item in hand and the same item in the world look alike: mean difference %.5f" % difference)
	_check(worst < 0.1, "even at the edges: 98%% of pixels within %.3f" % worst)
	_end_world()


## A held item keeps its place and size on screen when the world's field of view changes.
func _test_field_of_view() -> void:
	var setup := _make_world(50.0)
	var holder: ItemHolder = setup["holder"]
	var camera: Camera3D = setup["camera"]
	holder.avoid_walls = false
	var instance := _give_flashlight(setup)
	camera.fov = 75.0
	await _frames(6)
	var empty_narrow := await _capture("fov_1_empty_75")
	holder.equip_item(instance)
	await _frames(8)
	var narrow := _changed_mask(empty_narrow, await _capture("fov_2_held_world_75"), 0.03)
	holder.unequip_item()
	camera.fov = 100.0
	await _frames(6)
	var empty_wide := await _capture("fov_3_empty_100")
	holder.equip_item(instance)
	await _frames(8)
	var wide := _changed_mask(empty_wide, await _capture("fov_4_held_world_100"), 0.03)
	var overlap := _overlap(narrow, wide)
	_check(_count(narrow) > 2000 and _count(wide) > 2000, "the item is on screen in both")
	_check(overlap > 0.9, "and covers the same pixels whether the world is seen at 75 or 100 degrees (%.0f%% shared)" % (100.0 * overlap))
	_end_world()


## The flashlight's beam lights the world from the item in hand.
func _test_beam() -> void:
	var setup := _make_world(3.0)
	var holder: ItemHolder = setup["holder"]
	(setup["sun"] as DirectionalLight3D).light_energy = 0.0
	holder.equip_item(_give_flashlight(setup))
	await _frames(8)
	var dark := await _capture("beam_1_off")
	var wall_region := Rect2i(int(dark.get_width() * 0.35), int(dark.get_height() * 0.3), int(dark.get_width() * 0.3), int(dark.get_height() * 0.4))
	(holder.equipped_actor as FlashlightActor).toggle()
	await _frames(8)
	var lit := await _capture("beam_2_on")
	var before := _mean_luma(dark, wall_region)
	var after := _mean_luma(lit, wall_region)
	_check(after > before + 0.05, "switching it on lights the wall in front: %.3f -> %.3f" % [before, after])
	_end_world()


## With the nose near a wall the light would start inside it. The item comes back so that it does not.
## (Pressed against a wall a flashlight lights only a small bright spot, so this is judged by where the
## light is, and the screenshots show how it looks.)
func _test_wall() -> void:
	var setup := _make_world(0.5)
	var holder: ItemHolder = setup["holder"]
	holder.equip_item(_give_flashlight(setup))
	var actor := holder.equipped_actor as FlashlightActor
	actor.toggle()
	holder.avoid_walls = false
	await _frames(40)
	_check(actor.light.global_position.z < -0.5, "left where it is held, the light is inside the wall (%.2f)" % actor.light.global_position.z)
	await _capture("wall_1_item_inside_the_wall")

	holder.avoid_walls = true
	await _frames(40)
	_check(actor.light.global_position.z > -0.5, "pulled back, the light is in front of the wall (%.2f)" % actor.light.global_position.z)
	_check(actor.global_position.z - actor.reach > -0.5, "and so is the front of the item")
	await _capture("wall_2_item_pulled_back")
	_end_world()


## What holding an item costs, so it can be weighed. Printed, not judged: each figure is the median frame
## time with vsync off. The item held is compared with nothing, and with the same item lying in the world
## drawn as the world draws it, which shows what the first-person drawing adds to the item itself.
func _test_cost() -> void:
	var setup := _make_world(50.0)
	var holder: ItemHolder = setup["holder"]
	var camera: Camera3D = setup["camera"]
	var instance := _give_flashlight(setup)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _frames(20)
	var before := await _median_frame_ms(90)

	# The first frames after the world gets its first flashlight, drawn as a world item.
	var lying_pose := camera.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.3, -0.25, -0.55))
	var lying_first := await _frame_times(FLASHLIGHT.create_instance(), lying_pose)
	var lying := await _median_frame_ms(90)
	for node in _world.get_children():
		if node is ItemActor:
			node.free()
	await _frames(10)

	var held_first: Array[float] = await _first_frame_times(holder, instance)
	var held := await _median_frame_ms(90)
	holder.unequip_item()
	await _frames(10)
	var after := await _median_frame_ms(90)
	var baseline := (before + after) * 0.5
	print("  info frame time: %.2f ms with nothing held; %.2f ms with the flashlight lying in the world (%+.2f); %.2f ms holding it (%+.2f)" % [baseline, lying, lying - baseline, held, held - baseline])
	print("  info the first frames after its first appearance: as a world item %s ms, in hand %s ms (a normal frame is about %.1f)" % [_format_ms(lying_first), _format_ms(held_first), baseline])
	_end_world()


# --- Helpers -----------------------------------------------------------------

## A world with a sun, a sky and a wall [param wall_distance] meters in front of the player (far away for
## no wall), and the real Player scene looking at it.
func _make_world(wall_distance: float) -> Dictionary:
	_world = Node3D.new()
	add_child(_world)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.4
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 1.5
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_world.add_child(world_environment)

	# It travels toward -Z a little downward, so it falls on faces that look back at the player.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, -25.0, 0.0)
	sun.shadow_enabled = true
	_world.add_child(sun)

	var wall := StaticBody3D.new()
	wall.collision_layer = PhysicsLayers.WORLD
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 20, 0.2)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	var wall_mesh := MeshInstance3D.new()
	var wall_box := BoxMesh.new()
	wall_box.size = box.size
	wall_mesh.mesh = wall_box
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.62, 0.6, 0.55)
	wall_mesh.material_override = wall_material
	wall.add_child(wall_mesh)
	_world.add_child(wall)
	wall.position = Vector3(0.0, 1.6, -wall_distance - 0.1)

	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	# A test window must not take the mouse.
	(player.get_node("Rotator") as Rotator).capture_mouse_on_start = false
	_world.add_child(player)
	return {
		"player": player,
		"holder": player.get_node("ItemHolder"),
		"camera": player.get_node("Head/YawPivot/PitchPivot/Camera3D"),
		"sun": sun,
		"wall": wall,
	}


func _end_world() -> void:
	_world.free()
	_world = null


func _give_flashlight(setup: Dictionary) -> FlashlightInstance:
	var instance := FLASHLIGHT.create_instance() as FlashlightInstance
	((setup["player"] as Node).get_node("Inventory") as Inventory).add(instance)
	return instance


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## What the window shows, saved if SHOTS says where.
func _capture(label: String) -> Image:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if not _shots.is_empty():
		image.save_png(_shots.path_join(label + ".png"))
	return image


func _color_distance(a: Color, b: Color) -> float:
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0


func _luma(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722


## A picture of which pixels differ between two others (white where they do), at half the size.
func _changed_mask(a: Image, b: Image, threshold: float) -> Image:
	var mask := Image.create_empty(int(a.get_width() * 0.5), int(a.get_height() * 0.5), false, Image.FORMAT_L8)
	for y in mask.get_height():
		for x in mask.get_width():
			if _color_distance(a.get_pixel(x * 2, y * 2), b.get_pixel(x * 2, y * 2)) > threshold:
				mask.set_pixel(x, y, Color.WHITE)
	return mask


func _count(mask: Image) -> int:
	var count := 0
	for y in mask.get_height():
		for x in mask.get_width():
			if mask.get_pixel(x, y).r > 0.5:
				count += 1
	return count


## The share of a mask's white pixels that lie in an area of full-size picture coordinates.
func _share_in(mask: Image, area: Rect2i) -> float:
	var inside := 0
	var total := 0
	for y in mask.get_height():
		for x in mask.get_width():
			if mask.get_pixel(x, y).r > 0.5:
				total += 1
				if area.has_point(Vector2i(x, y)):
					inside += 1
	return float(inside) / maxf(total, 1)


## How much of the smaller of two masks the other one covers.
func _overlap(a: Image, b: Image) -> float:
	var both := 0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y).r > 0.5 and b.get_pixel(x, y).r > 0.5:
				both += 1
	return float(both) / maxf(mini(_count(a), _count(b)), 1)


## Mean difference between two pictures over an area.
func _mean_difference(a: Image, b: Image, area: Rect2i) -> float:
	var sum := 0.0
	var count := 0
	for y in range(area.position.y, area.end.y, 3):
		for x in range(area.position.x, area.end.x, 3):
			sum += _color_distance(a.get_pixel(x, y), b.get_pixel(x, y))
			count += 1
	return sum / maxf(count, 1)


## Mean difference between two pictures over the pixels a half-size mask marks.
func _mean_difference_on(a: Image, b: Image, mask: Image) -> float:
	var sum := 0.0
	var count := 0
	for y in mask.get_height():
		for x in mask.get_width():
			if mask.get_pixel(x, y).r > 0.5:
				sum += _color_distance(a.get_pixel(x * 2, y * 2), b.get_pixel(x * 2, y * 2))
				count += 1
	return sum / maxf(count, 1)


## The difference below which this share of the marked pixels lie.
func _percentile_difference(a: Image, b: Image, mask: Image, share: float) -> float:
	var differences: Array[float] = []
	for y in mask.get_height():
		for x in mask.get_width():
			if mask.get_pixel(x, y).r > 0.5:
				differences.append(_color_distance(a.get_pixel(x * 2, y * 2), b.get_pixel(x * 2, y * 2)))
	if differences.is_empty():
		return 1.0
	differences.sort()
	return differences[mini(int(differences.size() * share), differences.size() - 1)]


func _mean_luma(image: Image, area: Rect2i) -> float:
	var sum := 0.0
	var count := 0
	for y in range(area.position.y, area.end.y, 3):
		for x in range(area.position.x, area.end.x, 3):
			sum += _luma(image.get_pixel(x, y))
			count += 1
	return sum / maxf(count, 1)


## Puts an item in the world and times the frames that follow.
func _frame_times(instance: ItemInstance, pose: Transform3D) -> Array[float]:
	var actor := FLASHLIGHT.spawn_in_world(instance, _world, pose)
	actor.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	actor.freeze = true
	(actor.get_node("InteractableObject3D") as InteractableObject3D).show_distance_dot = false
	return await _times_of_next_frames(6)


## Equips an item and times the frames that follow.
func _first_frame_times(holder: ItemHolder, instance: ItemInstance) -> Array[float]:
	var times: Array[float] = []
	var last := Time.get_ticks_usec()
	holder.equip_item(instance)
	for i in 6:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
	return times


func _times_of_next_frames(count: int) -> Array[float]:
	var times: Array[float] = []
	var last := Time.get_ticks_usec()
	for i in count:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
	return times


func _format_ms(times: Array[float]) -> String:
	return str(times.map(func(ms: float) -> String: return "%.1f" % ms))


func _median_frame_ms(samples: int) -> float:
	var times: Array[float] = []
	var last := Time.get_ticks_usec()
	for i in samples:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
	times.sort()
	return times[int(times.size() * 0.5)]


func _check(value: bool, message: String) -> void:
	if value:
		return
	_failures += 1
	push_error("FIRST PERSON RENDER TEST FAILED: " + message)
	print("FAIL: ", message)
