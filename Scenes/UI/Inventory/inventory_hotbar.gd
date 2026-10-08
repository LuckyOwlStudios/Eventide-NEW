## Four-slot inventory display. ItemHolder owns selection and input behavior.
class_name InventoryHotbar
extends HBoxContainer

const SLOT_COUNT := 4

@export var inventory: Inventory
@export var item_holder: ItemHolder

var _slots: Array[PanelContainer] = []
var _icons: Array[TextureRect] = []
var _quantity_labels: Array[Label] = []

func _ready() -> void:
	_build_slots()
	if inventory != null:
		inventory.inventory_changed.connect(_refresh)
	if item_holder != null:
		item_holder.item_equipped.connect(_on_item_equipped)
		item_holder.item_unequipped.connect(_on_item_unequipped)
	_refresh()

func _build_slots() -> void:
	for slot_index in SLOT_COUNT:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(68.0, 68.0)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(slot)

		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)

		var key_label := Label.new()
		key_label.text = str(slot_index + 1)
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		key_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		key_label.add_theme_font_size_override(&"font_size", 14)
		key_label.add_theme_color_override(&"font_color", Color(0.85, 0.9, 1.0))
		key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(key_label)

		var quantity_label := Label.new()
		quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		quantity_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		quantity_label.add_theme_font_size_override(&"font_size", 16)
		quantity_label.add_theme_color_override(&"font_color", Color.WHITE)
		quantity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(quantity_label)

		_slots.append(slot)
		_icons.append(icon)
		_quantity_labels.append(quantity_label)

func _refresh() -> void:
	for slot_index in SLOT_COUNT:
		var instance: ItemInstance
		if inventory != null and slot_index < inventory.items.size():
			instance = inventory.items[slot_index]
		var is_equipped := item_holder != null and instance != null and instance == item_holder.equipped_instance
		_slots[slot_index].add_theme_stylebox_override(&"panel", _make_slot_style(is_equipped))
		if instance == null or instance.item == null:
			_icons[slot_index].texture = null
			_quantity_labels[slot_index].text = ""
			_slots[slot_index].tooltip_text = "Empty"
			continue
		_icons[slot_index].texture = instance.item.icon
		_quantity_labels[slot_index].text = str(instance.quantity) if instance.quantity > 1 else ""
		_slots[slot_index].tooltip_text = instance.item.display_name

func _make_slot_style(is_equipped: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.05, 0.075, 0.9)
	style.border_color = Color(0.3, 0.85, 1.0) if is_equipped else Color(0.32, 0.38, 0.48)
	style.set_border_width_all(3 if is_equipped else 2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 8.0
	style.content_margin_top = 8.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 8.0
	return style

func _on_item_equipped(_instance: ItemInstance, _actor: ItemActor) -> void:
	_refresh()

func _on_item_unequipped(_instance: ItemInstance) -> void:
	_refresh()
