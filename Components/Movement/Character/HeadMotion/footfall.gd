class_name Footfall
extends Resource
## One foot landing during a gait cycle. A [HeadBobProfile] lists these.
##
## The head dips at every footfall and the footstep sound plays at the same moment,
## which is how bobbing and stepping stay in sync.

## Where in the cycle (0 to 1) the foot lands. A walk has two, at 0 and 0.5.
@export_range(0.0, 1.0, 0.001) var phase := 0.0
## How hard the foot lands. Scales the dip in the head and the loudness of the step.
@export_range(0.0, 2.0, 0.01) var strength := 1.0
## Which foot: -1 is the left, 1 is the right, 0 is in the middle. The head sways toward it.
@export_range(-1.0, 1.0, 0.1) var side := 0.0


static func create(at_phase: float, at_strength := 1.0, on_side := 0.0) -> Footfall:
	var footfall := Footfall.new()
	footfall.phase = at_phase
	footfall.strength = at_strength
	footfall.side = on_side
	return footfall
