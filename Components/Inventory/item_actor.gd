## The node that stands for one [ItemInstance] wherever the item is: lying in the world, in a player's
## hands, or on a player's body. Every item scene has one of these as its root, and WorldItem.tscn is the
## scene they all start from (an inherited scene), so a flashlight is ONE scene and not one for the ground
## and another for the hand.
##
## An actor is made in one of four [enum Presence]s and keeps it for as long as it lives. A world actor
## is a physical body that players can pick up. A held actor is the same scene with its body switched
## off, sitting in a mount: in first person for the player holding it, in third person for everybody
## else. A carried actor is an item that is in a pocket, not in hand: only the parts made for that exist.
## Dropping an item frees the held actor and makes a world one from the same ItemInstance, and picking it
## up does the reverse, so the item's data (the battery, whether it is on) is never copied. It is the same
## object all along.
##
## Parts that only belong to some presences go in groups, and the actor frees the others as it is made, so
## they never run in the wrong place. A node with none of these groups is in the world and in hands.
## [codeblock]
## item_world          the collision shape, the pickup prompt
## item_first_person   arms, a sight, anything only the holder sees
## item_third_person   a model made for the character's hand
## item_carried        only while it is in a pocket, such as a status light
## item_always         everywhere, pockets included: the flashlight's beam
## [/codeblock]
## A node may be in several (both held ones, say). In a pocket nothing exists unless it is in
## [code]item_always[/code] or [code]item_carried[/code] (or holds something that is), so an item that
## needs nothing while carried has no actor at all, and costs nothing.
##
## [b]Input.[/b] An item reads input like any node, in [method Node._unhandled_input] or
## [method Node._input]. This class makes sure those are only called while the item is held in first
## person: by the player who holds it, on their own machine, with no menu open. Nothing needs checking.
## [member holder] says who holds it. To read input by polling instead, ask [method can_use_input].
##
## A carried item has input of its own, [method _carried_input], for what it does from a pocket. It is
## only called while the holder's container is meant to listen (see [enum InventoryContainer.Carrying]),
## so a player with two flashlights in their bag does not switch both on with one key.
##
## [b]Drawing.[/b] A first-person item is a normal node in the world, in the hand's place, so the world's
## lights light it and its own lights light the world. It is drawn clear of walls by its materials, with
## no second camera: each standard material gets Godot's z clip scale, which draws it as if it were closer
## to the camera than it is, and a field of view of its own. The actor does this to copies of the item's
## materials as it is made, so the same scene in the world is unaffected. A material with a custom
## shader is left alone (and warned about), as it has to do the same in its own vertex function.
class_name ItemActor
extends RigidBody3D

enum Presence {
	## Lying on the ground, on a shelf, anywhere in the world: a body players can pick up.
	WORLD,
	## In the hands of the player sitting at this machine, seen through their own eyes.
	FIRST_PERSON,
	## In the hands of another player, seen as part of their character.
	THIRD_PERSON,
	## On a player's body, not in hand: only the parts made for carrying exist. It looks the same on every
	## machine, because it hangs from the character's head and not from the camera.
	CARRIED,
}

const GROUP_WORLD: StringName = &"item_world"
const GROUP_FIRST_PERSON: StringName = &"item_first_person"
const GROUP_THIRD_PERSON: StringName = &"item_third_person"
const GROUP_CARRIED: StringName = &"item_carried"
const GROUP_ALWAYS: StringName = &"item_always"

## Which item this scene is: the id of its [Item] resource (see [ItemRegistry]). Only read by an actor
## placed in a level by hand. One made from an ItemInstance already knows.
@export var item_id: StringName
## For an actor placed by hand: how the item starts out, such as a flashlight at 40% battery. Leave it
## empty for a fresh one. Each copy of the scene gets its own copy of this.
@export var starting_instance: ItemInstance

@export_group("Held")
## Where the item sits in the holder's hand, relative to the mount, seen by the holder.
@export var first_person_offset := Transform3D.IDENTITY
## Where the item sits in the holder's hand, relative to the mount, seen by everyone else.
@export var third_person_offset := Transform3D.IDENTITY
## How much of the walking bob the item takes on in the holder's own view, as a multiple of the holder's
## own setting (see [ItemMotion]). A heavy tool might be 0.5 and stay steadier, 0 keeps it fixed in view.
@export_range(0.0, 2.0, 0.05) var bob_scale := 1.0
## How far the item sticks out in front of the hand. It is pulled back toward the holder when something
## is closer than that, so it never pokes into a wall and its light stays out of it.
@export_range(0.0, 2.0, 0.01, "suffix:m") var reach := 0.3
## How far toward the camera the holder's own view draws the item, as a share of its distance. Smaller
## keeps it clear of closer walls, but the front of the item is lost if it comes nearer than the
## camera's near plane. Screen-space effects such as SSAO and SSR are less right the further from 1.
@export_range(0.05, 1.0, 0.01) var first_person_clip_scale := 0.3
## The field of view the holder's own view draws the item with, whatever the world's is.
@export_range(20.0, 120.0, 1.0, "suffix:°") var first_person_fov := 75.0

@export_group("Carried")
## Where the item sits on the body while it is carried, relative to the holder's carry mount.
@export var carried_offset := Transform3D.IDENTITY

var item: Item
var item_instance: ItemInstance
## Who has this: the holder with it in hand or in a pocket. Null while it is in the world.
var holder: ItemHolder
var presence := Presence.WORLD

var _presence_applied := false
var _shadow_only := false
var _input_open := true
var _wants_input := false
var _wants_shortcut_input := false
var _wants_unhandled_input := false
var _wants_unhandled_key_input := false
## First-person copies of the item's materials, by the material each stands for.
var _first_person_materials: Dictionary[Material, Material] = {}


func _notification(what: int) -> void:
	# Notifications reach every script in the chain, so an item that overrides _ready (or any other
	# virtual) never has to call super for this to work.
	match what:
		NOTIFICATION_ENTER_TREE:
			_apply_presence(presence)
			_ensure_instance()
			_enter_presence()
		NOTIFICATION_READY:
			# By now the engine has switched on whatever input the item's script defines.
			_wants_input = is_processing_input()
			_wants_shortcut_input = is_processing_shortcut_input()
			_wants_unhandled_input = is_processing_unhandled_input()
			_wants_unhandled_key_input = is_processing_unhandled_key_input()
			# Only a first-person item can ever be allowed input, and it asks the holder every frame.
			set_process_internal(presence == Presence.FIRST_PERSON)
			_update_input_gate(true)
			if item_instance != null:
				_on_item_instance_changed()
		NOTIFICATION_INTERNAL_PROCESS:
			_update_input_gate()
		NOTIFICATION_EXIT_TREE:
			if get_tree().node_added.is_connected(_on_tree_node_added):
				get_tree().node_added.disconnect(_on_tree_node_added)


## Gives the actor its instance. [method ItemActor._on_item_instance_changed] follows.
func setup(instance: ItemInstance) -> void:
	item_instance = instance
	item = instance.item if instance != null else null
	if is_node_ready():
		_on_item_instance_changed()


## Makes this actor an item in somebody's hands. Call it before the actor enters the tree, because it
## decides which parts are kept and switches the body off. ItemHolder does this.
##
## [param shadow_only] makes the actor a shadow and nothing else: its meshes are not drawn but still cast
## their shadow, and its lights are freed. The player sees one of these in the hand of their own character
## (the third person copy), so they see the shadow of what they hold. Whatever the item runs on its own (a
## battery draining, a sound) must check [method is_shadow_only] and not run.
func set_held(by: ItemHolder, view: Presence, shadow_only: bool = false) -> void:
	if is_inside_tree() or _presence_applied:
		push_error("[ItemActor] set_held must be called before the actor enters the tree.")
		return
	if view != Presence.FIRST_PERSON and view != Presence.THIRD_PERSON:
		push_error("[ItemActor] A held item is seen in first or third person.")
		return
	holder = by
	_apply_presence(view)
	if shadow_only:
		_shadow_only = true
		_make_shadow_only(self)


## Makes this actor an item on somebody's body, not in hand. Call it before the actor enters the tree, for
## the same reason as [method set_held]. ItemHolder does this.
func set_carried(by: ItemHolder) -> void:
	if is_inside_tree() or _presence_applied:
		push_error("[ItemActor] set_carried must be called before the actor enters the tree.")
		return
	holder = by
	_apply_presence(Presence.CARRIED)


## The holder lets go of the item, whether it is being put away or dropped. It stops reading input and
## disappears at once, and the holder frees it.
func release() -> void:
	holder = null
	visible = false
	if is_node_ready():
		_update_input_gate(true)


## The holder puts the item away, into the inventory. What the item does about it is in
## [method ItemActor._on_stowed]. It may be carried from then on (see [method ItemActor._on_packed_away]
## for what ends when it is not). Dropping an item is not this: it just releases it.
func stow() -> void:
	_on_stowed()
	release()


## In somebody's hand, seen by them or by others.
func is_held() -> bool:
	return holder != null and (presence == Presence.FIRST_PERSON or presence == Presence.THIRD_PERSON)


## In somebody's pocket and not in hand.
func is_carried() -> bool:
	return holder != null and presence == Presence.CARRIED


func is_in_world() -> bool:
	return presence == Presence.WORLD


func is_first_person() -> bool:
	return presence == Presence.FIRST_PERSON


func is_third_person() -> bool:
	return presence == Presence.THIRD_PERSON


## Held by the player at this machine, seen through their own eyes. The only case that reads input.
func is_held_locally() -> bool:
	return holder != null and presence == Presence.FIRST_PERSON


## Whether input may be read right now: [method is_held_locally], and the holder is not blocked
## (a menu is open, they are sitting in a turret). Event callbacks are already limited to this.
func can_use_input() -> bool:
	return is_held_locally() and holder.is_input_allowed()


## Whether [method _carried_input] would be called right now: the item is carried by the player at this
## machine, its container listens, and nothing blocks them. To read input while carried by polling.
func can_use_carried_input() -> bool:
	return is_carried() and holder.is_carried_input_ready(self)


## Called when the actor first learns its instance, and again if [method setup] gives it another. Read
## the instance's state here, and watch its signals to keep up with it.
func _on_item_instance_changed() -> void:
	pass


## Input for an item that is carried and not in hand, like [method Node._unhandled_input] is for one in
## hand. Only called for the player who carries it, on their own machine, while the container it is in
## listens (READY, see [enum InventoryContainer.Carrying]), so it can safely do what a key says:
## [codeblock]
## func _carried_input(event: InputEvent) -> void:
##     if event.is_action_pressed(&"toggle_flashlight"):
##         toggle()
## [/codeblock]
func _carried_input(_event: InputEvent) -> void:
	pass


## Somebody used one of this item's own options while it lies in the world (see [ItemPickup]): a flashlight
## that has a "toggle" option switches here. [param option_id] is the option's id. Return whether it did
## something. Picking the item up is not one of these.
func _on_world_option(_option_id: StringName, _interactor: Node3D) -> bool:
	return false


## The holder put the item away, out of hand. A flashlight does nothing here: it goes on shining from the
## pocket. A weapon might unload.
func _on_stowed() -> void:
	pass


## The item went into a container that does not carry it (a backpack), so this actor is about to go. A
## light would switch itself off here. It is not called when the item is taken in hand, dropped or leaves
## the inventory.
func _on_packed_away() -> void:
	pass


func _apply_presence(value: Presence) -> void:
	if _presence_applied:
		return
	_presence_applied = true
	presence = value
	_prune_other_presences(self)
	if presence == Presence.WORLD:
		return
	# A held or carried item is moved by its mount alone, and nothing collides with it.
	# Static, not kinematic. A kinematic body is moved by the physics engine, which trails the node by
	# a step and writes that older place back onto it, so an item in a moving hand would shake.
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	collision_layer = 0
	collision_mask = 0
	if presence == Presence.FIRST_PERSON:
		_draw_clear_of_walls(self)
		# What they hold casts its shadow from the character's hand (see set_held), not from the camera.
		if holder != null and holder.third_person_parent != null:
			_cast_no_shadow(self)
	if presence == Presence.FIRST_PERSON or (presence == Presence.CARRIED and holder != null and holder.is_local()):
		_keep_own_body_out_of_light(self)


## Frees every part that belongs to another presence. Nothing here is in the tree yet, so none of it
## has run or been seen.
func _prune_other_presences(root: Node) -> void:
	for child in root.get_children():
		if _belongs_to_other_presence(child):
			root.remove_child(child)
			child.free()
		else:
			_prune_other_presences(child)


func _belongs_to_other_presence(node: Node) -> bool:
	if node.is_in_group(GROUP_ALWAYS):
		return false
	var tagged := false
	for group_presence: Presence in [Presence.WORLD, Presence.FIRST_PERSON, Presence.THIRD_PERSON, Presence.CARRIED]:
		if node.is_in_group(_group_of(group_presence)):
			if group_presence == presence:
				return false
			tagged = true
	if tagged:
		return true
	# Nothing says where it belongs, so it is part of the item as seen in the world and in a hand. A pocket
	# has none of that, unless the node is only there to hold something that does.
	return presence == Presence.CARRIED and not _holds_carried_part(node)


func _holds_carried_part(node: Node) -> bool:
	for child in node.get_children():
		if child.is_in_group(GROUP_ALWAYS) or child.is_in_group(GROUP_CARRIED) or _holds_carried_part(child):
			return true
	return false


func _group_of(value: Presence) -> StringName:
	match value:
		Presence.FIRST_PERSON:
			return GROUP_FIRST_PERSON
		Presence.THIRD_PERSON:
			return GROUP_THIRD_PERSON
		Presence.CARRIED:
			return GROUP_CARRIED
	return GROUP_WORLD


## Whether a scene has any part that exists while its item is carried, that is a node in
## [constant GROUP_CARRIED] or [constant GROUP_ALWAYS]. Looks through the scenes it is inherited from.
static func scene_has_carried_parts(scene: PackedScene) -> bool:
	if scene == null:
		return false
	var state := scene.get_state()
	while state != null:
		for index in state.get_node_count():
			var groups := state.get_node_groups(index)
			if groups.has(GROUP_CARRIED) or groups.has(GROUP_ALWAYS):
				return true
		state = state.get_base_scene_state()
	return false


## True for the copy of a held item that is only a shadow (see [method set_held]).
func is_shadow_only() -> bool:
	return _shadow_only


func _make_shadow_only(root: Node) -> void:
	for child in root.get_children():
		if child is Light3D:
			root.remove_child(child)
			child.free()
			continue
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		_make_shadow_only(child)


func _cast_no_shadow(root: Node) -> void:
	for child in root.get_children():
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_cast_no_shadow(child)


## The light of what a player holds or carries does not shine on their own body model, so the model
## does not shadow it (see [Player]).
func _keep_own_body_out_of_light(root: Node) -> void:
	for child in root.get_children():
		if child is Light3D:
			(child as Light3D).light_cull_mask &= ~Player.OWN_BODY_LAYER
		_keep_own_body_out_of_light(child)


## Gives everything the item draws its first-person materials.
func _draw_clear_of_walls(root: Node) -> void:
	for child in root.get_children():
		if child is GeometryInstance3D:
			_draw_clear_of_walls_geometry(child as GeometryInstance3D)
		_draw_clear_of_walls(child)


func _draw_clear_of_walls_geometry(geometry: GeometryInstance3D) -> void:
	geometry.material_override = _first_person_material(geometry.material_override, geometry)
	geometry.material_overlay = _first_person_material(geometry.material_overlay, geometry)
	var mesh_instance := geometry as MeshInstance3D
	if mesh_instance == null or mesh_instance.mesh == null or mesh_instance.material_override != null:
		return
	for surface in mesh_instance.mesh.get_surface_count():
		var material := mesh_instance.get_active_material(surface)
		var converted := _first_person_material(material, mesh_instance)
		if converted != material:
			# On this node only: the mesh, and every other actor made from it, keeps its own.
			mesh_instance.set_surface_override_material(surface, converted)


## The material to draw with in first person. A copy, made once for each material the item uses, so the
## parts that share one still share one.
func _first_person_material(material: Material, user: Node) -> Material:
	if material == null:
		return null
	if _first_person_materials.has(material):
		return _first_person_materials[material]
	var standard := material as BaseMaterial3D
	if standard == null:
		push_warning("[ItemActor] %s draws with a custom shader, which cannot keep clear of walls in first person by itself." % user.name)
		return material
	if standard.use_z_clip_scale:
		# Already made for a viewmodel by whoever authored it.
		return material
	var copy := standard.duplicate() as BaseMaterial3D
	copy.use_z_clip_scale = true
	copy.z_clip_scale = first_person_clip_scale
	copy.use_fov_override = true
	copy.fov_override = first_person_fov
	_first_person_materials[material] = copy
	_first_person_materials[copy] = copy
	copy.next_pass = _first_person_material(standard.next_pass, user)
	return copy


## Something the item adds while held (a muzzle flash) is drawn the same way.
func _on_tree_node_added(node: Node) -> void:
	if node is GeometryInstance3D and is_ancestor_of(node):
		_draw_clear_of_walls_geometry(node as GeometryInstance3D)


func _enter_presence() -> void:
	match presence:
		Presence.FIRST_PERSON:
			transform = first_person_offset
			if not get_tree().node_added.is_connected(_on_tree_node_added):
				get_tree().node_added.connect(_on_tree_node_added)
		Presence.THIRD_PERSON:
			transform = third_person_offset
		Presence.CARRIED:
			transform = carried_offset


## An actor placed in a level by hand makes its own instance.
func _ensure_instance() -> void:
	if item_instance != null:
		return
	var instance: ItemInstance
	if starting_instance != null:
		# Copies of one scene share what is saved in it, and each needs an instance of its own.
		instance = starting_instance.duplicate() as ItemInstance
		if instance.item == null:
			instance.item = ItemRegistry.get_item(item_id)
	else:
		var definition := ItemRegistry.get_item(item_id)
		if definition != null:
			instance = definition.create_instance()
	if instance == null or instance.item == null:
		push_warning("[ItemActor] %s has no item. Set its Item Id to the id of an Item in the registry." % get_path())
		return
	item_instance = instance
	item = instance.item


func _update_input_gate(force: bool = false) -> void:
	var open := can_use_input()
	if open == _input_open and not force:
		return
	_input_open = open
	set_process_input(open and _wants_input)
	set_process_shortcut_input(open and _wants_shortcut_input)
	set_process_unhandled_input(open and _wants_unhandled_input)
	set_process_unhandled_key_input(open and _wants_unhandled_key_input)
