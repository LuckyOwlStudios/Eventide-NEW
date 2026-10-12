extends Node
## Headless checks for the Graphics Quality setting: AdvEnvironment and the pause blur.
##
## godot --headless --fixed-fps 60 --path . res://Components/Graphics/Testing/GraphicsQualityTest.tscn

var _failures := 0
var _original_quality: Variant


func _ready() -> void:
	_original_quality = Settings.get_setting(GraphicsQuality.SETTING_ID)
	await _run()
	Settings.set_setting(GraphicsQuality.SETTING_ID, _original_quality, false)
	if _failures == 0:
		print("Graphics quality tests passed.")
	else:
		print("Graphics quality tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _run() -> void:
	_check(GraphicsQuality.level_from_id(&"low") == GraphicsQuality.Level.LOW, "level names map to levels")
	_check(GraphicsQuality.level_from_id(&"ultra") == GraphicsQuality.Level.ULTRA and GraphicsQuality.level_from_id(&"nonsense") == GraphicsQuality.Level.MEDIUM, "and unknown names fall back to medium")

	# A world with glow on, a sun with shadows, a lamp with shadows and a lamp without.
	var holder := Node3D.new()
	add_child(holder)
	var adv := AdvEnvironment.new()
	var authored := Environment.new()
	authored.glow_enabled = true
	adv.environment = authored
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	var lamp := OmniLight3D.new()
	lamp.shadow_enabled = true
	var plain := SpotLight3D.new()
	plain.shadow_enabled = false
	holder.add_child(sun)
	holder.add_child(lamp)
	holder.add_child(plain)
	holder.add_child(adv)
	await get_tree().process_frame
	var viewport := get_viewport()

	_set_quality(&"low")
	_check(not adv.environment.glow_enabled, "low: glow is off")
	_check(not sun.shadow_enabled and not lamp.shadow_enabled, "low: shadows are off")
	_check(is_equal_approx(viewport.scaling_3d_scale, 0.75), "low: the 3D world renders at 75%% (%.2f)" % viewport.scaling_3d_scale)
	_check(viewport.msaa_3d == Viewport.MSAA_DISABLED, "low: no antialiasing")

	_set_quality(&"medium")
	_check(adv.environment.glow_enabled, "medium: glow is back")
	_check(sun.shadow_enabled and lamp.shadow_enabled, "medium: shadows are back")
	_check(is_equal_approx(viewport.scaling_3d_scale, 1.0), "medium: full resolution")
	_check(not plain.shadow_enabled, "a light that never had shadows still has none")

	_set_quality(&"ultra")
	_check(viewport.msaa_3d == Viewport.MSAA_2X, "ultra: antialiasing is on")
	_check(viewport.positional_shadow_atlas_size == 4096, "ultra: sharper light shadows (%d)" % viewport.positional_shadow_atlas_size)
	_check(authored.glow_enabled and adv.environment != authored, "the saved Environment was never changed, only a copy")

	# A light that turns up later is covered by whatever quality is current.
	_set_quality(&"low")
	var latecomer := SpotLight3D.new()
	latecomer.shadow_enabled = true
	holder.add_child(latecomer)
	_check(not latecomer.shadow_enabled, "low: a light added later has its shadows off too")
	_set_quality(&"high")
	_check(latecomer.shadow_enabled, "and gets them back with the quality")

	# A scene that turned glow off keeps it off at any quality.
	var dim := Environment.new()
	dim.glow_enabled = false
	var dim_adv := AdvEnvironment.new()
	dim_adv.environment = dim
	holder.add_child(dim_adv)
	_set_quality(&"ultra")
	_check(not dim_adv.environment.glow_enabled, "glow the scene turned off stays off even on ultra")
	dim_adv.free()

	# Presets can be replaced.
	adv.low = GraphicsPreset.create(true, true, 0.5, Viewport.MSAA_DISABLED, 512)
	_set_quality(&"low")
	_check(is_equal_approx(viewport.scaling_3d_scale, 0.5) and adv.environment.glow_enabled, "a preset set on the node replaces the built-in one")

	holder.free()
	_check(is_equal_approx(viewport.scaling_3d_scale, 1.0) and viewport.msaa_3d == Viewport.MSAA_DISABLED, "leaving the world puts the window back as it was")

	# The pause blur: a live blur from high up, otherwise one picture taken when it starts.
	var blur := BlurOverlay.new()
	add_child(blur)
	blur.snapshot_downscale = 10
	var grabs := [0]
	blur.screen_grabber = func() -> Image:
		grabs[0] += 1
		var image := Image.create(400, 200, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.8, 0.2, 0.2))
		return image
	for entry in [[&"low", true], [&"medium", true], [&"high", false], [&"ultra", false]]:
		var snapshot: bool = entry[1]
		_set_quality(entry[0])
		grabs[0] = 0
		blur.fade_in(0.0)
		_check(blur.visible, "%s: the blur is showing" % entry[0])
		_check(blur.is_using_snapshot() == snapshot and blur.is_using_live_blur() == not snapshot, "%s: as %s" % [entry[0], "a still picture" if snapshot else "a live blur"])
		_check(grabs[0] == (1 if snapshot else 0), "%s: %s (%d)" % [entry[0], "one picture was taken" if snapshot else "none was taken", grabs[0]])
		_check((blur.material == null) == snapshot, "%s: and the blur shader is %s" % [entry[0], "left off" if snapshot else "on"])
		blur.fade_out(0.0)
		_check(not blur.visible, "%s: fading out hides it" % entry[0])

	# Fading in and out over time takes one picture, not one per frame.
	_set_quality(&"medium")
	grabs[0] = 0
	blur.fade_in(0.2)
	for i in 30:
		await get_tree().process_frame
	_check(grabs[0] == 1 and blur.is_using_snapshot() and is_equal_approx(blur.blur_amount, 1.0), "a fade takes a single picture (%d) and ends fully blurred" % grabs[0])
	var snapshot_rect := blur.get_child(0, true) as TextureRect
	_check(snapshot_rect.texture != null and snapshot_rect.texture.get_width() == 160 and snapshot_rect.texture.get_height() == 80, "the picture is shrunk a lot, then smoothed back up a little (%dx%d)" % [snapshot_rect.texture.get_width(), snapshot_rect.texture.get_height()])
	_check(is_equal_approx(snapshot_rect.modulate.a, 1.0), "and fully shown")
	blur.fade_out(0.2)
	for i in 30:
		await get_tree().process_frame
	_check(not blur.visible and snapshot_rect.texture == null, "fading out hides it and drops the picture")

	# Raising the quality while it shows swaps in the live blur; lowering it waits.
	_set_quality(&"low")
	blur.fade_in(0.0)
	_check(blur.is_using_snapshot(), "low: a picture")
	_set_quality(&"high")
	_check(blur.is_using_live_blur() and blur.visible, "raising to high switches to the live blur at once")
	_set_quality(&"low")
	_check(blur.is_using_live_blur(), "lowering it again waits for the next time")
	blur.fade_out(0.0)
	blur.fade_in(0.0)
	_check(blur.is_using_snapshot(), "which is the next blur")
	blur.fade_out(0.0)

	# If there is no picture to be had, a live blur is better than none.
	blur.screen_grabber = func() -> Image: return null
	blur.fade_in(0.0)
	_check(blur.is_using_live_blur(), "with nothing to take a picture of, it blurs live instead")
	blur.fade_out(0.0)
	blur.free()
	_set_quality(&"medium")


func _set_quality(id: StringName) -> void:
	Settings.set_setting(GraphicsQuality.SETTING_ID, id, false)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)
