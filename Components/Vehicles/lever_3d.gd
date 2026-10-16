class_name Lever3D
extends Node3D
## A wall lever: an arm that swings between an up position and a down position.
##
## This node is the hinge. Build the arm as a child that points along this node's +Y axis (a box or
## mesh standing up from the origin), and put this node where the arm meets the panel. The hinge turns
## around [member axis], in this node's rest orientation, so a lever on a wall that faces +Z swings up
## and down around X.
##
## Set [member down] and the arm swings there over [member travel_time]. Whatever uses the lever (a
## [PowerSwitch3D]) sets it, and it does nothing else.

## The arm reached the up or down position.
signal moved(is_down: bool)

## The hinge's axis, in the lever's own space as it was placed in the scene.
@export var axis := Vector3.RIGHT
## Where the arm points when the lever is up, in degrees around the axis. 0 is straight up the node's +Y.
@export_range(-180.0, 180.0, 1.0, "suffix:°") var up_angle := 45.0
## Where the arm points when the lever is down.
@export_range(-180.0, 180.0, 1.0, "suffix:°") var down_angle := 135.0
## How long the arm takes to swing from one end to the other.
@export_range(0.01, 5.0, 0.01, "suffix:s") var travel_time := 0.3
## Whether the lever is pulled down. The arm swings to the new position.
@export var down := false:
	set(value):
		if value == down:
			return
		down = value
		_swinging = true
		set_process(is_node_ready() and not Engine.is_editor_hint())

## How far along the swing the arm is: 0 is up, 1 is down.
var progress := 0.0

var _rest := Basis.IDENTITY
var _swinging := false


func _ready() -> void:
	_rest = basis
	progress = 1.0 if down else 0.0
	_apply()
	set_process(false)


func _process(delta: float) -> void:
	var target := 1.0 if down else 0.0
	progress = move_toward(progress, target, delta / travel_time)
	_apply()
	if is_equal_approx(progress, target):
		progress = target
		_apply()
		set_process(false)
		if _swinging:
			_swinging = false
			moved.emit(down)


## Puts the arm at its end position with no swing.
func snap(value: bool) -> void:
	down = value
	if not is_node_ready():
		# It places itself when it is ready.
		return
	progress = 1.0 if value else 0.0
	_swinging = false
	_apply()
	set_process(false)


func is_swinging() -> bool:
	return not is_equal_approx(progress, 1.0 if down else 0.0)


## The arm's current angle around the axis, in degrees.
func get_angle() -> float:
	# Eased, so the arm starts and ends gently.
	return lerpf(up_angle, down_angle, smoothstep(0.0, 1.0, progress))


func _apply() -> void:
	if axis.is_zero_approx():
		return
	basis = _rest * Basis(axis.normalized(), deg_to_rad(get_angle()))
