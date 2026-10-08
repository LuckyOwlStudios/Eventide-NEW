class_name Car3D
extends MovingVehicle3D

@export_group("Handling & Feel")
## Reduces steering sharpness at high speeds so the car does not spin out too easily.
@export var turn_effluence_curve: Curve
