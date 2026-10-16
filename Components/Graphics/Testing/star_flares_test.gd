extends Node
## Headless checks for the lens flares and god rays of the stars: the numbers the effect hands its shaders, how StarFlares
## builds them from a system, how it installs itself in (and leaves) the level's compositor, how the Graphics Quality
## setting turns it down, and that a StarField uses it. (What it looks like is checked with screenshots, and the
## shaders themselves only compile with a rendering device, so a headless run cannot see them.)
##
## godot --headless --fixed-fps 60 --path . res://Components/Graphics/Testing/StarFlaresTest.tscn

const Kit := preload("res://Components/Space/Testing/space_test_kit.gd")

var _failures := 0
var _original_quality: Variant


func _ready() -> void:
	_original_quality = Settings.get_setting(GraphicsQuality.SETTING_ID)
	await _run()
	Settings.set_setting(GraphicsQuality.SETTING_ID, _original_quality, false)
	if _failures == 0:
		print("Star flares tests passed.")
	else:
		print("Star flares tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _run() -> void:
	_test_effect_data()
	_test_building_from_a_system()
	await _test_installing()
	await _test_quality()
	await _test_star_field()
	_test_shader_files()


func _system(stars: int) -> StarSystem:
	return StarSystem.create(3, 20, SystemTuning.new(), Vector3.ZERO, Kit.flat_template(0.0, 0.5, stars))


func _test_effect_data() -> void:
	print("What the effect gives its shaders")
	var effect := StarFlareEffect.new()
	_check(effect.effect_callback_type == CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT, "it runs after the see-through things, where the stars are")
	_check(effect.access_resolved_color and effect.access_resolved_depth, "and sees the resolved picture and depth when there is antialiasing")
	_check(effect.get_star_count() == 0 and effect.get_uniform_values().size() == 8, "no stars to start with; eight vec4s in the block")

	effect.set_star(0, Vector3(0.0, 0.0, 5.0), 0.1, Color(1.0, 0.5, 0.25), 1.5)
	effect.set_star(2, Vector3.UP, 0.2, Color.BLUE, 0.7)
	effect.set_star(3, Vector3.RIGHT, 0.3, Color.RED, 9.0)
	effect.set_star(-1, Vector3.RIGHT, 0.3, Color.RED, 9.0)
	effect.set_star_count(2)
	var values := effect.get_uniform_values()
	var first: Vector4 = values[0]
	_check(first.is_equal_approx(Vector4(0.0, 0.0, 1.0, tan(0.1))), "a star is a unit direction and the tangent of its radius (%s)" % first)
	var third: Vector4 = values[2]
	_check(third.is_equal_approx(Vector4(0.0, 1.0, 0.0, tan(0.2))), "the third slot is the star set at 2")
	var color: Vector4 = values[3]
	_check(color.is_equal_approx(Vector4(1.0, 0.5, 0.25, 1.5)), "then each star's color and strength (%s)" % color)
	var counts: Vector4 = values[6]
	_check(counts.is_equal_approx(Vector4(2.0, effect.glare_strength, effect.streak_strength, effect.ghost_strength)), "then how many stars, and the glare, streak and ghost strengths (%s)" % counts)
	var rays: Vector4 = values[7]
	_check(rays.is_equal_approx(Vector4(effect.ray_strength, float(effect.ray_samples), effect.streak_length, effect.shadow_hardness)), "then the rays' strength and samples, the streak's length and the shadows' hardness")
	var untouched_star: Vector4 = values[1]
	var untouched_color: Vector4 = values[4]
	_check(untouched_star.is_equal_approx(Vector4(0.0, 0.0, -1.0, 0.1)) and untouched_color.is_equal_approx(Vector4.ONE), "slots never set keep their defaults, and out-of-range indexes are ignored")

	effect.glare_strength = 2.5
	effect.ray_samples = 12
	values = effect.get_uniform_values()
	var changed_counts: Vector4 = values[6]
	var changed_rays: Vector4 = values[7]
	_check(is_equal_approx(changed_counts.y, 2.5) and is_equal_approx(changed_rays.y, 12.0), "changing a setting changes the block")
	effect.set_star_count(99)
	_check(effect.get_star_count() == 3, "no more than three stars")
	effect.clear_stars()
	_check(effect.get_star_count() == 0, "and they can all be taken away")
	effect.set_star(0, Vector3.ZERO, 0.1, Color.WHITE, 1.0)
	var zero_direction: Vector4 = effect.get_uniform_values()[0]
	_check(is_finite(zero_direction.x) and is_finite(zero_direction.w), "a bad direction does not make a bad number")


func _test_building_from_a_system() -> void:
	print("Building the effect's stars from a system")
	var system := _system(3)
	var flares := StarFlares.new()
	flares.show_system(system)
	var values := flares.effect.get_uniform_values()
	_check(flares.effect.get_star_count() == 3, "every star of a ternary system is there")
	var all_right := true
	for index in 3:
		var spec := system.stars[index]
		var star: Vector4 = values[index]
		var glare: Vector4 = values[3 + index]
		all_right = all_right and Vector3(star.x, star.y, star.z).is_equal_approx(spec.direction.normalized())
		all_right = all_right and is_equal_approx(star.w, tan(spec.angular_radius))
		var expected := StarFlares.get_glare_color(spec)
		all_right = all_right and is_equal_approx(glare.x, expected.r) and is_equal_approx(glare.y, expected.g) and is_equal_approx(glare.z, expected.b)
		all_right = all_right and is_equal_approx(glare.w, StarFlares.get_strength(spec))
	_check(all_right, "each with the direction, size, color and strength of its star")

	var spec := StarSpec.new()
	spec.heat = 1.0
	_check(is_equal_approx(StarFlares.get_strength(spec), 1.0), "a sun-like star glares at 1")
	spec.heat = 0.0
	_check(is_equal_approx(StarFlares.get_strength(spec), StarFlares.MIN_STRENGTH), "a very faint one at the least")
	spec.heat = 400.0
	_check(is_equal_approx(StarFlares.get_strength(spec), StarFlares.MAX_STRENGTH), "a huge one at the most")
	spec.color = Color(0.9, 0.8, 0.7)
	spec.color_boost = 1.7
	var glare := StarFlares.get_glare_color(spec)
	_check(glare.r <= 1.0 and glare.g >= 0.0 and glare.b >= 0.0 and glare.b < spec.color.b, "its glare is the disc's stronger color, kept on the screen (%s)" % glare)

	flares.show_system(_system(1))
	_check(flares.effect.get_star_count() == 1, "a new system replaces the stars")
	flares.show_system(null)
	_check(flares.effect.get_star_count() == 0, "and no system has none")
	flares.show_system(_system(2))
	flares.clear()
	_check(flares.effect.get_star_count() == 0, "clear takes them away")


func _test_installing() -> void:
	print("Installing in the compositor")
	var holder := Node3D.new()
	add_child(holder)
	var flares := StarFlares.new()
	_check(not flares.attach(holder), "without a WorldEnvironment there is nothing to attach to")
	var environment := WorldEnvironment.new()
	holder.add_child(environment)
	_check(flares.attach(holder), "with one, it attaches (even though it looked before it was there)")
	_check(environment.compositor != null and _effects_of(environment) == [flares.effect], "a compositor is made, with the effect in it")
	_check(flares.is_attached() and flares.get_environment() == environment, "and it knows where it is")
	flares.attach(holder)
	_check(environment.compositor.compositor_effects.size() == 1, "attaching twice does not add it twice")
	flares.detach()
	_check(environment.compositor == null and not flares.is_attached(), "taking it away takes the compositor it made away too")

	var other := CompositorEffect.new()
	var compositor := Compositor.new()
	compositor.compositor_effects = [other]
	environment.compositor = compositor
	flares.attach(holder)
	_check(environment.compositor == compositor and _effects_of(environment) == [other, flares.effect], "a compositor that is there is kept, and the effect goes after what it has")
	flares.detach()
	_check(environment.compositor == compositor and _effects_of(environment) == [other], "and is left as it was")
	flares.detach()
	_check(true, "taking it away twice is fine")

	var loose := Node3D.new()
	_check(not StarFlares.new().attach(loose), "a node outside the tree cannot attach")
	loose.free()

	flares.attach(holder)
	environment.free()
	_check(not flares.is_attached() and flares.get_environment() == null, "if the environment is freed it is not attached any more")
	flares.detach()
	holder.free()
	await get_tree().process_frame


func _test_quality() -> void:
	print("Following the Graphics Quality setting")
	var holder := Node3D.new()
	add_child(holder)
	var adv := AdvEnvironment.new()
	holder.add_child(adv)
	await get_tree().process_frame
	var presets: Array[GraphicsPreset] = []
	adv.preset_applied.connect(func(preset: GraphicsPreset) -> void: presets.append(preset))
	_set_quality(&"medium")
	_check(presets.size() == 1 and presets[0].lens_flares and presets[0].god_ray_samples == 24, "the environment says which preset it applied (medium)")

	var flares := StarFlares.new()
	flares.attach(holder)
	_check(flares.effect.enabled and flares.effect.ray_samples == 24, "medium: flares, and rays of 24 samples (%d)" % flares.effect.ray_samples)
	_set_quality(&"low")
	_check(not flares.effect.enabled, "low: no flares at all")
	_set_quality(&"high")
	_check(flares.effect.enabled and flares.effect.ray_samples == 48, "high: back, with 48 samples (%d)" % flares.effect.ray_samples)
	_set_quality(&"ultra")
	_check(flares.effect.ray_samples == 48, "ultra: the effect's own 48 is the limit, though the preset allows more (%d)" % flares.effect.ray_samples)
	_set_quality(&"medium")
	_check(flares.effect.ray_samples == 24, "and the samples come down again")

	var gentle := StarFlareEffect.new()
	gentle.ray_samples = 10
	var gentle_flares := StarFlares.new(gentle)
	gentle_flares.attach(holder)
	_set_quality(&"high")
	_check(gentle.ray_samples == 10, "a look made with fewer samples than the preset allows keeps them (%d)" % gentle.ray_samples)
	gentle_flares.detach()

	adv.low = GraphicsPreset.create(true, true, 1.0, Viewport.MSAA_DISABLED, 1024, true, 8)
	_set_quality(&"low")
	_check(flares.effect.enabled and flares.effect.ray_samples == 8, "a preset set on the environment decides, rays and all (%d)" % flares.effect.ray_samples)

	flares.detach()
	flares.effect.enabled = true
	flares.effect.ray_samples = 40
	_set_quality(&"medium")
	_check(flares.effect.enabled and flares.effect.ray_samples == 40, "detached, it no longer follows the quality")
	holder.free()
	_set_quality(&"medium")
	await get_tree().process_frame


func _test_star_field() -> void:
	print("A StarField uses it")
	var holder := Node3D.new()
	add_child(holder)
	var environment := WorldEnvironment.new()
	holder.add_child(environment)
	var field := StarField.new()
	holder.add_child(field)
	_check(field.get_flares() == null, "nothing is made before there are stars")
	field.show_system(_system(3))
	var flares := field.get_flares()
	_check(flares != null and flares.is_attached(), "showing a system puts the effect in the level's compositor")
	_check(flares.effect.get_star_count() == 3 and field.get_child_count() == 6, "with all its stars, and no nodes of its own in the field")
	field.show_system(_system(1))
	_check(flares.effect.get_star_count() == 1 and flares.is_attached(), "a new system replaces them")
	field.clear()
	_check(flares.effect.get_star_count() == 0 and flares.is_attached(), "clearing takes the stars but not the effect")
	field.show_system(_system(2))

	holder.remove_child(field)
	_check(not flares.is_attached() and environment.compositor == null, "a field that leaves the level takes the effect out")
	holder.add_child(field)
	_check(flares.is_attached() and flares.effect.get_star_count() == 2, "and puts it back, with its stars, when it returns")

	var shown_effect := StarFlareEffect.new()
	shown_effect.glare_strength = 3.0
	field.free()
	var own_look := StarField.new()
	own_look.flare_effect = shown_effect
	holder.add_child(own_look)
	own_look.show_system(_system(1))
	_check(own_look.get_flares().effect == shown_effect and _effects_of(environment) == [shown_effect], "a look set on the field is the one used")
	own_look.free()

	var plain := StarField.new()
	plain.lens_flares = false
	holder.add_child(plain)
	plain.show_system(_system(2))
	_check(plain.get_flares() == null and environment.compositor == null, "with lens_flares off there is no effect")
	_check(plain.get_star_meshes().size() == 2, "and the stars are there as usual")
	plain.free()
	holder.free()
	await get_tree().process_frame

	var quiet_holder := Node3D.new()
	add_child(quiet_holder)
	var no_environment := StarField.new()
	quiet_holder.add_child(no_environment)
	no_environment.show_system(_system(2))
	_check(no_environment.get_flares() != null and not no_environment.get_flares().is_attached(), "with no WorldEnvironment it does nothing, quietly")
	quiet_holder.free()
	await get_tree().process_frame


func _test_shader_files() -> void:
	print("The shader files")
	var rays := _read_text(StarFlareEffect.RAYS_SHADER_PATH)
	var flares := _read_text(StarFlareEffect.FLARES_SHADER_PATH)
	_check(rays.begins_with("#[compute]") and flares.begins_with("#[compute]"), "both are compute shaders")
	_check(rays.contains("local_size_x = 16, local_size_y = 16") and flares.contains("local_size_x = 16, local_size_y = 16"), "with the 16 by 16 groups the effect dispatches")
	var rays_block := _between(rays, "uniform StarBlock {", "} stars;")
	var flares_block := _between(flares, "uniform StarBlock {", "} stars;")
	_check(rays_block != "" and rays_block == flares_block, "both read the same block of numbers")
	_check(flares.contains("binding = %d) uniform sampler2D rays_sampler" % StarFlareEffect.RAYS_BINDING), "the full-size pass reads the rays where the effect binds them")
	_check(rays.contains("binding = 1) uniform restrict writeonly image2D rays_image"), "and the quarter-size pass writes them where it binds them")
	_check(StarFlareEffect.MAX_STARS == 3 and rays.contains("const int MAX_STARS = 3;") and flares.contains("const int MAX_STARS = 3;"), "three stars everywhere")
	_check(flares.contains("inv_view_matrix") and not flares.contains("scene.data.view_matrix"), "the stars are put on the screen with the camera's own matrix, as the engine names it")
	_check(rays.contains("if (star.z <= 0.0)") and not rays.contains("params_c"), "the rays are only made for a star that is in view, so they show only when looking toward it")
	_check(rays.contains("ahead <= 0.02") and flares.contains("ahead <= 0.02") and is_equal_approx(StarFlareEffect.AHEAD_LIMIT, 0.02), "and a star not in front of the camera is one the shaders draw nothing for, which is when the effect does not run them at all")


func _effects_of(environment: WorldEnvironment) -> Array:
	var found: Array = []
	if environment.compositor != null:
		found.assign(environment.compositor.compositor_effects)
	return found


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""


func _between(text: String, start: String, end: String) -> String:
	var from := text.find(start)
	if from < 0:
		return ""
	var to := text.find(end, from)
	if to < 0:
		return ""
	return text.substr(from, to - from)


func _set_quality(id: StringName) -> void:
	Settings.set_setting(GraphicsQuality.SETTING_ID, id, false)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)
