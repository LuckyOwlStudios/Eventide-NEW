extends Node3D
## A stand-in for the scene a system's template can bring along (a black hole, say): all it does is remember which system it
## was made for, and place itself from that. Used by the jump director test.

var system_seen: StarSystem
var setup_calls := 0
var in_tree_during_setup := true


func setup(system: StarSystem) -> void:
	system_seen = system
	setup_calls += 1
	in_tree_during_setup = is_inside_tree()
	position = Vector3(0.0, 0.0, -1500.0)
