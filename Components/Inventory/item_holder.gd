## Holds one inventory item at a time in a character's hand, drops it and picks items up. Items that
## are on the body and not in hand keep their carried parts running.
##
## The held item is an [ItemActor] sitting in a mount: [member actor_parent] when seen through the
## holder's own eyes, [member third_person_parent] when seen by everyone else. The actor reads its own
## input (see ItemActor), so this class never forwards a use or an action to it. What it does read are
## the keys that are about the holder and not the item (the number keys and drop), and only on the
## machine of the player the holder belongs to.
##
## An item in a container that is [constant InventoryContainer.Carrying.CARRIED] or READY, and not in
## hand, has a second actor: a carried one in [member carried_parent], holding only the parts the item
## made for it (the flashlight's beam). Put the item in hand and it is swapped for the held one; put it
## away and the carried one is back. The item's state is in its ItemInstance, so nothing is lost, and
## a lit flashlight stays lit all the way through. The holder gives the actors in READY containers their
## carried input, and only the ones in READY containers.
class_name ItemHolder
extends Node

signal item_equipped(instance: ItemInstance, actor: ItemActor)
signal item_unequipped(instance: ItemInstance)
signal item_dropped(instance: ItemInstance, actor: ItemActor)
signal item_picked_up(instance: ItemInstance)

enum View {
	## First person for the player at this machine, third person for everyone else.
	AUTO,
	FIRST_PERSON,
	THIRD_PERSON,
}

## Inventory whose items this holder is allowed to equip.
@export var inventory: Inventory
## The slot container whose slots the number keys pick from. Slot 1 answers to the input action
## inventory_slot_1, and so on for as many of those actions as the project defines.
@export var hotbar_id: StringName = &"hotbar"
## Where the equipped item sits as seen through the holder's own eyes: a mount on the camera.
@export var actor_parent: Node3D
## Where it sits as seen by everyone else: a mount on the character, aimed the way the head is. Put it
## where [member actor_parent] is, measured from the head, and a light carried by the item shines from
## the same place for the holder and for everybody who watches them.
@export var third_person_parent: Node3D
## Where items sit while they are carried and not in hand: a mount on the head, so a worn light shines
## from the same place on every machine, the way [member third_person_parent] does. Leave it empty and
## carried items have no actors.
@export var carried_parent: Node3D
## Which view the held item is made for. Auto picks by whose player this is.
@export var view := View.AUTO
## While this is sitting in a seat, the held item takes no input (a primary action fires the turret).
@export var seat_controller: SeatController
## While this is on a ladder, items are put out of reach: no input, and the one in hand is hidden.
@export var ladder_controller: LadderController

@export_group("Dropping")
## The Input Map action that drops the item in hand.
@export var drop_action: StringName = &"drop_item"
## Where dropped items go. Empty finds the gameplay scene the holder is in.
@export var drop_parent: Node
## How fast the item is thrown forward, on top of how fast the holder is moving.
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var drop_speed := 2.5
## How far from a wall a dropped item appears when the holder faces it.
@export_range(0.0, 1.0, 0.01, "suffix:m") var drop_clearance := 0.15
## After dropping, when the hand is empty, takes the next hotbar slot that has an item in it (wrapping round).
@export var equip_next_on_drop := true

@export_group("Picking Up")
## Takes a picked up item in hand when the hand is empty and the item went to the hotbar.
@export var equip_on_pickup := true

@export_group("Walls")
## Pulls the item back toward the holder while something is in front of it, so it does not poke
## into a wall and shine its light from inside it.
@export var avoid_walls := true
@export_flags_3d_physics var wall_mask: int = PhysicsLayers.SOLID
## The most it is pulled back.
@export_range(0.0, 1.0, 0.01, "suffix:m") var max_pull_back := 0.5
## How quickly it moves back, and forward again.
@export_range(1.0, 60.0, 0.5) var pull_back_speed := 16.0
## Space kept between the front of the item and the wall.
@export_range(0.0, 0.3, 0.005, "suffix:m") var wall_margin := 0.04

## Add a blocker to stop the held item taking input and the keys of this holder, such as while stunned.
var can_use_items := ActionBlocker.new()
var equipped_instance: ItemInstance
var equipped_actor: ItemActor

var _slot_actions: Array[StringName] = []
var _has_drop_action := false
var _mount_rests: Dictionary[Node3D, Vector3] = {}
var _pull := 0.0
var _pull_target := 0.0
## The carried actor of each carried item, and whether that item hears its carried input.
var _carried: Dictionary[ItemInstance, ItemActor] = {}
var _carried_listens: Dictionary[ItemInstance, bool] = {}
## Carried actors that were let go of this frame, by item.
var _departed: Dictionary[ItemInstance, ItemActor] = {}
## For the local player, a copy of the item in hand on their character, drawn as nothing but a shadow.
var _shadow_actor: ItemActor


func _ready() -> void:
	var number := 1
	while InputMap.has_action(StringName("inventory_slot_%d" % number)):
		_slot_actions.append(StringName("inventory_slot_%d" % number))
		number += 1
	_has_drop_action = InputMap.has_action(drop_action)
	if inventory == null:
		push_warning("[ItemHolder] Inventory is not assigned.")
	else:
		if get_hotbar() == null:
			push_warning("[ItemHolder] The inventory has no slot container named '%s'." % hotbar_id)
		if not inventory.item_removed.is_connected(_on_inventory_item_removed):
			inventory.item_removed.connect(_on_inventory_item_removed)
		if not inventory.changed.is_connected(_sync_carried):
			inventory.changed.connect(_sync_carried)
		if carried_parent == null and _has_carrying_container():
			push_warning("[ItemHolder] The inventory carries items, but Carried Parent is not assigned.")
		# What the inventory started with, once everything is in the tree.
		_sync_carried.call_deferred()
	if actor_parent == null:
		push_warning("[ItemHolder] Actor parent is not assigned.")
	else:
		_mount_rests[actor_parent] = actor_parent.position
	if third_person_parent != null:
		_mount_rests[third_person_parent] = third_person_parent.position


func _unhandled_input(event: InputEvent) -> void:
	# Every player on the machine has one of these, and only the player at it may react.
	if not is_local() or not is_input_allowed():
		return
	if _has_drop_action and event.is_action_pressed(drop_action):
		get_viewport().set_input_as_handled()
		drop_equipped_item()
		return
	var hotbar := get_hotbar()
	if hotbar != null:
		for slot_index in mini(_slot_actions.size(), hotbar.size):
			if event.is_action_pressed(_slot_actions[slot_index]):
				get_viewport().set_input_as_handled()
				toggle_inventory_slot(slot_index)
				return
	_send_carried_input(event)


func _physics_process(_delta: float) -> void:
	_pull_target = _measure_wall_pull()


func _process(delta: float) -> void:
	if has_equipped_item():
		equipped_actor.visible = not are_items_hidden()
		if is_instance_valid(_shadow_actor):
			_shadow_actor.visible = equipped_actor.visible
	if _pull == 0.0 and not has_equipped_item():
		return
	var mount := _get_mount(get_presence())
	if mount == null or not _mount_rests.has(mount):
		return
	var target := _pull_target if avoid_walls and has_equipped_item() else 0.0
	if is_equal_approx(_pull, target):
		_pull = target
	else:
		_pull = lerpf(_pull, target, 1.0 - exp(-pull_back_speed * delta))
	var wanted := _mount_rests[mount] + Vector3(0.0, 0.0, _pull)
	if not mount.position.is_equal_approx(wanted):
		mount.position = wanted


## The holder that belongs to this character, or null. Interactions hand over the character.
static func find_for(character: Node) -> ItemHolder:
	if character == null:
		return null
	for child in character.get_children():
		if child is ItemHolder:
			return child
	return null


## True for the holder of the player sitting at this machine. A holder whose view is set to third person
## is somebody else's, whoever owns it.
func is_local() -> bool:
	match view:
		View.FIRST_PERSON:
			return true
		View.THIRD_PERSON:
			return false
	return NetworkSession.is_local_authority(get_parent())


## Whether the holder, and the item in hand, may take input right now.
func is_input_allowed() -> bool:
	if not can_use_items.is_permitted() or InGameUIHandler.is_ui_open:
		return false
	return not _is_seated_without_items() and not _is_on_ladder()


## Whether the item in hand is out of sight: the holder is on a ladder, or sits somewhere that does not
## allow items. It comes back by itself.
func are_items_hidden() -> bool:
	return _is_on_ladder() or _is_seated_without_items()


func _is_on_ladder() -> bool:
	return is_instance_valid(ladder_controller) and ladder_controller.is_on_ladder()


## Sitting in a seat that does not allow items (see [member Seat3D.allow_items]). A seat that is not a
## Seat3D allows none.
func _is_seated_without_items() -> bool:
	if not is_instance_valid(seat_controller) or not is_instance_valid(seat_controller.current_seat):
		return false
	var seat := seat_controller.current_seat as Seat3D
	return seat == null or not seat.are_items_allowed()


## How the item in hand is seen: through the holder's own eyes, or as part of the character.
func get_presence() -> ItemActor.Presence:
	return ItemActor.Presence.FIRST_PERSON if is_local() else ItemActor.Presence.THIRD_PERSON


## The slot container the number keys pick from, or null.
func get_hotbar() -> InventorySlotContainer:
	if inventory == null:
		return null
	return inventory.get_container(hotbar_id) as InventorySlotContainer


## Equips a slot, switches to it, or unequips it when it is already held.
func toggle_inventory_slot(slot_index: int) -> bool:
	var hotbar := get_hotbar()
	if hotbar == null or slot_index < 0 or slot_index >= hotbar.size:
		return false
	var instance := hotbar.get_instance(slot_index)
	if instance == null:
		unequip_item()
		return false
	if instance == equipped_instance:
		unequip_item()
		return true
	return equip_item(instance)


## Takes an item of this holder's inventory in hand.
func equip_item(instance: ItemInstance) -> bool:
	if inventory == null or instance == null or not inventory.has_instance(instance):
		return false
	return display_item(instance)


## Shows an item in hand without asking the inventory. This is how a holder whose inventory this machine
## does not have (another player's) comes to hold what that player holds: whatever tells this machine
## what they equipped calls it, with an instance made from what it was told.
func display_item(instance: ItemInstance) -> bool:
	if instance == null or instance.item == null:
		return false
	if instance == equipped_instance and is_instance_valid(equipped_actor):
		return true
	var presence := get_presence()
	var mount := _get_mount(presence)
	if mount == null:
		return false
	var new_actor := instance.item.create_actor(instance)
	if new_actor == null:
		return false

	_unequip()
	new_actor.set_held(self, presence)
	equipped_instance = instance
	equipped_actor = new_actor
	_pull = 0.0
	mount.add_child(equipped_actor)
	_show_shadow_copy(instance, presence)
	# The item is in hand now, so it is no longer carried: this is the swap.
	_sync_carried()
	item_equipped.emit(equipped_instance, equipped_actor)
	return true


## Puts the item in hand away. If it is in a container that carries items it goes on being carried.
func unequip_item() -> void:
	if _unequip():
		_sync_carried()


## Stows what is in hand. True if there was something.
func _unequip() -> bool:
	if equipped_instance == null and not is_instance_valid(equipped_actor):
		return false
	var previous_instance := equipped_instance
	equipped_instance = null
	_free_shadow_copy()
	if is_instance_valid(equipped_actor):
		equipped_actor.stow()
		equipped_actor.queue_free()
	equipped_actor = null
	_restore_mounts()
	if previous_instance != null:
		item_unequipped.emit(previous_instance)
	return true


## The copy of the item in hand that is only a shadow on the player's own character, or null.
func get_shadow_actor() -> ItemActor:
	return _shadow_actor if is_instance_valid(_shadow_actor) else null


func has_equipped_item() -> bool:
	return equipped_instance != null and is_instance_valid(equipped_actor)


## Shows an item as carried, on the body and not in hand, without asking the inventory (so, like
## [method display_item], it is also how another player's carried items appear on this machine). Does
## nothing for an item that has no parts for carrying, or one that is in hand. [param listens] says whether
## the actor hears [method ItemActor._carried_input]. Calling it again only changes that.
func carry_item(instance: ItemInstance, listens: bool = false) -> bool:
	if instance == null or instance.item == null or carried_parent == null:
		return false
	if instance == equipped_instance or not instance.item.has_carried_parts():
		return false
	_carried_listens[instance] = listens
	if is_carrying(instance):
		return true
	var actor := instance.item.create_actor(instance)
	if actor == null:
		_carried_listens.erase(instance)
		return false
	actor.set_carried(self)
	_carried[instance] = actor
	carried_parent.add_child(actor)
	return true


## Takes an item off the body. [param packed_away] says it went into a container that does not carry it,
## which the item is told (a light goes out); otherwise it was taken in hand, dropped or given away.
func stop_carrying(instance: ItemInstance, packed_away: bool = false) -> void:
	var actor := _carried.get(instance) as ItemActor
	_carried.erase(instance)
	_carried_listens.erase(instance)
	if is_instance_valid(actor):
		if packed_away:
			actor._on_packed_away()
		actor.release()
		actor.queue_free()
		# Moving an item from one container to another takes it out and then puts it in, so for a moment
		# it is nowhere. If it ends up in a bag, its old actor (still alive until the frame ends) is told.
		_departed[instance] = actor
		_forget_departed.call_deferred()


func is_carrying(instance: ItemInstance) -> bool:
	return is_instance_valid(_carried.get(instance) as ItemActor)


## The actor of a carried item, or null.
func get_carried_actor(instance: ItemInstance) -> ItemActor:
	return _carried.get(instance) as ItemActor if is_carrying(instance) else null


## Whether this actor would hear its carried input right now: it is on the body of the player at this
## machine, in a container that listens, and nothing blocks the holder. See [method ItemActor.can_use_carried_input].
func is_carried_input_ready(actor: ItemActor) -> bool:
	if actor == null or not _carried_listens.get(actor.item_instance, false):
		return false
	return is_local() and is_input_allowed()


## Throws the item in hand into the world, with all its state: a flashlight lands as it was, on or off and
## with the same battery. Returns the item in the world, or null when there was nothing to drop.
func drop_equipped_item() -> ItemActor:
	if not has_equipped_item() or inventory == null or not inventory.has_instance(equipped_instance):
		return null

	# Nothing may leave the inventory unless it can appear in the world.
	var parent := _find_drop_parent()
	if parent == null or equipped_instance.item.actor_scene == null:
		return null

	var instance := equipped_instance
	var held := equipped_actor
	var hotbar_slot := get_hotbar().get_slot_of(instance) if get_hotbar() != null else -1
	var mount := _get_mount(get_presence())
	var pose := held.global_transform
	var forward := -mount.global_basis.z if mount != null else -held.global_basis.z
	pose.origin = _keep_out_of_walls(held, pose.origin)

	# Only apply velocity when the holder is affected by gravity.
	var velocity := Vector3.ZERO
	var holder := get_parent() as CharacterBody3D
	if holder != null and holder.get_gravity():
		velocity = _get_holder_velocity() + forward.normalized() * drop_speed

	# Let go first, so the item keeps its state instead of being put away.
	_let_go_of_equipped()
	inventory.remove(instance)

	var dropped := instance.item.spawn_in_world(instance, parent, pose, velocity)
	item_unequipped.emit(instance)
	item_dropped.emit(instance, dropped)
	if equip_next_on_drop and not has_equipped_item():
		_equip_next_hotbar_item(hotbar_slot)
	return dropped



## Hands the item in hand over to something else (an [ItemSlot], a machine that takes items): it leaves the
## inventory and the hand, with all its state, and the caller now has it. Returns the instance, or null when
## there was nothing in hand. Whoever takes it must put it somewhere, or add it back with
## [method Inventory.add].
func take_equipped_item() -> ItemInstance:
	if not has_equipped_item() or inventory == null or not inventory.has_instance(equipped_instance):
		return null
	var instance := equipped_instance
	var hotbar_slot := get_hotbar().get_slot_of(instance) if get_hotbar() != null else -1
	_let_go_of_equipped()
	inventory.remove(instance)
	item_unequipped.emit(instance)
	if equip_next_on_drop and not has_equipped_item():
		_equip_next_hotbar_item(hotbar_slot)
	return instance


## The hand is empty and its actor goes, without the item being put away (see [method ItemActor.stow]), so
## whatever happens to the item next, it keeps its state.
func _let_go_of_equipped() -> void:
	var held := equipped_actor
	equipped_instance = null
	equipped_actor = null
	held.release()
	held.queue_free()
	_free_shadow_copy()
	_restore_mounts()


## The player sees the item in their hand from their own eyes, so what the world sees of it, its shadow, comes
## from a copy on their character's hand that is not drawn (see [method ItemActor.set_held]).
func _show_shadow_copy(instance: ItemInstance, presence: ItemActor.Presence) -> void:
	if presence != ItemActor.Presence.FIRST_PERSON or third_person_parent == null:
		return
	var copy := instance.item.create_actor(instance)
	if copy == null:
		return
	copy.set_held(self, ItemActor.Presence.THIRD_PERSON, true)
	_shadow_actor = copy
	third_person_parent.add_child(copy)


func _free_shadow_copy() -> void:
	if is_instance_valid(_shadow_actor):
		_shadow_actor.release()
		_shadow_actor.queue_free()
	_shadow_actor = null

## Takes in hand the first item found in the hotbar after [param after_slot], going round to the start.
func _equip_next_hotbar_item(after_slot: int) -> void:
	var hotbar := get_hotbar()
	if hotbar == null:
		return
	for step in range(1, hotbar.size + 1):
		var instance := hotbar.get_instance((after_slot + step) % hotbar.size)
		if instance != null:
			equip_item(instance)
			return


func can_pick_up(actor: ItemActor) -> bool:
	return (
		inventory != null
		and is_local()
		and actor != null
		and actor.is_in_world()
		and actor.item_instance != null
		and inventory.can_add(actor.item_instance)
	)


## Takes an item lying in the world into the inventory, and into hand if the hand is empty. The item
## that was in the world is gone; its instance, and everything it remembers, is now in the inventory.
func pick_up(actor: ItemActor) -> bool:
	if not can_pick_up(actor):
		return false
	var instance := actor.item_instance
	if not inventory.add(instance):
		return false
	actor.visible = false
	actor.queue_free()
	var hotbar := get_hotbar()
	if equip_on_pickup and not has_equipped_item() and hotbar != null and hotbar.has_instance(instance):
		equip_item(instance)
	item_picked_up.emit(instance)
	return true


## Makes the carried actors match the inventory: one for every item that has parts for carrying, sits in a
## container that carries and is not in hand; none for any other. Runs whenever the inventory changes.
func _sync_carried() -> void:
	if inventory == null or carried_parent == null:
		return
	var wanted: Dictionary[ItemInstance, bool] = {}
	var packed: Array[ItemInstance] = []
	for container in inventory.get_containers():
		for instance in container.get_instances():
			if instance == equipped_instance or not instance.item.has_carried_parts():
				continue
			if container.carrying == InventoryContainer.Carrying.PACKED_AWAY:
				packed.append(instance)
			else:
				wanted[instance] = container.carrying == InventoryContainer.Carrying.READY
	for instance: ItemInstance in _carried.keys():
		if not wanted.has(instance):
			stop_carrying(instance, packed.has(instance))
	for instance: ItemInstance in wanted:
		carry_item(instance, wanted[instance])
	# An item that was just taken out of a pocket and is now in a bag has been packed away.
	for instance: ItemInstance in packed:
		var departed := _departed.get(instance) as ItemActor
		_departed.erase(instance)
		if is_instance_valid(departed):
			departed._on_packed_away()


func _forget_departed() -> void:
	_departed.clear()


## Gives a key press to the carried items that listen. They decide what it means.
func _send_carried_input(event: InputEvent) -> void:
	for instance: ItemInstance in _carried.keys():
		if not _carried_listens.get(instance, false):
			continue
		var actor := _carried.get(instance) as ItemActor
		if is_instance_valid(actor):
			actor._carried_input(event)


func _has_carrying_container() -> bool:
	for container in inventory.get_containers():
		if container.carrying != InventoryContainer.Carrying.PACKED_AWAY:
			return true
	return false


## An item leaves its container when it is dropped, traded, or put in a bag, and you cannot
## keep holding it then. Moving it to another hotbar slot is not leaving, so that keeps it in hand.
func _on_inventory_item_removed(_container: InventoryContainer, instance: ItemInstance) -> void:
	if instance == equipped_instance:
		unequip_item()


func _get_mount(presence: ItemActor.Presence) -> Node3D:
	return third_person_parent if presence == ItemActor.Presence.THIRD_PERSON else actor_parent


func _find_drop_parent() -> Node:
	if is_instance_valid(drop_parent):
		return drop_parent
	var node := get_parent()
	while node != null:
		if node.is_in_group(InGameUIHandler.GAMEPLAY_SCENE_GROUP):
			return node
		node = node.get_parent()
	return get_tree().current_scene if is_inside_tree() else null


func _get_holder_velocity() -> Vector3:
	var character := get_parent() as CharacterBody3D
	return character.velocity if character != null else Vector3.ZERO


## Where something thrown from the eye to [param target] ends up if a wall is in between: in front of it.
func _keep_out_of_walls(held: ItemActor, target: Vector3) -> Vector3:
	var eye := _get_eye()
	if eye == null:
		return target
	var query := PhysicsRayQueryParameters3D.create(eye.global_position, target, wall_mask)
	var hit := held.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return target
	return (hit["position"] as Vector3) + (hit["normal"] as Vector3) * drop_clearance


## The node the mount hangs from, which stands for the holder's eyes: the camera, or the head.
func _get_eye() -> Node3D:
	var mount := _get_mount(get_presence())
	return mount.get_parent() as Node3D if mount != null else null


## How far the item must come back for its front not to be inside whatever is ahead of it.
func _measure_wall_pull() -> float:
	if not avoid_walls or not has_equipped_item():
		return 0.0
	var mount := _get_mount(get_presence())
	var eye := _get_eye()
	if mount == null or eye == null or not _mount_rests.has(mount):
		return 0.0
	# From the eye to the front of the item as it sits when it is not pulled back.
	var front := eye.to_global(_mount_rests[mount] + Vector3(0.0, 0.0, -equipped_actor.reach))
	var from := eye.global_position
	var query := PhysicsRayQueryParameters3D.create(from, front, wall_mask)
	var hit := mount.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return 0.0
	var wall_distance := from.distance_to(hit["position"] as Vector3)
	return clampf(from.distance_to(front) - wall_distance + wall_margin, 0.0, max_pull_back)


func _restore_mounts() -> void:
	_pull = 0.0
	_pull_target = 0.0
	for mount in _mount_rests:
		if is_instance_valid(mount):
			mount.position = _mount_rests[mount]
