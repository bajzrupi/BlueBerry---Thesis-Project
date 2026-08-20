extends Node

# Runtime registry for every inventory item definition.

signal item_registered(
	item_id: StringName,
	item_data: ItemData
)

signal catalog_rebuilt(
	item_count: int
)


@export_category("Debug Logging")

@export var debug_log: bool = false


var _items: Dictionary = {}


# Initializes this system when the node becomes ready.
func _ready() -> void:
	rebuild_catalog()

	if debug_log:
		print(
			"[ItemCatalog] ready items=",
			get_all_item_ids()
		)


# Rebuilds the alpha catalog. Current seed items are bridged from PlantData,
# so existing Lily/Cactus .tres files do not need to be changed.
func rebuild_catalog() -> void:
	_items.clear()

	for plant_data: PlantData in (
		PlantSelectionSystem.get_all_plants()
	):
		_register_seed_from_plant(plant_data)

	catalog_rebuilt.emit(_items.size())

	if debug_log:
		print(
			"[ItemCatalog] rebuilt count=",
			_items.size(),
			" ids=",
			get_all_item_ids()
		)


# Registers a generic ItemData resource for future content.
func register_item(item_data: ItemData) -> bool:
	if item_data == null or not item_data.is_valid():
		if debug_log:
			print("[ItemCatalog] register rejected invalid item")
		return false

	_items[item_data.item_id] = item_data
	item_registered.emit(
		item_data.item_id,
		item_data
	)

	if debug_log:
		print(
			"[ItemCatalog] registered id=",
			String(item_data.item_id),
			" name=",
			item_data.display_name,
			" kind=",
			item_data.item_kind
		)

	return true


# Checks whether item exists or is available.
func has_item(item_id: StringName) -> bool:
	return item_id != &"" and _items.has(item_id)


# Returns the item.
func get_item(item_id: StringName) -> ItemData:
	var value: Variant = _items.get(item_id)

	if value is ItemData:
		return value as ItemData

	return null


# Returns the all items.
func get_all_items() -> Array[ItemData]:
	var result: Array[ItemData] = []

	for value: Variant in _items.values():
		if value is ItemData:
			result.append(value as ItemData)

	return result


# Returns the all item IDs.
func get_all_item_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for key: Variant in _items.keys():
		result.append(StringName(String(key)))

	return result


# Returns the plant definition linked to a seed item.
func get_plant_for_item(
	item_id: StringName
) -> PlantData:
	var item_data: ItemData = get_item(item_id)

	if item_data == null:
		return null

	return item_data.linked_plant_data


# Checks whether the item is a seed item.
func is_seed_item(item_id: StringName) -> bool:
	var item_data: ItemData = get_item(item_id)
	return item_data != null and item_data.is_seed()


# Registers the seed from plant.
func _register_seed_from_plant(
	plant_data: PlantData
) -> void:
	if (
		plant_data == null
		or plant_data.seed_item_id == &""
	):
		return

	var item_data := ItemData.new()
	item_data.item_id = plant_data.seed_item_id
	item_data.display_name = "%s Seeds" % (
		plant_data.display_name
	)
	item_data.description = (
		"Seeds used to plant %s." % plant_data.display_name
	)
	item_data.item_kind = ItemData.ItemKind.SEED
	item_data.stack_limit = 9999
	item_data.hotbar_allowed = true
	item_data.linked_plant_data = plant_data

	register_item(item_data)
