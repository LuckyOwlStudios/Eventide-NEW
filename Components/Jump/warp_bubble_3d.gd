class_name WarpBubble3D
extends Node3D
## The oval of warping energy that wraps the ship while it jumps, so nobody sees the space around it
## being thrown away and built again. It is opaque: while it is whole, everything behind it is hidden.
## From inside it is a tunnel of light streaming past; from outside, a glowing shell around the ship.
##
## It is a child of the ship, so it follows it. Two numbers drive it, and the [JumpDirector] sets them
## every frame: [member progress] is how much of the skin exists (0 none, 1 all of it, burning in from
## scattered points) and [member expansion] is how far it has swelled past its resting size, which is
## how it blows away when the jump is over. [method attach_to] sizes it to a ship.

const SHADER := preload("res://Assets/Shaders/warp_bubble.gdshader")
## However small the ship, the bubble must hold the camera that rides behind it and anyone working
## close by.
const MINIMUM_RADII := Vector3(26.0, 22.0, 40.0)

## How far from the ship's middle the oval reaches along each of its axes, in meters.
@export var radii := MINIMUM_RADII:
	set(value):
		radii = value.max(Vector3.ONE)
		_apply()
## How much of the skin exists, from 0 to 1.
@export_range(0.0, 1.0, 0.001) var progress := 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		_apply()
## How far it has swelled, from 0 (its size) to 1 ([member burst_scale] times it).
@export_range(0.0, 1.0, 0.001) var expansion := 0.0:
	set(value):
		expansion = clampf(value, 0.0, 1.0)
		_apply()
## How much bigger than its resting size it is at full [member expansion].
@export_range(1.0, 5.0, 0.05) var burst_scale := 2.0
## How small it starts, as a share of its resting size, when it begins to form.
@export_range(0.0, 1.0, 0.01) var start_scale := 0.3

var _mesh: MeshInstance3D
var _material: ShaderMaterial


func _init() -> void:
	# Its scale is set every frame by whoever drives it; there is nothing to smooth.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	_build()


func _ready() -> void:
	_apply()


## True while any of the skin exists, which is when it is drawn.
func is_visible_now() -> bool:
	return progress > 0.0


## Makes it a child of [param ship], centered on it and big enough to hold it and the camera that
## follows it. The oval's long axis is the ship's own forward axis (z).
func attach_to(ship: Node3D) -> void:
	if get_parent() != ship:
		if get_parent() != null:
			get_parent().remove_child(self)
		ship.add_child(self)
	fit_to(ship)


## Centers it on the ship's hull and sizes it, at least [constant MINIMUM_RADII].
func fit_to(ship: Node3D) -> void:
	var low := Vector3(1.0e9, 1.0e9, 1.0e9)
	var high := Vector3(-1.0e9, -1.0e9, -1.0e9)
	for child in ship.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null or shape_node.shape == null:
			continue
		var half := _half_extents(shape_node.shape)
		for corner in 8:
			var corner_sign := Vector3(1 if corner & 1 else -1, 1 if corner & 2 else -1, 1 if corner & 4 else -1)
			var point := shape_node.transform * (half * corner_sign)
			low = low.min(point)
			high = high.max(point)
	if low.x > high.x:
		position = Vector3.ZERO
		radii = MINIMUM_RADII
		return
	position = (low + high) * 0.5
	var half := (high - low) * 0.5
	radii = Vector3(maxf(half.x * 2.5, MINIMUM_RADII.x), maxf(half.y * 3.0, MINIMUM_RADII.y), maxf(half.z * 2.0, MINIMUM_RADII.z))


## Sets both numbers at once.
func set_state(new_progress: float, new_expansion := 0.0) -> void:
	if is_equal_approx(progress, clampf(new_progress, 0.0, 1.0)) and is_equal_approx(expansion, clampf(new_expansion, 0.0, 1.0)):
		return
	progress = new_progress
	expansion = new_expansion


## Half the size of the box around [param shape], centered on the shape's own origin.
static func _half_extents(shape: Shape3D) -> Vector3:
	if shape is BoxShape3D:
		return (shape as BoxShape3D).size * 0.5
	if shape is SphereShape3D:
		return Vector3.ONE * (shape as SphereShape3D).radius
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		return Vector3(capsule.radius, capsule.height * 0.5, capsule.radius)
	if shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		return Vector3(cylinder.radius, cylinder.height * 0.5, cylinder.radius)
	var box := shape.get_debug_mesh().get_aabb()
	return box.size * 0.5 + box.get_center().abs()


func _build() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "Skin"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	_mesh.mesh = sphere
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_mesh.material_override = _material
	# The skin is a light of its own: it must not shade the ship inside it, or be shaded by the sun.
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_mesh.visible = false
	add_child(_mesh, false, Node.INTERNAL_MODE_FRONT)


func _apply() -> void:
	if _mesh == null:
		return
	_mesh.visible = progress > 0.0
	# Forming, it swells from a small oval (the same one, so it keeps its shape) up to its size, fast at first.
	var forming := lerpf(start_scale, 1.0, 1.0 - pow(1.0 - progress, 2.2))
	var size := forming * lerpf(1.0, burst_scale, expansion)
	_mesh.scale = radii * size
	_material.set_shader_parameter("progress", progress)
