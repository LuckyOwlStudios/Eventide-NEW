class_name SurfaceMaterial
extends PhysicsMaterial
## A physics material that also says what stepping on it sounds like.
##
## Use it exactly where you would use a PhysicsMaterial: the Physics Material Override of
## a StaticBody3D, AnimatableBody3D or RigidBody3D. A [FootstepPlayer] looks at what the
## character is standing on and plays this sound along with the character's own.
##
## CSG shapes have no physics material slot. Give them the same thing as node metadata
## instead: in the inspector under Metadata, add an entry named [code]surface_material[/code]
## of type Object, and put a SurfaceMaterial in it. A body has one surface, so a floor
## that is partly grating and partly dirt needs to be two bodies.
##
## Ground that has no surface of its own sounds like [constant DEFAULT_PATH].

## The name of the metadata entry that gives a node (usually CSG) a surface.
const META_NAME := &"surface_material"
## The surface for ground that has none. Change what it plays by editing this resource.
const DEFAULT_PATH := "res://Components/Physics/Surfaces/DefaultSurface.tres"

## Played when a foot lands on this surface. Use an AudioStreamRandomizer for variety.
@export var step_sound: AudioStream
@export_range(-30.0, 12.0, 0.5, "suffix:dB") var step_volume_db := 0.0
@export_range(0.25, 3.0, 0.01) var step_pitch := 1.0


## The surface that ground without one falls back to.
static func get_default() -> SurfaceMaterial:
	return load(DEFAULT_PATH) as SurfaceMaterial


## The surface of whatever a ray or shape hit, or the default surface when it has none.
## Never null.
static func from_collider(collider: Object) -> SurfaceMaterial:
	var material: PhysicsMaterial
	if collider is StaticBody3D:
		material = (collider as StaticBody3D).physics_material_override
	elif collider is RigidBody3D:
		material = (collider as RigidBody3D).physics_material_override
	if material is SurfaceMaterial:
		return material as SurfaceMaterial
	if collider != null and collider.has_meta(META_NAME):
		var from_meta: Variant = collider.get_meta(META_NAME)
		if from_meta is SurfaceMaterial:
			return from_meta as SurfaceMaterial
	return get_default()
