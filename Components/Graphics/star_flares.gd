class_name StarFlares
extends RefCounted
## Gives the stars of a system lens flares and god rays: it puts a [StarFlareEffect] in the compositor of the level's
## WorldEnvironment, tells it where the stars are, and follows the Graphics Quality setting. A [StarField] makes one
## of these and uses it, so nothing in a scene has to be set up.
##
## The effect is added to whatever compositor the WorldEnvironment already has (one is made if it has none) and is taken
## out again by [method detach], leaving the compositor as it was. With no WorldEnvironment in the level, or a renderer
## that cannot run compute shaders, it does nothing.
##
## If the WorldEnvironment is an [AdvEnvironment] the effect follows the quality: [member GraphicsPreset.lens_flares]
## turns it off and [member GraphicsPreset.god_ray_samples] can only lower the samples the effect was authored with.

## How strong the glare of a star is, from how much heat it gives: a sun-like star (heat 1) is 1, a tiny far one is
## dimmer and a huge near one stronger.
const MIN_STRENGTH := 0.5
const MAX_STRENGTH := 1.8

## The effect that draws them. Made when this is, unless one was given.
var effect: StarFlareEffect

var _environment: WorldEnvironment
var _made_compositor := false
var _authored_ray_samples := 0


func _init(flare_effect: StarFlareEffect = null) -> void:
	effect = flare_effect if flare_effect != null else StarFlareEffect.new()
	_authored_ray_samples = effect.ray_samples


## Finds the WorldEnvironment that [param host] is in the tree with and puts the effect in its compositor. Does nothing
## if that is done already; returns whether the effect is in a compositor now. Safe to call again later when there was
## no WorldEnvironment yet.
func attach(host: Node) -> bool:
	if is_attached():
		return true
	if host == null or not host.is_inside_tree():
		return false
	var found := host.get_tree().root.find_children("*", "WorldEnvironment", true, false)
	if found.is_empty():
		return false
	_environment = found[0] as WorldEnvironment
	var compositor := _environment.compositor
	if compositor == null:
		compositor = Compositor.new()
		_environment.compositor = compositor
		_made_compositor = true
	var effects: Array[CompositorEffect] = compositor.compositor_effects.duplicate()
	if not effects.has(effect):
		effects.append(effect)
		compositor.compositor_effects = effects
	var advanced := _environment as AdvEnvironment
	if advanced != null:
		if not advanced.preset_applied.is_connected(apply_preset):
			advanced.preset_applied.connect(apply_preset)
		apply_preset(advanced.get_preset(GraphicsQuality.get_level()))
	return true


## Takes the effect out of the compositor again.
func detach() -> void:
	if _environment == null:
		return
	if is_instance_valid(_environment):
		var advanced := _environment as AdvEnvironment
		if advanced != null and advanced.preset_applied.is_connected(apply_preset):
			advanced.preset_applied.disconnect(apply_preset)
		var compositor := _environment.compositor
		if compositor != null:
			var effects: Array[CompositorEffect] = compositor.compositor_effects.duplicate()
			effects.erase(effect)
			compositor.compositor_effects = effects
			if _made_compositor and effects.is_empty():
				_environment.compositor = null
	_environment = null
	_made_compositor = false


func is_attached() -> bool:
	if _environment == null or not is_instance_valid(_environment):
		_environment = null
		return false
	var compositor := _environment.compositor
	return compositor != null and compositor.compositor_effects.has(effect)


## The WorldEnvironment the effect is in, or null.
func get_environment() -> WorldEnvironment:
	return _environment if is_attached() else null


## Shows the flares and rays of the stars of [param system] (the first three; the rest are too faint to matter), or
## none for null.
func show_system(system: StarSystem) -> void:
	if system == null:
		clear()
		return
	var count := mini(system.stars.size(), StarFlareEffect.MAX_STARS)
	for index in count:
		var spec := system.stars[index]
		effect.set_star(index, spec.direction, spec.angular_radius, get_glare_color(spec), get_strength(spec))
	effect.set_star_count(count)


## Takes the flares away until the next system.
func clear() -> void:
	effect.clear_stars()


## Follows [param preset]: whether there are flares at all, and how many samples the rays may take.
func apply_preset(preset: GraphicsPreset) -> void:
	effect.enabled = preset.lens_flares
	effect.ray_samples = mini(_authored_ray_samples, preset.god_ray_samples)


## The color a star's glare has: the disc's own color (see [member StarSpec.color_boost]), which is stronger than the
## pale color of its light, kept inside what a screen can show.
static func get_glare_color(spec: StarSpec) -> Color:
	var hue := Color.WHITE.lerp(spec.color, spec.color_boost)
	return Color(clampf(hue.r, 0.0, 1.0), clampf(hue.g, 0.0, 1.0), clampf(hue.b, 0.0, 1.0))


static func get_strength(spec: StarSpec) -> float:
	return clampf(MIN_STRENGTH + 0.5 * sqrt(maxf(spec.heat, 0.0)), MIN_STRENGTH, MAX_STRENGTH)
