class_name InteractableObjectPrompter
extends Node3D

## Shows every available interaction of the object being looked at, in the 3D world: a selector
## frame around the object and a panel of options beside it. Both are billboard quads that belong to
## the object (see [InteractablePrompt]), so they go wherever it goes without anyone placing them.
## This node owns the one SubViewport the options are drawn in, one pixel of it per screen pixel,
## and each frame sizes the quads of the object being looked at.
##
## Interactables that are in reach but not being looked at have a dot of their own. This node
## only decides which of them may show it (see _update_dots).

signal entry_action_pressed(interactable: InteractableObject3D, option_index: int)
signal entry_interaction_succeeded(interactable: InteractableObject3D, option_index: int)

const KEY_BIND_INTERACTION_ENTRY := preload("res://Components/UI/Interaction/KeyBindInteractionEntry.tscn")

## Frames to wait after a new object is looked at before showing the quads, so the SubViewport has
## drawn its options at least once.
const REVEAL_FRAMES := 2

## How many texels the options panel gets per real screen pixel, in each direction. More than 1
## makes the text and icons smooth, like the selector, because the GPU averages them down.
const SUPERSAMPLE := 2.0

## Gap, in screen pixels, between the selector and the options. When the object has no selector,
## the options are placed this far from its prompt spot instead.
@export var screen_offset := Vector2(18.0, 0.0)
## How close the options may get to the edge of the screen.
@export_range(0.0, 128.0, 1.0) var screen_margin := 20.0

@export_group("Distance Dots")
## Turns the dots on interactables that are not being looked at on or off. How far each dot shows
## is set on the interactable (Dot Distance), and how it looks in InteractableDot.tscn.
@export var dots_enabled := true
@export_group("")

@onready var sub_viewport: SubViewport = $SubViewport
@onready var option_list: VBoxContainer = %OptionList

var _interaction_ray: InteractionRayCast3D
var _interactable_object: InteractableObject3D
var _prompt: InteractablePrompt
var _option_indices: Array[int] = []
var _entries: Dictionary[int, KeybindInteractionEntry] = {}
var _reveal_frames := 0
## The size of the options panel in logical (UI) pixels. The SubViewport itself is rendered at the
## window's real resolution so the text stays sharp when the window is scaled.
var _ui_size := Vector2i.ZERO
## Real window pixels per logical (UI) pixel, set by _match_window_resolution.
var _pixel_scale := 1.0


func _ready() -> void:
	option_list.hide()
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_ui_size = sub_viewport.size
	sub_viewport.size_2d_override = _ui_size
	sub_viewport.size_2d_override_stretch = true


func _exit_tree() -> void:
	_detach_prompt()


func _process(_delta: float) -> void:
	_update_dots()
	_update_prompt()


func _physics_process(_delta: float) -> void:
	if is_instance_valid(_interactable_object):
		_interactable_object.update_prompt_anchor(_get_focus_point())


# The entries live in a SubViewport, which nothing feeds input to, so key presses are handed on.
func _input(event: InputEvent) -> void:
	if not is_instance_valid(_interactable_object) or event is InputEventMouseMotion:
		return
	sub_viewport.push_input(event)


func bind_to_interaction_ray(interaction_ray: InteractionRayCast3D) -> void:
	if _interaction_ray == interaction_ray:
		return
	_disconnect_interaction_ray()
	_interaction_ray = interaction_ray
	if not is_instance_valid(_interaction_ray):
		clear()
		return
	_interaction_ray.hold_progress_changed.connect(_on_hold_progress_changed)
	_interaction_ray.interaction_option_succeeded.connect(_on_interaction_option_succeeded)


func display_options(interactable: InteractableObject3D, option_indices: Array[int]) -> void:
	if not is_instance_valid(interactable) or option_indices.is_empty():
		clear()
		return
	if _interactable_object == interactable and _option_indices == option_indices:
		option_list.show()
		return
	if _interactable_object != interactable:
		_detach_prompt()
		_interactable_object = interactable
		_attach_prompt()
	_option_indices = option_indices.duplicate()
	_rebuild_entries()
	option_list.show()
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func clear() -> void:
	_detach_prompt()
	_interactable_object = null
	_option_indices.clear()
	_entries.clear()
	for child in option_list.get_children():
		option_list.remove_child(child)
		child.queue_free()
	option_list.hide()
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func get_entry(option_index: int) -> KeybindInteractionEntry:
	return _entries.get(option_index)


## True while the selector and options are on screen (they are held back for a moment after a new
## object is looked at, and hidden while the object is behind the camera).
func is_showing_prompt() -> bool:
	return is_instance_valid(_prompt) and _prompt.visible


## The selector and options of the object being looked at, or null.
func get_prompt() -> InteractablePrompt:
	return _prompt if is_instance_valid(_prompt) else null


func _attach_prompt() -> void:
	_prompt = _interactable_object.show_prompt(sub_viewport.get_texture())
	_interactable_object.update_prompt_anchor(_get_focus_point())
	_prompt.hide()
	_reveal_frames = REVEAL_FRAMES


func _detach_prompt() -> void:
	if is_instance_valid(_interactable_object):
		_interactable_object.hide_prompt()
	_prompt = null


func _rebuild_entries() -> void:
	_entries.clear()
	for child in option_list.get_children():
		option_list.remove_child(child)
		child.queue_free()
	for option_index in _option_indices:
		var option := _interactable_object.get_interaction_option(option_index) as InteractionOption
		if option == null:
			continue
		var entry := KEY_BIND_INTERACTION_ENTRY.instantiate() as KeybindInteractionEntry
		option_list.add_child(entry)
		entry.setup(_interactable_object, option, option_index)
		entry.action_pressed.connect(_on_entry_action_pressed)
		entry.interaction_succeeded.connect(_on_entry_interaction_succeeded)
		_entries[option_index] = entry


## Where the ray is looking on the object, or INF when it is not. Objects such as ladders move their
## prompt to follow it.
func _get_focus_point() -> Vector3:
	if (
		is_instance_valid(_interaction_ray)
		and _interaction_ray.is_colliding()
		and _interaction_ray.get_focused_interactable() == _interactable_object
	):
		return _interaction_ray.get_collision_point()
	return Vector3.INF


## Sizes the selector and places the options panel next to it. Neither is moved, because both belong
## to the object: the quads are billboards, so "next to" is an offset inside each quad's own plane,
## set through the mesh. Everything is worked out in screen pixels and turned into meters with
## the size one pixel has at the object's distance.
func _update_prompt() -> void:
	if not is_instance_valid(_interactable_object) or not is_instance_valid(_prompt):
		return
	if _reveal_frames > 0:
		_reveal_frames -= 1
		return
	var camera := get_viewport().get_camera_3d()
	if not is_instance_valid(camera):
		_prompt.hide()
		return
	var camera_transform := camera.get_global_transform_interpolated()
	var anchor := _prompt.get_global_transform_interpolated().origin
	var view := camera_transform.affine_inverse() * anchor
	if view.z >= -camera.near:
		_prompt.hide()
		return
	_prompt.show()

	var screen := get_viewport().get_visible_rect().size
	_match_window_resolution(screen)
	var meters_per_pixel := _meters_per_pixel(camera, screen, -view.z)
	var anchor_pixel := screen * 0.5 + Vector2(view.x, -view.y) / meters_per_pixel

	var show_selector := _interactable_object.show_interaction_selector
	var selector_size := Vector2.ZERO
	if show_selector:
		selector_size = _selector_size(camera_transform.basis, meters_per_pixel)
		_set_quad_size(_prompt.selector, selector_size)
	_prompt.selector.visible = show_selector

	# Where the options go, in pixels from the anchor: the left edge and the vertical middle of the list.
	var list_size := option_list.size
	var left := screen_offset.x
	var middle := screen_offset.y
	if show_selector:
		left += selector_size.x * 0.5 / meters_per_pixel
	elif _interactable_object.center_prompt:
		left = -list_size.x * 0.5
		middle = 0.0
	var top_left := anchor_pixel + Vector2(left, middle - list_size.y * 0.5)
	var lowest := Vector2(
		maxf(screen_margin, screen.x - list_size.x - screen_margin),
		maxf(screen_margin, screen.y - list_size.y - screen_margin)
	)
	var kept_on_screen := top_left.clamp(Vector2.ONE * screen_margin, lowest)
	left += kept_on_screen.x - top_left.x
	middle += kept_on_screen.y - top_left.y

	# Land the panel's pixels exactly on real screen pixels. Half a pixel off, every texel is smeared
	# over two by the filtering and the text goes soft.
	var viewport_size := Vector2(sub_viewport.size) / (_pixel_scale * SUPERSAMPLE)
	var viewport_top_left := anchor_pixel + Vector2(left, middle - viewport_size.y * 0.5)
	var snap := (viewport_top_left * _pixel_scale).round() / _pixel_scale - viewport_top_left
	left += snap.x
	middle += snap.y

	# The list sits at the left edge of the viewport, centered vertically, so the quad's center is
	# half a viewport to the right of where the list starts.
	var panel := _prompt.options.mesh as QuadMesh
	panel.size = viewport_size * meters_per_pixel
	panel.center_offset = Vector3(
		(left + viewport_size.x * 0.5) * meters_per_pixel,
		-middle * meters_per_pixel,
		0.0
	)


## The window is usually not the UI's logical size (the stretch mode scales it), so the SubViewport
## is drawn at SUPERSAMPLE times the real pixel count, with the UI laid out at its logical size. One logical pixel is
## [member _pixel_scale] real ones; the quad and its snapping use that, or the text is resampled.
func _match_window_resolution(logical_screen: Vector2) -> void:
	var window := get_window()
	_pixel_scale = maxf(float(window.size.y) / maxf(logical_screen.y, 1.0), 0.01)
	var wanted := Vector2i((Vector2(_ui_size) * _pixel_scale * SUPERSAMPLE).round())
	if sub_viewport.size != wanted:
		sub_viewport.size = wanted

func _set_quad_size(quad_instance: MeshInstance3D, quad_size: Vector2) -> void:
	var quad := quad_instance.mesh as QuadMesh
	if not quad.size.is_equal_approx(quad_size):
		quad.size = quad_size

## How big the selector is in the world: the object's selector box as it looks from the camera,
## plus the padding, keeping the box's own proportions so a flat panel seen edge-on stays framed.
func _selector_size(camera_basis: Basis, meters_per_pixel: float) -> Vector2:
	var box := Vector2(
		_interactable_object.get_selector_half_extent(camera_basis.x),
		_interactable_object.get_selector_half_extent(camera_basis.y)
	) * 2.0
	var padded := box + Vector2.ONE * _interactable_object.selector_screen_padding * 2.0 * meters_per_pixel
	return _preserve_selector_aspect(padded)

func _preserve_selector_aspect(framed: Vector2) -> Vector2:
	var object_scale := _interactable_object.global_transform.basis.get_scale().abs()
	var box := _interactable_object.get_selector_half_size_local() * 2.0
	var target_width := box.x * object_scale.x
	var target_height := box.y * object_scale.y
	if target_width <= 0.0001 or target_height <= 0.0001:
		return framed
	var target_aspect := target_width / target_height
	var aspect := framed.x / maxf(framed.y, 0.0001)
	if aspect < target_aspect:
		framed.x = framed.y * target_aspect
	elif aspect > target_aspect:
		framed.y = framed.x / target_aspect
	return framed

## The size of one screen pixel, in meters, on a plane [param depth] meters in front of the camera.
func _meters_per_pixel(camera: Camera3D, screen: Vector2, depth: float) -> float:
	var span := screen.y if camera.keep_aspect == Camera3D.KEEP_HEIGHT else screen.x
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return camera.size / span
	return 2.0 * depth * tan(deg_to_rad(camera.fov) * 0.5) / span

## The dots live on the interactables. All this decides, for the player this prompter belongs to, is
## which of them may show theirs: in reach, in front of the camera, something to do with them,
## and no wall in the way (the dot is drawn over everything, so it would show through walls).
## Other players' prompters leave the dots alone, and an interaction ray that is off (sitting in a
## vehicle, say) switches them all off.
func _update_dots() -> void:
	if not is_instance_valid(_interaction_ray):
		return
	if _interaction_ray.input_requires_multiplayer_authority and not _interaction_ray.is_multiplayer_authority():
		return
	var camera := get_viewport().get_camera_3d()
	var active := dots_enabled and _interaction_ray.interaction_enabled and is_instance_valid(camera)
	var eye := camera.global_position if active else Vector3.ZERO
	var space: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state if active else null
	for node in get_tree().get_nodes_in_group(InteractableObject3D.GROUP):
		var interactable := node as InteractableObject3D
		if interactable != null:
			interactable.set_dot_allowed(active and _wants_dot(interactable, camera, eye, space))

func _wants_dot(
		interactable: InteractableObject3D,
		camera: Camera3D,
		eye: Vector3,
		space: PhysicsDirectSpaceState3D
) -> bool:
	if not interactable.show_distance_dot or not interactable.interaction_enabled:
		return false
	var point := interactable.get_dot_world_position()
	var distance := eye.distance_to(point)
	if distance >= interactable.dot_distance or camera.is_position_behind(point):
		return false
	if interactable.get_available_interaction_indices(_interaction_ray.get_interaction_source()).is_empty():
		return false
	return not _is_hidden(space, eye, point, distance)

## True when scenery or a wall stands between the eye and the point. The ray stops a little short
## of the point, because buttons sit on the surfaces they are fixed to.
func _is_hidden(space: PhysicsDirectSpaceState3D, eye: Vector3, point: Vector3, distance: float) -> bool:
	if distance < 0.5:
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, point + (eye - point).normalized() * 0.2, PhysicsLayers.SOLID)
	query.collide_with_areas = false
	return not space.intersect_ray(query).is_empty()


func _on_hold_progress_changed(
		interactable: Area3D,
		option_index: int,
		progress: float
) -> void:
	if interactable != _interactable_object:
		return
	var entry := get_entry(option_index)
	if is_instance_valid(entry):
		entry.set_hold_progress(progress)


func _on_interaction_option_succeeded(
		interactable: Area3D,
		_interactor: Node3D,
		option_index: int
) -> void:
	if interactable != _interactable_object:
		return
	var entry := get_entry(option_index)
	if is_instance_valid(entry):
		entry.notify_interaction_succeeded()


func _on_entry_action_pressed(option_index: int) -> void:
	if is_instance_valid(_interactable_object):
		entry_action_pressed.emit(_interactable_object, option_index)


func _on_entry_interaction_succeeded(option_index: int) -> void:
	if is_instance_valid(_interactable_object):
		entry_interaction_succeeded.emit(_interactable_object, option_index)


func _disconnect_interaction_ray() -> void:
	if not is_instance_valid(_interaction_ray):
		return
	if _interaction_ray.hold_progress_changed.is_connected(_on_hold_progress_changed):
		_interaction_ray.hold_progress_changed.disconnect(_on_hold_progress_changed)
	if _interaction_ray.interaction_option_succeeded.is_connected(_on_interaction_option_succeeded):
		_interaction_ray.interaction_option_succeeded.disconnect(_on_interaction_option_succeeded)
