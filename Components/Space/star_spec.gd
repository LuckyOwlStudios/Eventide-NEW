class_name StarSpec
extends RefCounted
## One star of a system, as plain numbers: which way it is, how big it looks, what color it is and how
## much light it gives. Nothing in it is a node. [StarGenerator] makes them from a system's seed, so every
## machine agrees on them, and the [StarField] turns them into something to look at and a light.
##
## A star is only ever a direction in the sky. It cannot be reached: it is drawn at the same place on the
## screen however far the ship flies, like the stars of the sky behind it. How near it is shows in how big
## it looks, and the template of the system decides how near (a big star is a near one, and a hot system).

## The star of the template this was made from, or null.
var source: Star
## How far away it is, from 0 (as near as a star can look) to 1 (as far), see [member Star.distance].
var distance := 0.42
## Which way it is, as a unit vector in the world.
var direction := Vector3.FORWARD
## Half the angle across its disc, in radians. About a tenth of a radian is a comfortable distance, ten
## times that is far too close, and a tenth of it far too far.
var angular_radius := 0.1
## The color temperature of its surface, in kelvin. Redder below 5800, bluer above. (A star with a color of its
## own in the template is a sun-like 5800.)
var kelvin := 5800.0
## The color it shines in. A natural one (see [member Star.random_color]) comes from [member kelvin] but is kept
## pale, so no star is very strongly colored.
var color := Color.WHITE
## How bright its surface is next to a sun-like star: bluer ones are brighter per bit of surface.
var brightness := 1.0
## How much more strongly the disc is drawn in its color than the light is cast in it. A natural color is kept pale (so the light is
## not strongly colored) and the disc brings it back; a color chosen in a template is shown as it is, which is 1.
var color_boost := 1.0
## How much of the system's light it gives, next to the others: how big it looks, squared, times its brightness.
var heat := 1.0
## The energy of the light it casts into the system.
var light_energy := 0.75
## How fast its surface turns, in radians a second, and where in the turn it is at the start.
var spin_speed := 0.02
var spin_phase := 0.0
## How far its axis leans, in radians. It decides which part of the star texture faces us.
var tilt := 0.0


## Half the angle across the disc, in degrees.
func get_angular_radius_degrees() -> float:
	return rad_to_deg(angular_radius)
