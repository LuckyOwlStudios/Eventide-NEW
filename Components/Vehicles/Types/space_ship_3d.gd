@icon("uid://b3hdct1vl1edl")
class_name SpaceShip3D
extends MovingVehicle3D
## A Space Ship

@export_group("Movement")
## How fast the Ship moves forward relative to its movement speed
@export var forward_direction_multiplier: float = 1
## How fast the Ship moves backward relative to its movement speed
@export var backward_direction_multiplier: float = 1
## How fast the Ship moves left relative to its movement speed
@export var left_direction_multiplier: float = 1
## How fast the Ship moves right relative to its movement speed
@export var right_direction_multiplier: float = 1
## How fast the Ship moves up relative to its movement speed
@export var up_direction_multiplier: float = 1
## How fast the Ship moves down relative to its movement speed
@export var down_direction_multiplier: float = 1
