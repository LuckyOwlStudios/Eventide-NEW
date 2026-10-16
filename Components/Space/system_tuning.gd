class_name SystemTuning
extends Resource
## The numbers behind how systems change as the jump count climbs: how fast the Cosmic Presence
## closes in, and how thick and how big the asteroids are. Every system is built from the world's seed, its
## jump count, one of the [SystemTemplate]s and one of these (see [StarSystem]), so tuning the game is editing
## this resource. (What kinds of system there are, and when, is in the templates.)
##
## Difficulty is a single number from 0 to 1 that rises with the jump count and levels off. Each
## "easy" and "hard" pair below is the value at difficulty 0 and at difficulty 1.

@export_group("Cosmic Presence")
## How long the presence takes to cross the whole bar, empty to full, at normal speed, in the first
## systems. (A jump takes [member jump_relief] off the bar, so the time between jumps is about that
## share of this.)
@export_range(30.0, 7200.0, 1.0, "suffix:s") var easy_fill_time := 1200.0
## ...and in the hardest systems, where it is faster.
@export_range(30.0, 7200.0, 1.0, "suffix:s") var hard_fill_time := 480.0
## How much of the bar every jump takes off: the presence is left that far behind.
@export_range(0.05, 1.0, 0.01) var jump_relief := 0.5
## Where the bar stands when a new world begins.
@export_range(0.0, 0.95, 0.01) var starting_presence := 0.0
## How full the bar must be before the presence starts to get aggressive. Aggression rises from
## nothing there to everything when the bar is full.
@export_range(0.0, 0.95, 0.01) var aggression_start := 0.35

@export_group("Difficulty")
## The jump count at which a system is half as hard as systems ever get. Smaller ramps up faster.
@export_range(1.0, 500.0, 1.0) var halfway_jump := 25.0

@export_group("Systems")
## The kind of system the very first one of a world is (it is this whatever its jump needs and weight say). A
## normal system when left empty.
@export var starting_template: SystemTemplate

@export_group("Asteroids")
## How many asteroids sit in an average chunk (a cube 500 m across) of an easy system of medium density...
@export_range(0.0, 100.0, 0.1) var easy_density := 4.0
## ...and of the hardest one. Belts hold several times the average and the voids between them almost none.
@export_range(0.0, 100.0, 0.1) var hard_density := 10.0
## How the template's density (see [member SystemTemplate.density_min]) changes that: a sparse system (density 0) has this
## share of the asteroids of a medium one (0.5), which has all of them, and a packed one (1) has this share.
@export_range(0.0, 1.0, 0.01) var sparse_density_factor := 0.25
@export_range(1.0, 5.0, 0.01) var packed_density_factor := 1.75
## The smallest asteroid there is.
@export_range(0.5, 100.0, 0.5, "suffix:m") var smallest_radius := 10.0
## The largest asteroid in an easy system...
@export_range(1.0, 240.0, 0.5, "suffix:m") var easy_largest_radius := 90.0
## ...and in the hardest one.
@export_range(1.0, 240.0, 0.5, "suffix:m") var hard_largest_radius := 180.0
## How big the belts and voids are: the distance over which the thickness of the field changes.
@export_range(200.0, 20000.0, 50.0, "suffix:m") var cluster_size := 1800.0

@export_group("Arrival")
## Nothing is built this close to where the ship arrives, so it never appears inside a rock.
@export_range(0.0, 1000.0, 5.0, "suffix:m") var arrival_clear_radius := 200.0

@export_group("Stars")
## How bright the light is in a system with a comfortable temperature (0). Hotter systems are brighter than this
## and colder ones dimmer.
@export_range(0.1, 4.0, 0.05) var temperate_light := 0.75
