class_name JumpPurge
extends RefCounted
## The rule for what a jump takes with it and what it leaves behind: the main ship, and everything
## inside it, goes on to the next system. Everything outside it is deleted, because the space around
## the ship is made new.
##
## [b]Stays:[/b] the ship and anything fastened to it; everything inside the ship's interior (see
## [VehicleInterior3D]): crew, loose items, cars; every player, and so whatever they carry or hold
## (players are never deleted: one left outside is brought aboard, see [method recall_players]); and
## anything in the [code]jump_keep[/code] group.
##
## [b]Goes:[/b] loose items ([ItemActor]s in the world, and any body on the Items layer), vehicles and
## turrets, creatures (every character that is not a player), and anything in the [code]jump_purge[/code]
## group, such as a bit of scenery that belongs to the system. A thing that would go but is inside the
## ship stays.
##
## Asteroids are not handled here: they belong to the [ChunkStreamer], which drops them all when the
## new system begins.

## Put a node in this group to have it deleted by a jump (when it is outside the ship).
const PURGE_GROUP: StringName = &"jump_purge"
## Put a node in this group to make a jump leave it alone, wherever it is.
const KEEP_GROUP: StringName = &"jump_keep"
## A marker in the ship's own tree in this group says where people recalled to the ship are put.
const RECALL_POINT_GROUP: StringName = &"ship_recall"
## People brought aboard stand this far apart.
const RECALL_SPACING := 1.1
## The size of a person, for finding room to put one.
const RECALL_RADIUS := 0.4
const RECALL_HEIGHT := 1.8
## What stands in the way of a person: scenery, vehicles and the walls and furniture of ships.
const RECALL_MASK := PhysicsLayers.WORLD | PhysicsLayers.VEHICLES | PhysicsLayers.VEHICLE_INTERIORS


## The inside spaces of [param ship]: every [VehicleInterior3D] in it.
static func get_interiors(ship: Node) -> Array[VehicleInterior3D]:
	return VehicleAboard.get_interiors(ship)


## Whether a jump leaves [param node] where it is, with the ship, rather than deleting it.
static func stays(node: Node, ship: Node3D, interiors: Array[VehicleInterior3D]) -> bool:
	if _stays_by_itself(node, ship, interiors):
		return true
	# Fastened to something that stays: held by a player, or part of a car that is inside the ship.
	var current := node.get_parent()
	while current != null:
		if current == ship or current is Player or current.is_in_group(KEEP_GROUP):
			return true
		if is_purgeable(current) and _stays_by_itself(current, ship, interiors):
			return true
		current = current.get_parent()
	return false


## Whether [param node] is one of the things a jump deletes when it is outside the ship.
static func is_purgeable(node: Node) -> bool:
	return _category(node) != ""


## Deletes everything outside the ship under [param root]. [param skip] is a subtree that is not
## looked at (the streamer's, which holds thousands of asteroids and has its own way of clearing them).
## Returns how many of each kind went: [code]items[/code], [code]vehicles[/code], [code]creatures[/code],
## [code]scenery[/code] (the things tagged for it), and [code]removed[/code], the nodes themselves.
static func purge(root: Node, ship: Node3D, skip: Node = null) -> Dictionary:
	var interiors := get_interiors(ship)
	var removed: Array[Node] = []
	var report := {"items": 0, "vehicles": 0, "creatures": 0, "scenery": 0, "removed": removed}
	var doomed: Array[Node] = []
	_collect(root, ship, skip, doomed)
	for node in _nodes_in_purge_group(root):
		if not doomed.has(node):
			doomed.append(node)
	for node in doomed:
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if stays(node, ship, interiors):
			continue
		match _category(node):
			"item":
				report["items"] += 1
			"vehicle":
				report["vehicles"] += 1
			"creature":
				report["creatures"] += 1
			_:
				report["scenery"] += 1
		removed.append(node)
		node.queue_free()
	return report


## Every player under [param root].
static func find_players(root: Node) -> Array[Player]:
	var found: Array[Player] = []
	for node in root.find_children("*", "Player", true, false):
		found.append(node as Player)
	return found


## Whether [param player] goes on with the ship: they are inside it, or sitting in one of its seats.
static func is_aboard(player: Player, ship: Node3D, interiors: Array[VehicleInterior3D]) -> bool:
	return VehicleAboard.is_player_aboard(player, ship, interiors)


## Brings every player who is not aboard onto the ship, standing in the hold (or around a marker in
## the group [constant RECALL_POINT_GROUP], if the ship has one), and returns who was brought.
## [param velocity] is their velocity in the world once there, for a ship that has no interior to put
## them at rest in (inside one, they arrive at rest in the ship whatever this says). Someone sitting in
## a seat that is not part of the ship is moved like anyone else, which does not get them out of the seat.
static func recall_players(root: Node, ship: Node3D, velocity := Vector3.ZERO) -> Array[Player]:
	var interiors := get_interiors(ship)
	var brought: Array[Player] = []
	var stranded: Array[Player] = []
	for player in find_players(root):
		if not is_aboard(player, ship, interiors):
			stranded.append(player)
	var places := get_recall_transforms(ship, interiors, stranded.size())
	for index in stranded.size():
		var player := stranded[index]
		var controller := _find_controller(player)
		if controller != null:
			controller.teleport(places[index], velocity)
		else:
			player.global_transform = places[index]
		# The ship carries what is in it, so it must know straight away, or a moving ship leaves them behind.
		for interior in interiors:
			if interior.contains_point(player.global_position):
				interior.admit(player)
				break
		brought.append(player)
	return brought


## [param count] places to stand on the ship, in the world, upright in the ship. With a marker in the
## group [constant RECALL_POINT_GROUP] they are in a row around it. Without one the hold is searched
## for floor with room for a person to stand, starting from the middle, so a bulkhead or a crate in
## the way is skipped. If the ship has no hold the places are at its origin.
static func get_recall_transforms(ship: Node3D, interiors: Array[VehicleInterior3D], count: int) -> Array[Transform3D]:
	var places: Array[Transform3D] = []
	if count <= 0:
		return places
	var marker: Node3D
	if ship.is_inside_tree():
		for node in ship.get_tree().get_nodes_in_group(RECALL_POINT_GROUP):
			if ship.is_ancestor_of(node) and node is Node3D:
				marker = node as Node3D
				break
	if marker != null:
		var around := Transform3D(marker.global_basis.orthonormalized(), marker.global_position)
		for index in count:
			places.append(around * Transform3D(Basis.IDENTITY, Vector3.RIGHT * RECALL_SPACING * _alternating_step(index)))
		return places
	if not interiors.is_empty():
		places = _find_clear_spots(ship, interiors[0], count)
	# Whatever could not be found goes in a row at the ship's origin, which is better than nowhere.
	var fallback := Transform3D(ship.global_basis.orthonormalized(), ship.global_position)
	while places.size() < count:
		places.append(fallback * Transform3D(Basis.IDENTITY, Vector3.BACK * RECALL_SPACING * _alternating_step(places.size())))
	return places


# --- Details ----------------------------------------------------------------------

## 0, 1, -1, 2, -2 ...: how many places along from the middle the n-th person goes.
static func _alternating_step(index: int) -> int:
	return int((index + 1) * 0.5) * (1 if index % 2 == 1 else -1)


## Floor in the hold with room to stand on, found by shooting a ray at the floor and asking whether a
## person-sized capsule fits there, at spots along the hold from its middle outward.
static func _find_clear_spots(ship: Node3D, interior: VehicleInterior3D, count: int) -> Array[Transform3D]:
	var found: Array[Transform3D] = []
	var box_node: CollisionShape3D
	for child in interior.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
			box_node = child as CollisionShape3D
			break
	if box_node == null or not ship.is_inside_tree():
		return found
	var half := (box_node.shape as BoxShape3D).size * 0.5
	var frame := Transform3D(interior.global_basis.orthonormalized(), interior.global_position)
	var middle := box_node.position
	var capsule := CapsuleShape3D.new()
	capsule.radius = RECALL_RADIUS
	capsule.height = RECALL_HEIGHT
	var space := ship.get_world_3d().direct_space_state

	# Where to try: along the hold from the middle outward, in the middle then to each side.
	var candidates: Array[Vector3] = []
	var rows := int((half.z - RECALL_RADIUS) / RECALL_SPACING)
	for row in range(rows * 2 + 1):
		var along := _alternating_step(row) * RECALL_SPACING
		for across in [0.0, -RECALL_SPACING, RECALL_SPACING]:
			if absf(across) <= half.x - RECALL_RADIUS:
				candidates.append(Vector3(middle.x + across, middle.y, middle.z + along))
	for candidate in candidates:
		if found.size() >= count:
			break
		var from := frame * Vector3(candidate.x, middle.y + half.y - 0.1, candidate.z)
		var to := frame * Vector3(candidate.x, middle.y - half.y - 0.5, candidate.z)
		var ray := PhysicsRayQueryParameters3D.create(from, to, RECALL_MASK)
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			continue
		var feet: Vector3 = (hit["position"] as Vector3) + frame.basis.y * 0.05
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(frame.basis, feet + frame.basis.y * (RECALL_HEIGHT * 0.5 + 0.03))
		query.collision_mask = RECALL_MASK
		if not space.intersect_shape(query, 1).is_empty():
			continue
		found.append(Transform3D(frame.basis, feet))
	return found


static func _nodes_in_purge_group(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	var tree := root.get_tree()
	if tree == null:
		return found
	for node in tree.get_nodes_in_group(PURGE_GROUP):
		if root == node or root.is_ancestor_of(node):
			found.append(node)
	return found


static func _collect(node: Node, ship: Node3D, skip: Node, out: Array[Node]) -> void:
	for child in node.get_children():
		if child == skip or child == ship or child is Player or child.is_in_group(KEEP_GROUP):
			continue
		if is_purgeable(child):
			out.append(child)
			continue
		_collect(child, ship, skip, out)


## What [param node] is, as far as a jump is concerned: "item", "vehicle", "creature", "scenery" or "" for none of them.
static func _category(node: Node) -> String:
	if node is Player or node.is_in_group(KEEP_GROUP):
		return ""
	if node.is_in_group(PURGE_GROUP):
		return "scenery"
	if node is ItemActor:
		return "item" if (node as ItemActor).is_in_world() else ""
	# A vehicle, or anything else that can be driven, such as a turret.
	if node is Node3D and node.has_method("claim_control"):
		return "vehicle"
	if node is BaseCharacter3D:
		return "creature"
	if node is RigidBody3D and (node as RigidBody3D).collision_layer & PhysicsLayers.ITEMS != 0:
		return "item"
	return ""


static func _stays_by_itself(node: Node, ship: Node3D, interiors: Array[VehicleInterior3D]) -> bool:
	if node == ship or node is Player or node.is_in_group(KEEP_GROUP):
		return true
	var spatial := node as Node3D
	return spatial != null and _inside_ship(spatial, ship, interiors)


## Measured from the interior's shapes, not from what the physics engine has noticed, which trails a
## body that was just moved (a teleport) by a step.
static func _inside_ship(node: Node3D, ship: Node3D, interiors: Array[VehicleInterior3D]) -> bool:
	return VehicleAboard.is_inside(node, ship, interiors)


static func _find_controller(player: Player) -> CharacterController:
	for node in player.find_children("*", "CharacterController", true, false):
		return node as CharacterController
	return null
