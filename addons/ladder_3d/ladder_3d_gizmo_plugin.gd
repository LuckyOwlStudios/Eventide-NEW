@tool
extends EditorNode3DGizmoPlugin
## Draws a Ladder3D in the editor: rails and rungs for its height, an arrow for the
## climb direction, an arrow for the side the climber faces, and the two landing
## points.

const RUNG_SPACING := 0.3
const MAX_RUNGS := 200
const ARROW_HEAD := 0.12


var _materials_created := false


func _init() -> void:
	_create_materials()


## Also called from _redraw: a hot-reloaded script keeps its old plugin instance,
## whose _init never ran with the current material names.
func _create_materials() -> void:
	if _materials_created:
		return
	_materials_created = true
	create_material("ladder", Color(0.3, 0.8, 1.0))
	create_material("rungs", Color(0.3, 0.8, 1.0, 0.45))
	create_material("facing", Color(1.0, 0.9, 0.2))
	create_material("top", Color(0.35, 1.0, 0.4))
	create_material("bottom", Color(1.0, 0.55, 0.2))


func _get_gizmo_name() -> String:
	return "Ladder3D"


func _has_gizmo(node: Node3D) -> bool:
	return node is Ladder3D


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	_create_materials()
	gizmo.clear()
	var ladder := gizmo.get_node_3d() as Ladder3D
	if ladder == null:
		return

	var height := ladder.height
	var half_width := ladder.width * 0.5

	# Rails and rungs.
	var frame := PackedVector3Array([
		Vector3(-half_width, 0.0, 0.0), Vector3(-half_width, height, 0.0),
		Vector3(half_width, 0.0, 0.0), Vector3(half_width, height, 0.0),
	])
	gizmo.add_lines(frame, get_material("ladder", gizmo))
	var rungs := PackedVector3Array()
	var rung_count := mini(int(height / RUNG_SPACING), MAX_RUNGS)
	var spacing := height / float(rung_count + 1) if rung_count > 0 else height
	for index in range(1, rung_count + 1):
		var y := spacing * index
		rungs.append(Vector3(-half_width, y, 0.0))
		rungs.append(Vector3(half_width, y, 0.0))
	if not rungs.is_empty():
		gizmo.add_lines(rungs, get_material("rungs", gizmo))

	# Climb direction: a spine from the base to the top, ending in an arrow.
	var spine := PackedVector3Array([Vector3.ZERO, Vector3(0.0, height, 0.0)])
	spine.append_array(_arrow_head(Vector3(0.0, height, 0.0), Vector3.UP, Vector3.RIGHT))
	gizmo.add_lines(spine, get_material("ladder", gizmo))

	# Facing: where the climber holds on and the way they look (toward the ladder).
	var hold := Vector3(0.0, height * 0.5, ladder.climb_offset)
	var facing := PackedVector3Array([hold, Vector3(0.0, hold.y, 0.0)])
	facing.append_array(_arrow_head(Vector3(0.0, hold.y, 0.0), Vector3.FORWARD, Vector3.UP))
	gizmo.add_lines(facing, get_material("facing", gizmo))

	# Dismount points.
	gizmo.add_lines(
		_dismount_marker(ladder.get_top_dismount_local_position(), Vector3(0.0, height, 0.0)),
		get_material("top", gizmo),
	)
	gizmo.add_lines(
		_dismount_marker(ladder.get_bottom_dismount_local_position(), Vector3.ZERO),
		get_material("bottom", gizmo),
	)

	# A fat selectable segment so the ladder can be picked in the viewport.
	gizmo.add_collision_segments(PackedVector3Array([Vector3.ZERO, Vector3(0.0, height, 0.0)]))


## A cross and an up tick on the landing spot, plus a link back to the ladder end
## at [param anchor]. [param origin] is relative to the ladder.
func _dismount_marker(origin: Vector3, anchor: Vector3) -> PackedVector3Array:
	return PackedVector3Array([
		anchor, origin,
		origin - Vector3.RIGHT * 0.25, origin + Vector3.RIGHT * 0.25,
		origin - Vector3.FORWARD * 0.25, origin + Vector3.FORWARD * 0.25,
		origin, origin + Vector3.UP * 0.35,
	])


## Two barbs trailing back from [param tip] along [param direction].
func _arrow_head(tip: Vector3, direction: Vector3, side: Vector3) -> PackedVector3Array:
	var back := -direction * ARROW_HEAD
	var spread := side * ARROW_HEAD * 0.6
	return PackedVector3Array([
		tip, tip + back + spread,
		tip, tip + back - spread,
	])
