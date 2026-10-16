class_name StarField
extends Node3D
## The stars of the system the ship is in: what each looks like in the sky, and the light it casts.
##
## For every [StarSpec] of the system (see [StarGenerator]) this makes a mesh drawn with the star shader and a
## [DirectionalLight3D] pointing from the star at the system. The mesh is only a way to run the shader: it is drawn
## at the far end of the sky, behind everything, so it cannot be flown to and never gets closer; its size on screen
## is how near the star is, and how near it is decides how warm the system is. The light is colored like the star,
## and is brighter in a hotter system (see [member StarSystem.light_energy]). Only the brightest star casts shadows,
## which are the costly part.
##
## A new system replaces the old one's stars. The level's own sun (any other [DirectionalLight3D] in the level) is
## switched off while this is in use ([member take_over_lights]), since the star is the sun now, and is switched
## back on if this is removed.
##
## The stars also get lens flares and god rays, drawn over the picture by a compositor effect in the level's
## WorldEnvironment (see [StarFlares] and [StarFlareEffect]); [member lens_flares] turns that off.

const SHADER := preload("res://Assets/Shaders/star.gdshader")
const STAR_TEXTURE := preload("res://Assets/Textures/star.jpg")
## Every light and every star mesh made here is in this group.
const LIGHT_GROUP: StringName = &"star_light"
const STAR_GROUP: StringName = &"star_visual"

@export_group("Look")
## How bright the disc of a star is. Its hot patches go above 1 and bloom, if the level has glow, and a
## brighter disc than this loses the surface detail to white.
@export_range(0.2, 8.0, 0.05) var disc_energy := 1.0
## How bright the corona around it is.
@export_range(0.0, 4.0, 0.05) var corona_energy := 0.6
## How many disc widths out the glow around a star reaches.
@export_range(2.0, 12.0, 0.5) var corona_reach := 7.0

@export_group("Light")
## Switches off the level's own [DirectionalLight3D]s while the stars light it.
@export var take_over_lights := true
## How far from the camera the brightest star's shadows reach, in meters.
@export_range(10.0, 2000.0, 10.0, "suffix:m") var shadow_distance := 200.0

@export_group("Flares")
## Lens flares and god rays around the stars. They follow the Graphics Quality setting; this turns them off
## for good.
@export var lens_flares := true
## How they look. Leave empty for the default look.
@export var flare_effect: StarFlareEffect

var _stars: Array[MeshInstance3D] = []
var _lights: Array[DirectionalLight3D] = []
var _taken: Array[DirectionalLight3D] = []
var _looked_for_lights := false
var _system: StarSystem
var _flares: StarFlares


func _init() -> void:
	# The sky does not move with the ship, and nothing here should be smoothed or carried.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _enter_tree() -> void:
	# Back in a level after being out of it: the flares went with the last one.
	if _flares != null and _system != null and lens_flares:
		_flares.attach(self)


func _exit_tree() -> void:
	for light in _taken:
		if is_instance_valid(light):
			light.visible = true
	_taken.clear()
	_looked_for_lights = false
	if _flares != null:
		_flares.detach()


## Shows the stars of [param system] and lights it with them, putting away the last system's.
func show_system(system: StarSystem) -> void:
	_system = system
	_remove_stars()
	_show_flares(system)
	if system == null:
		return
	_take_over_scene_lights()
	for index in system.stars.size():
		_add_star(system.stars[index], index == 0)


## Takes the stars away. The level's own sun stays off until this node leaves the tree.
func clear() -> void:
	_system = null
	_remove_stars()
	_show_flares(null)


## What draws the lens flares and god rays of the stars, or null when there are none (see [member lens_flares]).
func get_flares() -> StarFlares:
	return _flares


## The star meshes, brightest first.
func get_star_meshes() -> Array[MeshInstance3D]:
	return _stars.duplicate()


## The lights of the stars, brightest first.
func get_star_lights() -> Array[DirectionalLight3D]:
	return _lights.duplicate()


## The level's lights this has switched off.
func get_lights_taken_over() -> Array[DirectionalLight3D]:
	return _taken.duplicate()


func _add_star(spec: StarSpec, brightest: bool) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"direction", spec.direction)
	material.set_shader_parameter(&"angular_radius", spec.angular_radius)
	material.set_shader_parameter(&"quad_radius", corona_reach)
	material.set_shader_parameter(&"star_color", spec.color)
	material.set_shader_parameter(&"color_boost", spec.color_boost)
	# Bluer stars are brighter and redder ones dimmer, but only a little, or a blue disc is just white.
	material.set_shader_parameter(&"disc_energy", disc_energy * lerpf(1.0, spec.brightness, 0.35))
	material.set_shader_parameter(&"corona_energy", corona_energy)
	material.set_shader_parameter(&"spin_phase", spec.spin_phase)
	material.set_shader_parameter(&"spin_speed", spec.spin_speed)
	material.set_shader_parameter(&"tilt", spec.tilt)
	material.set_shader_parameter(&"star_texture", STAR_TEXTURE)
	# Before everything else that is see-through, so nothing is drawn under it by mistake.
	material.render_priority = -100

	var mesh := MeshInstance3D.new()
	mesh.name = "Star%d" % _stars.size()
	mesh.mesh = quad
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# The shader puts it where it wants it, so where it is and how big it is mean nothing to the culling.
	mesh.custom_aabb = AABB(Vector3.ONE * -1.0e6, Vector3.ONE * 2.0e6)
	mesh.ignore_occlusion_culling = true
	mesh.add_to_group(STAR_GROUP)
	add_child(mesh)
	_stars.append(mesh)

	var light := DirectionalLight3D.new()
	light.name = "StarLight%d" % _lights.size()
	light.light_color = spec.color
	light.light_energy = spec.light_energy
	light.shadow_enabled = brightest
	light.directional_shadow_max_distance = shadow_distance
	light.add_to_group(LIGHT_GROUP)
	# The light travels away from the star, so it looks along minus the direction the star is in.
	var up := Vector3.UP if absf(spec.direction.y) < 0.99 else Vector3.RIGHT
	light.transform = Transform3D(Basis.looking_at(-spec.direction, up), Vector3.ZERO)
	add_child(light)
	_lights.append(light)


func _show_flares(system: StarSystem) -> void:
	if not lens_flares:
		if _flares != null:
			_flares.detach()
		return
	if _flares == null:
		_flares = StarFlares.new(flare_effect)
	if system != null:
		_flares.attach(self)
	_flares.show_system(system)


func _remove_stars() -> void:
	for node in _stars:
		if is_instance_valid(node):
			remove_child(node)
			node.queue_free()
	for node in _lights:
		if is_instance_valid(node):
			remove_child(node)
			node.queue_free()
	_stars.clear()
	_lights.clear()


## Finds the level's own sun the first time, and switches it off.
func _take_over_scene_lights() -> void:
	if _looked_for_lights or not take_over_lights or not is_inside_tree():
		return
	_looked_for_lights = true
	for node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		var light := node as DirectionalLight3D
		if light != null and not is_ancestor_of(light) and not light.is_in_group(LIGHT_GROUP) and light.visible:
			_taken.append(light)
			light.visible = false
