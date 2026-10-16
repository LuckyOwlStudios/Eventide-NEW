class_name Asteroid3D
extends StaticBody3D
## One asteroid of a system: a fixed rock that ships and people collide with. It is made by a
## [SpaceChunk] from one of the system's [AsteroidShapes] models and thrown away with the chunk.
##
## It sits on the World layer with nothing in its mask, like scenery: it never moves and never
## looks for anything, so it costs next to nothing while the chunk it is in is loaded.

## How far from its middle the rock reaches, in meters.
var radius := 1.0
## Which of the system's models it is made from.
var model_index := 0
## What kind of asteroid it is: how it looks, and what it will drop.
var type: Asteroid
## The chunk it belongs to.
var chunk_coord := Vector3i.ZERO


func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
