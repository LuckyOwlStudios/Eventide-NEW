@tool
extends EditorNode3DGizmoPlugin

const CURVED_RAYCAST_SCRIPT := preload("res://Components/Physics/curved_raycast_3d.gd")


func _init() -> void:
	create_material("arc", Color.WHITE, false, false, true)
	get_material("arc").cull_mode = BaseMaterial3D.CULL_DISABLED


func _get_gizmo_name() -> String:
	return "CurvedRayCast3D"


func _has_gizmo(node: Node3D) -> bool:
	return node.get_script() == CURVED_RAYCAST_SCRIPT


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var curved_ray := gizmo.get_node_3d()
	if curved_ray == null:
		return

	var arc_points: PackedVector3Array = curved_ray.call("get_arc_points")
	if arc_points.is_empty():
		return
	var lines := PackedVector3Array()
	lines.append(Vector3.ZERO)
	lines.append(arc_points[0])
	for index in range(arc_points.size() - 1):
		lines.append(arc_points[index])
		lines.append(arc_points[index + 1])
	_append_arrowhead(
		lines,
		arc_points,
		float(curved_ray.get("radius")),
		int(curved_ray.get("debug_shape_thickness")),
	)

	var color := curved_ray.get("debug_shape_custom_color") as Color
	if not bool(curved_ray.get("enabled")):
		color.a *= 0.35
	var thickness := int(curved_ray.get("debug_shape_thickness"))
	var radius := float(curved_ray.get("radius"))
	var ribbon_width := clampf(radius * 0.004, 0.006, 0.05) * float(thickness)
	var debug_mesh := _build_line_box_mesh(lines, ribbon_width, color)
	if debug_mesh.get_surface_count() > 0:
		gizmo.add_mesh(debug_mesh, get_material("arc", gizmo))
	gizmo.add_collision_segments(lines)


func _append_arrowhead(
	lines: PackedVector3Array,
	arc_points: PackedVector3Array,
	radius: float,
	thickness: int,
) -> void:
	if arc_points.size() < 2:
		return
	var tip := arc_points[arc_points.size() - 1]
	var tangent := (tip - arc_points[arc_points.size() - 2]).normalized()
	if tangent.is_zero_approx():
		return
	var side := Vector3.UP.cross(tangent).normalized()
	var arrow_size := clampf(radius * 0.12, 0.08, 0.5) * (1.0 + float(thickness - 1) * 0.08)
	var arrow_back := tip - tangent * arrow_size
	lines.append(tip)
	lines.append(arrow_back + side * arrow_size * 0.55)
	lines.append(tip)
	lines.append(arrow_back - side * arrow_size * 0.55)


func _build_line_box_mesh(
	lines: PackedVector3Array,
	width: float,
	color: Color,
) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var half_width := maxf(width, 0.001) * 0.5
	for line_index in range(0, lines.size() - 1, 2):
		var from := lines[line_index]
		var to := lines[line_index + 1]
		var direction := (to - from).normalized()
		if direction.is_zero_approx():
			continue
		var side := Vector3.UP.cross(direction).normalized() * half_width
		if side.is_zero_approx():
			continue
		var up := direction.cross(side).normalized() * half_width
		var vertex_start := vertices.size()
		vertices.append(from - side - up)
		vertices.append(from + side - up)
		vertices.append(from + side + up)
		vertices.append(from - side + up)
		vertices.append(to - side - up)
		vertices.append(to + side - up)
		vertices.append(to + side + up)
		vertices.append(to - side + up)
		for unused_index in 8:
			colors.append(color)
		_append_quad(indices, vertex_start, vertex_start + 1, vertex_start + 2, vertex_start + 3)
		_append_quad(indices, vertex_start + 4, vertex_start + 7, vertex_start + 6, vertex_start + 5)
		_append_quad(indices, vertex_start, vertex_start + 4, vertex_start + 5, vertex_start + 1)
		_append_quad(indices, vertex_start + 1, vertex_start + 5, vertex_start + 6, vertex_start + 2)
		_append_quad(indices, vertex_start + 2, vertex_start + 6, vertex_start + 7, vertex_start + 3)
		_append_quad(indices, vertex_start + 3, vertex_start + 7, vertex_start + 4, vertex_start)

	var mesh := ArrayMesh.new()
	if vertices.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _append_quad(
	indices: PackedInt32Array,
	a: int,
	b: int,
	c: int,
	d: int,
) -> void:
	indices.append(a)
	indices.append(b)
	indices.append(c)
	indices.append(a)
	indices.append(c)
	indices.append(d)
