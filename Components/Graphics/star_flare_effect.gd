@tool
class_name StarFlareEffect
extends BaseCompositorEffect
## Lens flares and god rays for up to three stars, drawn over the finished picture (before glow and tonemapping, so
## the glow picks the flares up too).
##
## The stars are only directions in the world, so this is given each star's direction, size, color and strength once
## (see [method set_star]) and the shaders find where they are on the screen by themselves, for every camera that
## renders the world. What it draws: a glare around each disc, a thin horizontal streak, ghosts along the line
## through the middle of the screen, and rays, which are haze around the star that is shadowed wherever the depth
## buffer has something between a pixel and the star (so a rock in front of the star casts long dark shafts).
## Everything is dimmer the more of the star something covers, and gone when the star is behind the camera or far off
## to the side: the rays only show while looking toward the star. Every star gets the same flare whatever size its disc
## is drawn (a hotter star is stronger, not wider).
##
## Two compute passes: star_rays.glsl works out the rays at a quarter of the screen's size (that is where the cost is),
## and star_flares.glsl draws everything at full size, using them.
##
## Put it in the [member Compositor.compositor_effects] of the WorldEnvironment; [StarFlares] does that for the stars
## of a [StarField]. It needs the Forward+ or Mobile renderer; with any other it silently does nothing.
##
## Based on the lens_effects addon by ARez (MIT, see addons/lens_effects), whose [BaseCompositorEffect] it extends.

const RAYS_SHADER_PATH := "res://Components/Graphics/star_rays.glsl"
const FLARES_SHADER_PATH := "res://Components/Graphics/star_flares.glsl"
const MAX_STARS := 3
const EFFECT_DATA_UBO_BINDING := 0
## The rays are worked out at this fraction of the screen's width and height.
const RAY_DOWNSCALE := 4
## How much in front of the camera a star has to be (the cosine of the angle from where it looks) for the shaders to
## draw anything for it. The same number is in both shaders.
const AHEAD_LIMIT := 0.02
const RAYS_BINDING := 3
const TEXTURE_CONTEXT := &"StarFlares"
const RAYS_TEXTURE := &"rays"

@export_group("Glare")
## How strong the glare around each star's disc is.
@export_range(0.0, 4.0, 0.01) var glare_strength := 1.0:
	set(value):
		glare_strength = value
		_rebuild_data()
## How strong the thin horizontal streak through each star is.
@export_range(0.0, 4.0, 0.01) var streak_strength := 1.0:
	set(value):
		streak_strength = value
		_rebuild_data()
## How far the streak reaches, in screen heights, for a small star (a big one gets a longer streak).
@export_range(0.05, 4.0, 0.05) var streak_length := 0.4:
	set(value):
		streak_length = value
		_rebuild_data()
## How strong the ghosts are, the reflections that line up through the middle of the screen. 0 has none.
@export_range(0.0, 4.0, 0.01) var ghost_strength := 0.5:
	set(value):
		ghost_strength = value
		_rebuild_data()

@export_group("God rays")
## How strong the rays are. 0 has none (and the depth buffer is not walked at all).
@export_range(0.0, 4.0, 0.01) var ray_strength := 0.3:
	set(value):
		ray_strength = value
		_rebuild_data()
## How many times each point looks toward the star to find what is in the way. More is smoother and costs more;
## 0 has no rays.
@export_range(0, 128, 1) var ray_samples := 48:
	set(value):
		ray_samples = value
		_rebuild_data()
## How much of the way to the star has to be blocked before the shadow is complete. Higher makes harder shadows:
## a thin rock then still casts a full one.
@export_range(1.0, 32.0, 0.5) var shadow_hardness := 8.0:
	set(value):
		shadow_hardness = value
		_rebuild_data()

var _mutex := Mutex.new()
var _directions: Array[Vector3] = [Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD]
var _tangents: Array[float] = [0.1, 0.1, 0.1]
var _colors: Array[Color] = [Color.WHITE, Color.WHITE, Color.WHITE]
var _strengths: Array[float] = [1.0, 1.0, 1.0]
var _star_count := 0
## The uniform block as plain values, in the order of the shaders' StarBlock. Made here, read on the render thread.
var _data: Array = []
var _data_changed := true

var _tried_shaders := false
var _rays_shader: RID
var _rays_pipeline: RID
var _flares_shader: RID
var _flares_pipeline: RID
var _data_buffer: RID
var _data_uniform: RDUniform
var _rays_texture: RID
var _rays_size := Vector2i.ONE


func _init() -> void:
	# The base class makes its samplers and finds the rendering device in its own constructor, which GDScript only
	# runs when asked to.
	super()
	# After everything see-through, because the stars are, and before the tonemapper.
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	# With antialiasing on, these make the effect see the resolved picture and depth rather than the multisampled ones.
	access_resolved_color = true
	access_resolved_depth = true
	_rebuild_data()


## Sets star [param index] (0 to 2): which way it is (a unit vector in the world), half the angle across its disc in
## radians, the color of its glare, and how strong the glare is (1 for a sun-like star). (The size of the disc reaches
## the shaders but is not used by them at the moment, since the flare is the same for every size.)
func set_star(index: int, direction: Vector3, angular_radius: float, color: Color, strength: float) -> void:
	if index < 0 or index >= MAX_STARS:
		return
	_mutex.lock()
	_directions[index] = direction.normalized()
	_tangents[index] = tan(clampf(angular_radius, 0.001, 1.4))
	_colors[index] = color
	_strengths[index] = strength
	_mutex.unlock()
	_rebuild_data()


## How many stars to draw, from 0 to 3. The first ones set with [method set_star] are used.
func set_star_count(count: int) -> void:
	_star_count = clampi(count, 0, MAX_STARS)
	_rebuild_data()


func get_star_count() -> int:
	return _star_count


## Takes all the stars away.
func clear_stars() -> void:
	set_star_count(0)


## The values the shaders will get, as their uniform block lays them out (eight vec4s). For checking.
func get_uniform_values() -> Array:
	_mutex.lock()
	var copy := _data.duplicate()
	_mutex.unlock()
	return copy


func _rebuild_data() -> void:
	_mutex.lock()
	var data: Array = []
	for index in MAX_STARS:
		var direction := _directions[index]
		data.append(Vector4(direction.x, direction.y, direction.z, _tangents[index]))
	for index in MAX_STARS:
		var color := _colors[index]
		data.append(Vector4(color.r, color.g, color.b, _strengths[index]))
	data.append(Vector4(float(_star_count), glare_strength, streak_strength, ghost_strength))
	data.append(Vector4(ray_strength, float(ray_samples), streak_length, shadow_hardness))
	_data = data
	_data_changed = true
	_mutex.unlock()


func _render_size_changed() -> void:
	# The textures of the old size go, and the rays one is made again in the new size.
	render_scene_buffers.clear_context(TEXTURE_CONTEXT)
	_rays_texture = RID()


func _render_setup() -> void:
	# Made here, on the render thread when it first draws, rather than when the resource is made.
	if not _tried_shaders:
		_tried_shaders = true
		_rays_shader = create_shader(RAYS_SHADER_PATH)
		if _rays_shader.is_valid():
			_rays_pipeline = create_pipeline(_rays_shader)
		_flares_shader = create_shader(FLARES_SHADER_PATH)
		if _flares_shader.is_valid():
			_flares_pipeline = create_pipeline(_flares_shader)
	var wanted_size := Vector2i(
		maxi(ceili(float(render_size.x) / RAY_DOWNSCALE), 1),
		maxi(ceili(float(render_size.y) / RAY_DOWNSCALE), 1),
	)
	# The engine frees the textures of a context whenever it rebuilds its buffers, which includes changing the
	# antialiasing and not only the size, so ask whether the texture is still there.
	if not _rays_texture.is_valid() or not rd.texture_is_valid(_rays_texture) or _rays_size != wanted_size:
		render_scene_buffers.clear_context(TEXTURE_CONTEXT)
		_rays_size = wanted_size
		# (Not the base class's create_simple_texture, which predates the extra argument of this engine version.)
		render_scene_buffers.create_texture(TEXTURE_CONTEXT, RAYS_TEXTURE, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
			RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT,
			RenderingDevice.TEXTURE_SAMPLES_1, _rays_size, 1, 1, true, false)
		_rays_texture = render_scene_buffers.get_texture_slice(TEXTURE_CONTEXT, RAYS_TEXTURE, 0, 0, 1, 1)
	if not _data_buffer.is_valid():
		_mutex.lock()
		var first_data := _data.duplicate()
		_data_changed = false
		_mutex.unlock()
		_data_buffer = create_uniform_buffer(first_data)
		_data_uniform = get_uniform_buffer_uniform(_data_buffer, EFFECT_DATA_UBO_BINDING)
		return
	_mutex.lock()
	var changed := _data_changed
	var latest := _data.duplicate() if changed else []
	_data_changed = false
	_mutex.unlock()
	if changed:
		update_uniform_buffer(_data_buffer, latest)


## Whether any star is in front of the camera. When none is (looking away from them, or from inside a room with the
## star behind a wall), the shaders find nothing to draw, so they are not run at all. It leaves out only what the shaders
## would not draw either: a star on the camera's side or behind it.
func _is_any_star_ahead() -> bool:
	var forward := -render_scene_data.get_cam_transform().basis.z
	_mutex.lock()
	var directions := _directions.duplicate()
	_mutex.unlock()
	for index in _star_count:
		if (directions[index] as Vector3).dot(forward) > AHEAD_LIMIT:
			return true
	return false


func _render_view(view: int) -> void:
	if _star_count <= 0 or not _flares_pipeline.is_valid() or not _rays_texture.is_valid() or not _is_any_star_ahead():
		return
	var effect_uniforms: Array[RDUniform] = [_data_uniform]
	var depth_uniform := get_depth_sampler_uniform(view, nearest_sampler)

	if ray_samples > 0 and ray_strength > 0.0 and _rays_pipeline.is_valid():
		var ray_uniforms: Array[RDUniform] = [
			get_scene_data_ubo(),
			get_image_uniform(_rays_texture, COLOR_IMAGE_BINDING),
			depth_uniform,
		]
		var screen_groups := _workgroups
		_workgroups = Vector3i(ceili(_rays_size.x / 16.0), ceili(_rays_size.y / 16.0), 1)
		run_compute_shader("Star rays", _rays_shader, _rays_pipeline, [ray_uniforms, effect_uniforms])
		_workgroups = screen_groups

	var flare_uniforms: Array[RDUniform] = [
		get_scene_data_ubo(),
		get_color_image_uniform(view),
		depth_uniform,
		get_sampler_uniform(_rays_texture, linear_sampler, RAYS_BINDING),
	]
	run_compute_shader("Star flares", _flares_shader, _flares_pipeline, [flare_uniforms, effect_uniforms])
