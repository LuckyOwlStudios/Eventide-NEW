@tool
class_name CharacterPositionMarker3D
extends Node3D

@export var width: float = 0.5
@export var height: float = 2

func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var offset := global_basis * Vector3.UP * (height / 2.0)

	DebugDraw3D.draw_capsule(
		global_position + offset,
		global_basis.get_rotation_quaternion(),
		width,
		height,
		Color.WHITE
	)
