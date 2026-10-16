class_name SpaceBackdrop
extends Node3D
## A slowly drifting view of space for the menus to sit on. The camera only turns; the sky
## never moves closer, so it costs next to nothing.

## Degrees per second the view turns around the up axis.
@export_range(0.0, 5.0, 0.05, "suffix:°/s") var yaw_speed := 0.6
## How far, in degrees, the view slowly nods up and down.
@export_range(0.0, 10.0, 0.1, "suffix:°") var pitch_sway := 2.0
@export_range(1.0, 120.0, 1.0, "suffix:s") var pitch_period := 90.0

@onready var camera: Camera3D = $Camera3D

var _elapsed := 0.0

func _process(delta: float) -> void:
	_elapsed += delta
	camera.rotation_degrees = Vector3(
		sin(_elapsed * TAU / pitch_period) * pitch_sway,
		fposmod(-_elapsed * yaw_speed, 360.0),
		0.0,
	)
