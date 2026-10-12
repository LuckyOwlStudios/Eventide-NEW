class_name Car3D
extends Vehicle3D

@export_group("Engine")
## Controls how fast the car accelerates (e.g., 300.0 to 1500.0 depending on mass)
@export var base_engine_power: float = 25
## Limits the maximum velocity of the car so it does not accelerate infinitely.
@export var base_max_speed: float = 100
## Sets the maximum turning angle for the wheels in radians (usually around 0.4 to 0.9).
@export var base_max_turn_angle: float = 30
## How the car accelerates overtime
@export var acceleration_curve: Curve

@export_group("Handling & Feel")
## Reduces steering sharpness at high speeds so the car does not spin out too easily.
@export var turn_effluence_curve: Curve

var engine_power := Attribute.new()
var max_speed := Attribute.new()
var max_turn_angle := Attribute.new()
