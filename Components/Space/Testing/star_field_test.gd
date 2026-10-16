extends Node
## Checks the star field: that every star of a system becomes a mesh drawn in the sky and a light pointing the right way,
## that only the brightest star casts shadows, that a new system replaces the old one's stars, and that the level's own sun
## is switched off while the stars light it, and on again after. (What the stars look like is checked with screenshots;
## a headless run draws nothing.)
##
## godot --headless --fixed-fps 60 --path . res://Components/Space/Testing/StarFieldTest.tscn

const Kit := preload("res://Components/Space/Testing/space_test_kit.gd")

var _failures := 0


func _ready() -> void:
	await _run()


func _run() -> void:
	await _test_building_stars()
	await _test_replacing()
	await _test_the_levels_sun()
	if _failures == 0:
		print("Star field tests passed.")
	else:
		print("Star field tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _find_system(stars: int) -> StarSystem:
	return StarSystem.create(3, 20, SystemTuning.new(), Vector3.ZERO, Kit.flat_template(0.0, 0.5, stars))


func _test_building_stars() -> void:
	print("Stars and their light")
	var field := StarField.new()
	add_child(field)
	var system := _find_system(3)
	_check(system.get_star_count() == 3, "a system with three stars to show")
	field.show_system(system)
	await get_tree().process_frame
	var meshes := field.get_star_meshes()
	var lights := field.get_star_lights()
	_check(meshes.size() == 3 and lights.size() == 3 and field.get_child_count() == 6, "every star is a mesh and a light (%d, %d)" % [meshes.size(), lights.size()])
	var right_way := true
	var colored := true
	var shaded := true
	var in_the_sky := true
	for index in 3:
		var spec := system.stars[index]
		var light := lights[index]
		right_way = right_way and (-light.global_basis.z).dot(-spec.direction) > 0.9999
		colored = colored and light.light_color == spec.color and is_equal_approx(light.light_energy, spec.light_energy)
		shaded = shaded and light.shadow_enabled == (index == 0)
		var material := meshes[index].material_override as ShaderMaterial
		in_the_sky = in_the_sky and material != null and material.shader == StarField.SHADER
		in_the_sky = in_the_sky and (material.get_shader_parameter(&"direction") as Vector3).is_equal_approx(spec.direction)
		in_the_sky = in_the_sky and is_equal_approx(material.get_shader_parameter(&"angular_radius"), spec.angular_radius)
		in_the_sky = in_the_sky and (material.get_shader_parameter(&"star_color") as Color) == spec.color
		in_the_sky = in_the_sky and material.get_shader_parameter(&"star_texture") == StarField.STAR_TEXTURE
		in_the_sky = in_the_sky and material.render_priority < 0
		in_the_sky = in_the_sky and meshes[index].cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		in_the_sky = in_the_sky and meshes[index].custom_aabb.size.x >= 1.0e6
	_check(right_way, "each light shines away from its star, on the system")
	_check(colored, "in the star's color and with the energy the system gives it")
	_check(shaded, "and only the brightest star's light casts shadows")
	_check(in_the_sky, "each mesh runs the star shader with the star's direction, size, color and the star texture, drawn first of the see-through things, never culled away")
	var total := 0.0
	for light in lights:
		total += light.light_energy
	_check(is_equal_approx(total, system.light_energy), "the lights add up to the system's light (%.2f)" % total)
	var in_groups := true
	for mesh in meshes:
		in_groups = in_groups and mesh.is_in_group(StarField.STAR_GROUP)
	for light in lights:
		in_groups = in_groups and light.is_in_group(StarField.LIGHT_GROUP)
	_check(in_groups, "they are in groups, so anything can find them")
	_check(StarField.SHADER.get_code().contains("POSITION") and StarField.SHADER.get_code().contains("blend_premul_alpha"), "and the shader puts each star at the far end of the sky")
	field.free()
	await get_tree().process_frame


func _test_replacing() -> void:
	print("A new system")
	var field := StarField.new()
	add_child(field)
	var first := _find_system(2)
	field.show_system(first)
	var old_meshes := field.get_star_meshes()
	var old_lights := field.get_star_lights()
	var second := _find_system(1)
	field.show_system(second)
	await get_tree().process_frame
	_check(field.get_star_meshes().size() == 1 and field.get_star_lights().size() == 1 and field.get_child_count() == 2, "the new system's stars replace the old one's (%d children)" % field.get_child_count())
	var gone := true
	for node: Node in old_meshes:
		gone = gone and not is_instance_valid(node)
	for node: Node in old_lights:
		gone = gone and not is_instance_valid(node)
	_check(gone, "and the old ones are freed")
	var still_right := (-field.get_star_lights()[0].global_basis.z).dot(-second.stars[0].direction) > 0.9999
	_check(still_right, "the light is the new star's")
	field.clear()
	await get_tree().process_frame
	_check(field.get_child_count() == 0 and field.get_star_meshes().is_empty(), "clearing takes every star away")
	field.show_system(null)
	_check(field.get_child_count() == 0, "and showing no system shows none")
	field.free()
	await get_tree().process_frame


func _test_the_levels_sun() -> void:
	print("The level's own sun")
	var level := Node3D.new()
	add_child(level)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.75
	level.add_child(sun)
	var lamp := OmniLight3D.new()
	level.add_child(lamp)
	var field := StarField.new()
	level.add_child(field)
	await get_tree().process_frame
	field.show_system(_find_system(1))
	_check(not sun.visible and lamp.visible, "the level's sun is switched off while the stars light it, and other lights are left alone")
	_check(field.get_lights_taken_over().size() == 1 and field.get_lights_taken_over()[0] == sun, "and it knows which it took")
	for node in field.get_star_lights():
		_check(node.visible, "while the stars' own lights are on")
	field.show_system(_find_system(2))
	_check(not sun.visible, "a new system leaves it off")
	level.remove_child(field)
	_check(sun.visible, "and it comes back on when the stars go")
	field.free()

	var other := Node3D.new()
	add_child(other)
	var spare := DirectionalLight3D.new()
	other.add_child(spare)
	var keeping := StarField.new()
	keeping.take_over_lights = false
	other.add_child(keeping)
	await get_tree().process_frame
	keeping.show_system(_find_system(1))
	_check(spare.visible and keeping.get_lights_taken_over().is_empty(), "with take_over_lights off, the level's sun stays on")
	level.free()
	other.free()
	await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)
