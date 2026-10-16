class_name JumpCameraEffect
extends Node
## What the jump drive does to the view of anyone aboard the ship. While it charges the view slowly zooms in, a
## little more every second, as if the ship were gathering itself; when the jump begins the view lets go and springs
## back to normal, which feels like a burst of speed.
##
## Only the player looking from aboard (the ship's camera, or a player inside it or sitting in its seats) feels it: someone
## outside, watching the ship charge, sees a normal view. It zooms the camera the player is looking through, by
## the field of view multiplier of [BaseCamera3D], so the setting the player chose is still the field of view they
## return to. A player who steps off the ship mid-charge, or on to it, is eased out of the zoom, or into it.
##
## It reads a [JumpDirector], its parent or the first one in the [code]jump_director[/code] group, and changes nothing in it.

## The name this effect goes by on the camera.
const SOURCE: StringName = &"jump_charge"
## How often it asks whether the view is from aboard, which takes a few shape tests.
const ABOARD_CHECK_TIME := 0.1

## How much the field of view narrows by the end of the charge: 0.3 makes it 30% narrower.
@export_range(0.0, 0.7, 0.01) var zoom := 0.3
## How the zoom builds up over the charge. 1 is steadily, more is slowly at first and faster at the end.
@export_range(0.5, 4.0, 0.05) var build_up := 1.8
## How long the view takes to let go and come back once the jump begins.
@export_range(0.05, 3.0, 0.05, "suffix:s") var release_time := 0.5
@export var director: JumpDirector

var _camera: BaseCamera3D
var _multiplier := 1.0
var _aboard := false
var _aboard_wait := 0.0
var _interiors: Array[VehicleInterior3D] = []
var _interiors_ship: Node
var _interiors_looked := 0


func _ready() -> void:
	if not is_instance_valid(director):
		var parent := get_parent()
		director = parent as JumpDirector if parent is JumpDirector else null
	process_priority = 100


func _exit_tree() -> void:
	_release_camera()


func _process(delta: float) -> void:
	if not is_instance_valid(director) or not is_instance_valid(director.ship):
		_multiplier = 1.0
		_release_camera()
		return
	var camera := get_viewport().get_camera_3d() as BaseCamera3D
	if camera != _camera:
		# The player is looking through another camera now (they sat down, or got up): the old one goes back to
		# normal, and the new one takes over from the zoom the old one had, so the view does not jump.
		if is_instance_valid(_camera):
			_camera.set_field_of_view_multiplier(SOURCE, 1.0)
		_camera = camera
		_aboard_wait = 0.0
	if _camera == null:
		return
	_aboard_wait -= delta
	if _aboard_wait <= 0.0:
		_aboard_wait = ABOARD_CHECK_TIME
		_aboard = _is_aboard(_camera)

	_multiplier = _follow(_multiplier, get_target(), delta)
	_camera.set_field_of_view_multiplier(SOURCE, _multiplier)


## What the field of view should be multiplied by right now: 1 unless the drive is charging and the view is from aboard.
func get_target() -> float:
	if not _aboard or director.phase != JumpDirector.Phase.CHARGING:
		return 1.0
	return 1.0 - zoom * pow(director.get_phase_progress(), build_up)


## How much the view is zoomed at this moment (1 is not at all).
func get_multiplier() -> float:
	return _multiplier


func _is_aboard(camera: Node3D) -> bool:
	# The ship's interiors are looked for again now and then: a segment added to the ship can have one.
	if _interiors_ship != director.ship or Time.get_ticks_msec() - _interiors_looked >= 1000:
		_interiors_ship = director.ship
		_interiors_looked = Time.get_ticks_msec()
		_interiors = VehicleAboard.get_interiors(director.ship)
	return VehicleAboard.is_viewer_aboard(camera, director.ship, _interiors)


## Moves the zoom toward [param target]: closely while it builds up, which is slowly, and quickly when it is let go.
func _follow(current: float, target: float, delta: float) -> float:
	var speed := 3.0 / maxf(release_time, 0.01) if target > current else 8.0
	return lerpf(current, target, 1.0 - exp(-speed * delta))


func _release_camera() -> void:
	if is_instance_valid(_camera):
		_camera.set_field_of_view_multiplier(SOURCE, 1.0)
	_camera = null
	_multiplier = 1.0
