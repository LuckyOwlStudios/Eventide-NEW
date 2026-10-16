class_name VehicleAboard
extends RefCounted
## Whether something is aboard a vehicle: part of it, inside its interior, or (for a player) sitting in one of its
## seats. These are the questions a jump asks about who goes on with the ship, and what the vehicle's own sounds
## and the view's effects ask about who is listening and looking from inside it.
##
## "Inside" is measured from the shape of the interior (see [VehicleInterior3D.contains_point]), not from what
## the physics engine has noticed, which trails a body that was just moved (a teleport) by a step.


## The inside spaces of [param vehicle]: every [VehicleInterior3D] in it.
static func get_interiors(vehicle: Node) -> Array[VehicleInterior3D]:
	var found: Array[VehicleInterior3D] = []
	if vehicle == null:
		return found
	for node in vehicle.find_children("*", "VehicleInterior3D", true, false):
		found.append(node as VehicleInterior3D)
	return found


## Whether [param node] is the vehicle, part of it, or inside one of [param interiors] (the ones from [method get_interiors]).
static func is_inside(node: Node3D, vehicle: Node3D, interiors: Array[VehicleInterior3D]) -> bool:
	if node == vehicle or vehicle.is_ancestor_of(node):
		return true
	for interior in interiors:
		if interior.contains_point(node.global_position):
			return true
	return false


## Whether [param player] is inside the vehicle, or sitting in one of its seats.
static func is_player_aboard(player: Player, vehicle: Node3D, interiors: Array[VehicleInterior3D]) -> bool:
	var seat_controller := SeatController.find_on_actor(player)
	if seat_controller != null and is_instance_valid(seat_controller.current_seat) and vehicle.is_ancestor_of(seat_controller.current_seat):
		return true
	return is_inside(player, vehicle, interiors)


## Whether [param camera] is looking from aboard the vehicle: it is part of it (the pilot's camera rides on it), it
## is a player's who is aboard, or it is simply inside.
static func is_viewer_aboard(camera: Node3D, vehicle: Node3D, interiors: Array[VehicleInterior3D]) -> bool:
	if vehicle.is_ancestor_of(camera):
		return true
	var node := camera.get_parent()
	while node != null:
		if node is Player:
			return is_player_aboard(node as Player, vehicle, interiors)
		node = node.get_parent()
	return is_inside(camera, vehicle, interiors)
