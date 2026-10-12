class_name HingedDoor3D
extends Node3D
## Swings a pivot node open and closed around a hinge, optionally stopping short
## of obstacles detected by CurvedRayCast3Ds.
##
## The pivot's pose when the scene starts is the closed pose. Opening rotates it
## around [member rotation_axis] (in the pivot's parent space) through
## [member open_angle], with the hinge at the pivot's origin.
##
## Obstacles: every raycast reports how far from closed it first hits something.
## The lowest of those angles is the most the door may open. If that limit drops
## below the door's current angle the door is shoved back to it at once, as if
## pushed by the obstacle. If the limit rises, the door swings out again at
## [member rotation_speed].

signal open_requested_changed(is_open: bool)
signal fully_opened
signal fully_closed
## Emitted when an obstacle starts or stops keeping the door from opening fully.
signal blocked_changed(is_blocked: bool)

const BLOCKED_TOLERANCE := 0.01

## The node that rotates. Leave empty to rotate this node itself.
@export var pivot: Node3D
## Hinge axis in the pivot's parent space.
@export var rotation_axis := Vector3.RIGHT
## How far the door swings when fully open. The sign picks the swing direction
## around the axis.
@export_range(-180.0, 180.0, 0.5, "suffix:°") var open_angle := 90.0
## How fast the door swings when opening or closing.
@export_range(1.0, 720.0, 1.0, "suffix:°/s") var rotation_speed := 60.0
## Starts the scene already open.
@export var start_open := false
## Raycasts that limit how far the door may open. Each should sweep from the
## closed pose through the opening arc, so its collision angle is the door angle
## at which it would hit something. Add as many as you like.
@export var limit_raycasts: Array[CurvedRayCast3D]

## Whether the door has been told to be open. It may still be swinging, or held
## back by an obstacle.
var open_requested := false

var _angle := 0.0
var _closed_basis := Basis.IDENTITY
var _blocked := false


func _ready() -> void:
	if not is_instance_valid(pivot):
		pivot = self
	if rotation_axis.is_zero_approx():
		push_error("HingedDoor3D needs a non-zero rotation axis.")
		set_physics_process(false)
		return
	_closed_basis = pivot.basis
	if start_open:
		open_requested = true
		_angle = _get_maximum_angle()
		_apply_rotation()


func _physics_process(delta: float) -> void:
	var maximum := _get_maximum_angle()
	var allowed := _get_allowed_angle(maximum)
	var previous := _angle

	# Pushed in: shrinking room moves the door immediately.
	_angle = minf(_angle, allowed)
	# Everything else, including recovering from a push, moves at door speed.
	var goal := minf(maximum if open_requested else 0.0, allowed)
	_angle = move_toward(_angle, goal, rotation_speed * delta)

	_set_blocked(open_requested and allowed < maximum - BLOCKED_TOLERANCE)
	if not is_equal_approx(_angle, previous):
		_apply_rotation()
		if _angle >= maximum and previous < maximum:
			fully_opened.emit()
		elif _angle <= 0.0 and previous > 0.0:
			fully_closed.emit()


## Asks the door to open.
func open() -> void:
	set_open(true)


## Asks the door to close.
func close() -> void:
	set_open(false)


func toggle() -> void:
	set_open(not open_requested)


func set_open(value: bool) -> void:
	if open_requested == value:
		return
	open_requested = value
	open_requested_changed.emit(open_requested)


## Jumps straight to open or closed with no swing, ignoring obstacles.
func snap(_open: bool) -> void:
	set_open(_open)
	_angle = _get_maximum_angle() if _open else 0.0
	_apply_rotation()


## Current swing from closed in degrees, between 0 and the open angle's size.
func get_angle() -> float:
	return _angle


## 0 when closed, 1 when fully open.
func get_open_fraction() -> float:
	var maximum := _get_maximum_angle()
	return _angle / maximum if maximum > 0.0 else 0.0


func is_fully_open() -> bool:
	return _angle >= _get_maximum_angle() - BLOCKED_TOLERANCE


func is_fully_closed() -> bool:
	return _angle <= BLOCKED_TOLERANCE


## True while an obstacle keeps a requested-open door from opening fully.
func is_blocked() -> bool:
	return _blocked


## The largest angle the door may currently reach, after all raycast limits.
func get_allowed_angle() -> float:
	return _get_allowed_angle(_get_maximum_angle())


func _get_maximum_angle() -> float:
	return absf(open_angle)


## The lowest collision angle across every raycast that is hitting something.
func _get_allowed_angle(maximum: float) -> float:
	var allowed := maximum
	for raycast in limit_raycasts:
		if is_instance_valid(raycast) and raycast.is_colliding():
			allowed = minf(allowed, raycast.get_collision_angle())
	return allowed


func _apply_rotation() -> void:
	var swing := Basis(rotation_axis.normalized(), deg_to_rad(signf(open_angle) * _angle))
	pivot.basis = swing * _closed_basis


func _set_blocked(value: bool) -> void:
	if _blocked == value:
		return
	_blocked = value
	blocked_changed.emit(_blocked)
