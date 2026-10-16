class_name AsteroidDecorator
extends Resource
## Something that grows out of an asteroid: ice crystals, purple crystals, spikes, moss. It is a scene (its
## [member scene]) and how to stick it on: how many, how big, how far they lean.
##
## [b]The scene.[/b] Build it pointing up (+Y) with its base at the origin and about one meter tall. Only its
## [MeshInstance3D]s count (the root's own too), with whatever materials they have; lights, scripts and
## everything else are ignored. A decoration is not a node on the asteroid: the pieces are baked into the
## asteroid model's mesh (and, with [member collide], its collision shape) when the system is made, so a field
## of a thousand decorated rocks costs no more than a thousand plain ones. That also means every asteroid built
## from the same model has the same pieces in the same places.
##
## [b]Where it goes.[/b] On each asteroid there are [member clusters_min] to [member clusters_max] spots on the
## surface, picked at random, and at every spot [member pieces_min] to [member pieces_max] pieces grow, leaning
## away from each other.

## The scene to stick on. See above for how to build it.
@export var scene: PackedScene:
	set(value):
		scene = value
		_parts_made = false
		_parts.clear()

@export_group("How many")
## How many spots on an asteroid, fewest and most.
@export_range(0, 100, 1) var clusters_min := 6
@export_range(0, 100, 1) var clusters_max := 11
## How many pieces grow at each spot, fewest and most.
@export_range(1, 20, 1) var pieces_min := 1
@export_range(1, 20, 1) var pieces_max := 4

@export_group("Size and angle")
## How tall a piece is next to the asteroid's radius (the scene counts as 1), smallest and biggest. 0.3 sticks out
## a third of the way across the rock.
@export_range(0.01, 2.0, 0.01) var size_min := 0.16
@export_range(0.01, 2.0, 0.01) var size_max := 0.38
## How much the width varies from piece to piece, from 0 (all the scene's own proportions) to 1.
@export_range(0.0, 1.0, 0.01) var thickness_variation := 0.25
## How far a piece leans from straight out of the surface. 0 is straight out; the pieces after the first at a
## spot lean further.
@export_range(0.0, 2.0, 0.01) var lean := 0.3
## How deep the base is buried, as a share of the piece's height, so it looks grown and not set down.
@export_range(0.0, 1.0, 0.01) var sink := 0.1

@export_group("Shape")
## Gives every face its own flat shading however the scene's meshes are shaded, which is what crystals look like.
@export var flat_shaded := false
## Whether ships and people bump into it (it is built into the asteroid's collision shape) or pass through.
@export var collide := true


## One mesh surface of the scene, as plain triangles.
class Part:
	extends RefCounted
	## Where the mesh sits in the scene, relative to its root.
	var transform := Transform3D.IDENTITY
	var material: Material
	## Three corners to a triangle, wound the way Godot draws them (clockwise).
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()

var _parts: Array[Part] = []
var _parts_made := false


## The meshes of the scene as plain triangles (once, then kept). Empty without a scene, or when the meshes
## cannot be read, which is the case for an imported mesh in a headless run (nothing is drawn there).
func get_parts() -> Array[Part]:
	if not _parts_made:
		_parts_made = true
		_read_scene()
	return _parts


func has_parts() -> bool:
	return not get_parts().is_empty()


func _read_scene() -> void:
	_parts.clear()
	if scene == null:
		return
	var root := scene.instantiate()
	if root == null:
		return
	var instances: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		instances.append(root as MeshInstance3D)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		instances.append(node as MeshInstance3D)
	for instance in instances:
		if instance.mesh == null:
			continue
		var placed := _get_transform_within(instance, root)
		for surface in instance.mesh.get_surface_count():
			var part := _read_surface(instance, surface)
			if part != null:
				part.transform = placed
				_parts.append(part)
	root.free()


## How [param node] sits in the scene whose root is [param root] (the root's own transform included).
func _get_transform_within(node: Node, root: Node) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current := node
	while current != null:
		if current is Node3D:
			result = (current as Node3D).transform * result
		if current == root:
			break
		current = current.get_parent()
	return result


func _read_surface(instance: MeshInstance3D, surface: int) -> Part:
	var mesh := instance.mesh
	if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
		return null
	var arrays := mesh.surface_get_arrays(surface)
	if arrays.size() <= Mesh.ARRAY_INDEX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
		return null
	var source: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if source.size() < 3:
		return null
	var source_normals := PackedVector3Array()
	if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
		source_normals = arrays[Mesh.ARRAY_NORMAL]
	var source_uvs := PackedVector2Array()
	if arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array:
		source_uvs = arrays[Mesh.ARRAY_TEX_UV]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
		indices = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		indices.resize(source.size())
		for index in source.size():
			indices[index] = index
	if indices.size() % 3 != 0:
		return null
	for index in indices:
		if index < 0 or index >= source.size():
			return null

	var part := Part.new()
	part.material = instance.get_active_material(surface)
	part.vertices.resize(indices.size())
	part.normals.resize(indices.size())
	part.uvs.resize(indices.size())
	for corner in indices.size():
		var index := indices[corner]
		part.vertices[corner] = source[index]
		part.normals[corner] = source_normals[index] if index < source_normals.size() else Vector3.UP
		part.uvs[corner] = source_uvs[index] if index < source_uvs.size() else Vector2.ZERO
	return part
