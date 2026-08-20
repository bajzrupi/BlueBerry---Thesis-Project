extends Node

# Legacy plant-facing signal kept so the current UI remains compatible.
signal slot_changed(
	slot_index: int,
	plant_data: PlantData
)

# Generic item-facing signal for new systems.
signal item_slot_changed(
	slot_index: int,
	item_id: StringName,
	item_data: ItemData
)

signal hotbar_reset()

signal assignment_failed(
	reason: String,
	plant_data: PlantData,
	slot_index: int
)

signal item_assignment_failed(
	reason: String,
	item_id: StringName,
	slot_index: int
)


const SLOT_COUNT: int = 8

const REASON_HOTBAR_FULL: String = "HOTBAR_FULL"
const REASON_SLOT_OCCUPIED: String = "SLOT_OCCUPIED"
const REASON_INVALID_SLOT: String = "INVALID_SLOT"
const REASON_INVALID_PLANT: String = "INVALID_PLANT"
const REASON_INVALID_ITEM: String = "INVALID_ITEM"
const REASON_ITEM_NOT_ALLOWED: String = "ITEM_NOT_ALLOWED"


@export_category("Debug Logging")

@export var debug_log: bool = false


# Hotbar storage is now item-id based instead of PlantData based.
var _slots: Array[StringName] = []


# Initializes this system when the node becomes ready.
func _ready() -> void:
	reset_to_defaults()

	if debug_log:
		print(
			"[HotbarSystem] ready slots=",
			SLOT_COUNT,
			" storage=generic_item_ids"
		)


# Restores this system to its default state.
func reset_to_defaults() -> void:
	_slots.clear()

	for _index in range(SLOT_COUNT):
		_slots.append(&"")

	var plants: Array[PlantData] = (
		PlantSelectionSystem.available_plants
	)

	if plants.size() > 0:
		_slots[0] = plants[0].seed_item_id

	if plants.size() > 1:
		_slots[1] = plants[1].seed_item_id

	hotbar_reset.emit()

	if debug_log:
		print(
			"[HotbarSystem] reset assignments=",
			get_assignment_ids()
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


# Finds the item slot.
func find_item_slot(item_id: StringName) -> int:
	if item_id == &"":
		return -1

	for index in range(_slots.size()):
		if _slots[index] == item_id:
			return index

	return -1


# Checks whether the hotbar already contains an item.
func contains_item(item_id: StringName) -> bool:
	return find_item_slot(item_id) >= 0


# Returns the plant.
func get_plant(slot_index: int) -> PlantData:
	return ItemCatalogSystem.get_plant_for_item(
		get_item_id(slot_index)
	)


# Finds the plant slot.
func find_plant_slot(plant_data: PlantData) -> int:
	if plant_data == null:
		return -1

	return find_item_slot(plant_data.seed_item_id)


# Checks whether the hotbar already contains a plant.
func contains_plant(plant_data: PlantData) -> bool:
	return find_plant_slot(plant_data) >= 0


# Returns the first free slot.
func get_first_free_slot() -> int:
	for index in range(_slots.size()):
		if _slots[index] == &"":
			return index

	return -1


# Checks whether all available slots are occupied.
func is_full() -> bool:
	return get_first_free_slot() < 0


# Adds the item.
func add_item(item_id: StringName) -> int:
	if not _is_item_assignable(item_id):
		_emit_item_assignment_failed(
			REASON_INVALID_ITEM,
			item_id,
			-1
		)
		return -1

	var existing_slot: int = find_item_slot(item_id)

	if existing_slot >= 0:
		return existing_slot

	var free_slot: int = get_first_free_slot()

	if free_slot < 0:
		_emit_item_assignment_failed(
			REASON_HOTBAR_FULL,
			item_id,
			-1
		)
		return -1

	if not assign_item(free_slot, item_id):
		return -1

	return free_slot


# Assigns the item.
func assign_item(
	slot_index: int,
	item_id: StringName
) -> bool:
	if not _is_valid_slot(slot_index):
		_emit_item_assignment_failed(
			REASON_INVALID_SLOT,
			item_id,
			slot_index
		)
		return false

	if not _is_item_assignable(item_id):
		_emit_item_assignment_failed(
			REASON_ITEM_NOT_ALLOWED,
			item_id,
			slot_index
		)
		return false

	var previous_slot: int = find_item_slot(item_id)
	var target_item_id: StringName = _slots[slot_index]

	if previous_slot == slot_index:
		_emit_slot_changed(slot_index)
		return true

	if (
		target_item_id != &""
		and target_item_id != item_id
	):
		_emit_item_assignment_failed(
			REASON_SLOT_OCCUPIED,
			item_id,
			slot_index
		)
		return false

	if previous_slot >= 0:
		_slots[previous_slot] = &""
		_emit_slot_changed(previous_slot)

	_slots[slot_index] = item_id
	_emit_slot_changed(slot_index)

	if debug_log:
		var item_data: ItemData = (
			ItemCatalogSystem.get_item(item_id)
		)
		print(
			"[HotbarSystem] assigned item=",
			item_data.display_name if item_data != null else String(item_id),
			" id=",
			String(item_id),
			" slot=",
			slot_index,
			" moved_from=",
			previous_slot
		)

	return true


# Removes the item.
func remove_item(item_id: StringName) -> bool:
	var slot_index: int = find_item_slot(item_id)

	if slot_index < 0:
		return false

	return clear_slot(slot_index)


# Adds the plant.
func add_plant(plant_data: PlantData) -> int:
	if plant_data == null:
		_emit_legacy_assignment_failed(
			REASON_INVALID_PLANT,
			null,
			-1
		)
		return -1

	return add_item(plant_data.seed_item_id)


# Assigns the plant.
func assign_plant(
	slot_index: int,
	plant_data: PlantData
) -> bool:
	if plant_data == null:
		_emit_legacy_assignment_failed(
			REASON_INVALID_PLANT,
			null,
			slot_index
		)
		return false

	return assign_item(
		slot_index,
		plant_data.seed_item_id
	)


# Removes the plant.
func remove_plant(plant_data: PlantData) -> bool:
	if plant_data == null:
		return false

	return remove_item(plant_data.seed_item_id)


# Clears the slot.
func clear_slot(slot_index: int) -> bool:
	if not _is_valid_slot(slot_index):
		_emit_item_assignment_failed(
			REASON_INVALID_SLOT,
			&"",
			slot_index
		)
		return false

	var previous_id: StringName = _slots[slot_index]

	if previous_id == &"":
		return true

	var previous_plant: PlantData = (
		ItemCatalogSystem.get_plant_for_item(
			previous_id
		)
	)

	_slots[slot_index] = &""
	_emit_slot_changed(slot_index)

	if (
		previous_plant != null
		and PlantSelectionSystem.is_selected(previous_plant)
	):
		PlantSelectionSystem.deselect_plant()

	if debug_log:
		print(
			"[HotbarSystem] cleared slot=",
			slot_index,
			" item_id=",
			String(previous_id)
		)

	return true


# Returns the assignment IDs.
func get_assignment_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for item_id: StringName in _slots:
		result.append(item_id)

	return result


# Checks whether an item can be assigned to the hotbar.
func _is_item_assignable(item_id: StringName) -> bool:
	var item_data: ItemData = (
		ItemCatalogSystem.get_item(item_id)
	)

	if item_data == null or not item_data.hotbar_allowed:
		return false

	var plant_data: PlantData = (
		item_data.linked_plant_data
	)

	if plant_data != null:
		return PlantSelectionSystem.is_plant_available(
			plant_data
		)

	return true


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


# Emits the item assignment failed.
func _emit_item_assignment_failed(
	reason: String,
	item_id: StringName,
	slot_index: int
) -> void:
	item_assignment_failed.emit(
		reason,
		item_id,
		slot_index
	)

	var plant_data: PlantData = (
		ItemCatalogSystem.get_plant_for_item(item_id)
	)

	assignment_failed.emit(
		reason,
		plant_data,
		slot_index
	)

	if debug_log:
		print(
			"[HotbarSystem] assignment failed reason=",
			reason,
			" item_id=",
			String(item_id),
			" slot=",
			slot_index,
			" assignments=",
			get_assignment_ids()
		)


# Emits the legacy assignment failed.
func _emit_legacy_assignment_failed(
	reason: String,
	plant_data: PlantData,
	slot_index: int
) -> void:
	assignment_failed.emit(
		reason,
		plant_data,
		slot_index
	)

	if debug_log:
		print(
			"[HotbarSystem] assignment failed reason=",
			reason,
			" plant=",
			plant_data.display_name if plant_data != null else "NONE",
			" slot=",
			slot_index
		)


# Checks whether the requested slot index is valid.
func _is_valid_slot(slot_index: int) -> bool:
	return slot_index >= 0 and slot_index < SLOT_COUNT
