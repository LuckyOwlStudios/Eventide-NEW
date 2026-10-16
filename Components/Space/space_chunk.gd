class_name SpaceChunk
extends Node3D
## The asteroids of one chunk of space, as nodes. A [ChunkStreamer] makes one when a chunk comes into
## range and frees it when the chunk is left behind, so nothing out of range costs anything.
##
## Each asteroid fades in and out by distance, with the engine's visibility range: it is fully
## drawn up to [code]fade_end - fade_margin[/code] from the camera and gone beyond
## [code]fade_end + fade_margin[/code], dithered in between. The streamer only loads chunks beyond
## that, so a rock is always invisible when it is made and when it is dropped, and never pops.

## Which chunk this is.
var coord := Vector3i.ZERO
var asteroid_count := 0


func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Fills the chunk with the asteroids of [param specs] (see [ChunkGenerator]), made from [param shapes].
func build(specs: Array[ChunkGenerator.Spec], shapes: AsteroidShapes, fade_end: float, fade_margin: float) -> void:
	for spec in specs:
		var model := shapes.get_model(spec.model)
		var asteroid := Asteroid3D.new()
		asteroid.radius = spec.radius
		asteroid.model_index = spec.model
		asteroid.type = model.asteroid
		asteroid.chunk_coord = coord
		asteroid.transform = Transform3D(spec.basis, spec.position)
		asteroid.collision_layer = PhysicsLayers.WORLD
		asteroid.collision_mask = 0

		# The size goes on the shape and the mesh, not on the body, which physics cannot scale.
		var collision := CollisionShape3D.new()
		collision.shape = model.collision
		collision.scale = Vector3.ONE * spec.radius
		asteroid.add_child(collision)

		var visual := MeshInstance3D.new()
		visual.mesh = model.mesh
		visual.scale = Vector3.ONE * spec.radius
		apply_fade(visual, fade_end, fade_margin)
		asteroid.add_child(visual)
		add_child(asteroid)
	asteroid_count = specs.size()


## Makes [param visual] fade out with distance (see [method ChunkStreamer.get_fade_distances]).
## Anything else a chunk holds later (loot, wrecks) should use this too, so it fades the same way.
static func apply_fade(visual: GeometryInstance3D, fade_end: float, fade_margin: float) -> void:
	visual.visibility_range_end = fade_end
	visual.visibility_range_end_margin = fade_margin
	visual.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
