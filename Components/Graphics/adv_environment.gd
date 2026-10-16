class_name AdvEnvironment
extends WorldEnvironment
## A WorldEnvironment that follows the Graphics Quality setting.
##
## Use it in place of a WorldEnvironment. When the level is chosen, and whenever the player
## changes it, it applies that level's [GraphicsPreset]: glow, light shadows, the 3D
## render scale and antialiasing. Lights added later (a vehicle spawning in) are covered too.
##
## It never turns on something the scene turned off. The Environment and each light keep
## whatever they were authored with, and the quality can only take it away.
## (The pause blur follows the same setting; see [BlurOverlay], and the flares and rays of the stars follow it too,
## through [signal preset_applied]; see [StarFlares].)

## Emitted every time a preset is applied: when the level is chosen, when the player changes the quality and when
## [method apply] is called. Anything that costs frame time and should follow the quality can listen to this.
signal preset_applied(preset: GraphicsPreset)

@export_group("Presets")
## Leave a preset empty to use the built-in one for that level.
@export var low: GraphicsPreset
@export var medium: GraphicsPreset
@export var high: GraphicsPreset
@export var ultra: GraphicsPreset

var _authored_glow := false
var _authored_shadows: Dictionary[Light3D, bool] = {}


func _ready() -> void:
	if environment != null:
		# Work on a copy so changing quality never edits the saved resource.
		environment = environment.duplicate()
		_authored_glow = environment.glow_enabled
	for light: Light3D in get_tree().root.find_children("*", "Light3D", true, false):
		_authored_shadows[light] = light.shadow_enabled
	get_tree().node_added.connect(_on_node_added)
	Settings.setting_changed.connect(_on_setting_changed)
	apply()


func _exit_tree() -> void:
	# Leaving the world (to a menu, say) leaves the window as it was.
	var viewport := get_viewport()
	if viewport != null:
		viewport.scaling_3d_scale = 1.0
		viewport.msaa_3d = Viewport.MSAA_DISABLED


## Applies the current quality level now. This happens by itself; call it only after
## changing a preset while the game runs.
func apply() -> void:
	var preset := get_preset(GraphicsQuality.get_level())
	if environment != null:
		environment.glow_enabled = _authored_glow and preset.glow
	for light in _authored_shadows.keys():
		if is_instance_valid(light):
			light.shadow_enabled = _authored_shadows[light] and preset.shadows
		else:
			_authored_shadows.erase(light)
	var viewport := get_viewport()
	viewport.scaling_3d_scale = preset.render_scale
	viewport.msaa_3d = preset.msaa
	viewport.positional_shadow_atlas_size = preset.positional_shadow_atlas_size
	preset_applied.emit(preset)


## The preset used at [param level]: the one set here, or the built-in one.
func get_preset(level: GraphicsQuality.Level) -> GraphicsPreset:
	var chosen: GraphicsPreset
	match level:
		GraphicsQuality.Level.LOW: chosen = low
		GraphicsQuality.Level.HIGH: chosen = high
		GraphicsQuality.Level.ULTRA: chosen = ultra
		_: chosen = medium
	return chosen if chosen != null else _built_in_preset(level)


func _built_in_preset(level: GraphicsQuality.Level) -> GraphicsPreset:
	match level:
		GraphicsQuality.Level.LOW:
			return GraphicsPreset.create(false, false, 0.75, Viewport.MSAA_DISABLED, 1024, false, 0)
		GraphicsQuality.Level.HIGH:
			return GraphicsPreset.create(true, true, 1.0, Viewport.MSAA_DISABLED, 2048, true, 48)
		GraphicsQuality.Level.ULTRA:
			return GraphicsPreset.create(true, true, 1.0, Viewport.MSAA_2X, 4096, true, 64)
	return GraphicsPreset.create(true, true, 1.0, Viewport.MSAA_DISABLED, 2048, true, 24)


func _on_setting_changed(id: StringName, _value: Variant) -> void:
	if id == GraphicsQuality.SETTING_ID:
		apply()


func _on_node_added(node: Node) -> void:
	var light := node as Light3D
	if light == null or _authored_shadows.has(light):
		return
	_authored_shadows[light] = light.shadow_enabled
	light.shadow_enabled = light.shadow_enabled and get_preset(GraphicsQuality.get_level()).shadows
