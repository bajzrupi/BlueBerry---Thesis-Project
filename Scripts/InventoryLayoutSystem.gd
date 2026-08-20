extends Node

# Legacy signal retained for the current plant inventory UI.
signal slot_changed(
	slot_index: int,
	plant_data: PlantData
)

# Generic item-facing signal for new inventory consumers.
signal item_slot_changed(
	slot_index: int,
	item_id: StringName,
	item_data: ItemData
)

signal layout_reset()


const SLOT_COUNT: int = 8


@export_category("Debug Logging")

@export var debug_log: bool = false


# Inventory layout storage is now generic item identifiers.
var _slots: Array[StringName] = []


# Initializes this system when the node becomes ready.
func _ready() -> void:
	if not PlantSelectionSystem.available_plants_changed.is_connected(
		_on_available_plants_changed
	):
		PlantSelectionSystem.available_plants_changed.connect(
			_on_available_plants_changed
		)

	if not InventorySystem.item_discovered.is_connected(
		_on_item_discovered
	):
		InventorySystem.item_discovered.connect(
			_on_item_discovered
		)

	reset_to_defaults()

	if debug_log:
		print(
			"[InventoryLayout] ready slots=",
			SLOT_COUNT,
			" storage=generic_item_ids"
		)


# Restores this system to its default state.
func reset_to_defaults() -> void:
	_slots.clear()

	for _index in range(SLOT_COUNT):
		_slots.append(&"")

	# Positive-stock generic items are valid inventory entries.
	for key: Variant in InventorySystem.get_all_items().keys():
		var item_id := StringName(String(key))

		if InventorySystem.get_amount(item_id) <= 0:
			continue

		_insert_item_first_free(item_id)

	# Unlocked seeds remain visible even when their amount is zero.
	_sync_available_plants()

	layout_reset.emit()

	if debug_log:
		print(
			"[InventoryLayout] reset layout=",
			get_layout_ids()
		)


# Returns the slot count.
func get_slot_count() -> int:
	return SLOT_COUNT


# Returns the item ID.
func get_item_id(slot_index: int) -> StringName:
	if not _is_valid_slot(slot_index):
		return &""

	return _slots[slot_index]


# Returns the item data.
func get_item_data(slot_index: int) -> ItemData:
	return ItemCatalogSystem.get_item(
		get_item_id(slot_index)
	)


# Returns the plant.
func get_plant(slot_index: int) -> PlantData:
	return ItemCatalogSystem.get_plant_for_item(
		get_item_id(slot_index)
	)


# Finds the item slot.
func find_item_slot(item_id: StringName) -> int:
	if item_id == &"":
		return -1

	for index in range(_slots.size()):
		if _slots[index] == item_id:
			return index

	return -1


# Finds the plant slot.
func find_plant_slot(plant_data: PlantData) -> int:
	if plant_data == null:
		return -1

	return find_item_slot(plant_data.seed_item_id)


# Moves the slot.
func move_slot(
	source_index: int,
	target_index: int
) -> bool:
	if (
		not _is_valid_slot(source_index)
		or not _is_valid_slot(target_index)
	):
		return false

	if source_index == target_index:
		return true

	var source_id: StringName = _slots[source_index]
	var target_id: StringName = _slots[target_index]

	if source_id == &"":
		return false

	_slots[target_index] = source_id
	_slots[source_index] = target_id

	_emit_slot_changed(target_index)
	_emit_slot_changed(source_index)

	if debug_log:
		print(
			"[InventoryLayout] moved source=",
			source_index,
			" target=",
			target_index,
			" item_id=",
			String(source_id),
			" swapped_with=",
			String(target_id) if target_id != &"" else "EMPTY"
		)

	return true


# Moves the item to slot.
func move_item_to_slot(
	item_id: StringName,
	target_index: int
) -> bool:
	if (
		item_id == &""
		or not _is_valid_slot(target_index)
		or not ItemCatalogSystem.has_item(item_id)
	):
		return false

	var source_index: int = find_item_slot(item_id)

	if source_index < 0:
		var target_id: StringName = _slots[target_index]
		_slots[target_index] = item_id
		_emit_slot_changed(target_index)

		if target_id != &"":
			var free_slot: int = get_first_free_slot()

			if free_slot < 0:
				_slots[target_index] = target_id
				_emit_slot_changed(target_index)
				return false

			_slots[free_slot] = target_id
			_emit_slot_changed(free_slot)

		if debug_log:
			print(
				"[InventoryLayout] inserted item_id=",
				String(item_id),
				" target=",
				target_index
			)

		return true

	return move_slot(source_index, target_index)


# Moves the plant to slot.
func move_plant_to_slot(
	plant_data: PlantData,
	target_index: int
) -> bool:
	if (
		plant_data == null
		or not PlantSelectionSystem.is_plant_available(
			plant_data
		)
	):
		return false

	return move_item_to_slot(
		plant_data.seed_item_id,
		target_index
	)


# Returns the first free slot.
func get_first_free_slot() -> int:
	for index in range(_slots.size()):
		if _slots[index] == &"":
			return index

	return -1


# Returns the layout IDs.
func get_layout_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for item_id: StringName in _slots:
		result.append(item_id)

	return result


# Ensures the item present exists and is ready to use.
func ensure_item_present(item_id: StringName) -> int:
	var existing_slot: int = find_item_slot(item_id)

	if existing_slot >= 0:
		return existing_slot

	return _insert_item_first_free(item_id)


# Inserts the item first free.
func _insert_item_first_free(item_id: StringName) -> int:
	if (
		item_id == &""
		or not ItemCatalogSystem.has_item(item_id)
	):
		return -1

	var free_slot: int = get_first_free_slot()

	if free_slot < 0:
		if debug_log:
			print(
				"[InventoryLayout] no free slot item_id=",
				String(item_id)
			)
		return -1

	_slots[free_slot] = item_id
	_emit_slot_changed(free_slot)
	return free_slot


# Synchronizes the available plants.
func _sync_available_plants() -> void:
	for plant_data: PlantData in (
		PlantSelectionSystem.available_plants
	):
		if plant_data == null:
			continue

		var item_id: StringName = plant_data.seed_item_id

		if find_item_slot(item_id) >= 0:
			continue

		var slot_index: int = _insert_item_first_free(
			item_id
		)

		if debug_log and slot_index >= 0:
			print(
				"[InventoryLayout] unlocked plant inserted=",
				plant_data.display_name,
				" item_id=",
				String(item_id),
				" slot=",
				slot_index
			)


# Emits the slot changed.
func _emit_slot_changed(slot_index: int) -> void:
	var item_id: StringName = get_item_id(slot_index)
	var item_data: ItemData = (
		ItemCatalogSystem.get_item(item_id)
	)
	var plant_data: PlantData = (
		ItemCatalogSystem.get_plant_for_item(item_id)
	)

	item_slot_changed.emit(
		slot_index,
		item_id,
		item_data
	)
	slot_changed.emit(
		slot_index,
		plant_data
	)


# Handles the available plants changed signal or callback.
func _on_available_plants_changed(
	_plants: Array[PlantData]
) -> void:
	_sync_available_plants()


# Handles the item discovered signal or callback.
func _on_item_discovered(
	item_id: StringName
) -> void:
	ensure_item_present(item_id)


# Checks whether the requested slot index is valid.
func _is_valid_slot(slot_index: int) -> bool:
	return slot_index >= 0 and slot_index < SLOT_COUNT
