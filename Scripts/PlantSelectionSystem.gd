extends Node

# Announces the selected plant or a cleared selection.
signal selection_changed(
	plant_data: PlantData,
	index: int
)


# Announces changes to the plants available for inventory and hotbar use.
signal available_plants_changed(
	plants: Array[PlantData]
)


# Plant resources available in the alpha version.
const LILY_DATA: PlantData = preload("res://Data/Lily.tres")
const CACTUS_DATA: PlantData = preload("res://Data/Cactus.tres")


@export_category("Debug Logging")

# Enables plant selection operation logging.
@export var debug_log: bool = false


# Stores every plant definition known by the alpha version.
var all_plants: Array[PlantData] = [
	LILY_DATA,
	CACTUS_DATA
]

# Stores only permanently unlocked plant definitions.
var available_plants: Array[PlantData] = []

# Stores the active plant index or -1 when deselected.
var current_index: int = -1

# Stores the active plant definition or null when deselected.
var current_plant_data: PlantData = null


# Initializes with no selected plant and follows progression unlocks.
func _ready() -> void:
	if all_plants.is_empty():
		push_error("[PlantSelection] No plant resources configured.")
		return

	if not ProgressionSystem.plant_unlock_changed.is_connected(
		_on_plant_unlock_changed
	):
		ProgressionSystem.plant_unlock_changed.connect(
			_on_plant_unlock_changed
		)

	if not ProgressionSystem.progression_reset.is_connected(
		_on_progression_reset
	):
		ProgressionSystem.progression_reset.connect(
			_on_progression_reset
		)

	current_index = -1
	current_plant_data = null
	_refresh_available_plants()

	if debug_log:
		print(
			"[PlantSelection] ready plant=NONE index=-1 available=",
			_get_available_ids()
		)


# Returns the complete plant catalog, including locked plants.
func get_all_plants() -> Array[PlantData]:
	var result: Array[PlantData] = []

	for plant_data: PlantData in all_plants:
		result.append(plant_data)

	return result


# Returns one plant definition by seed item identifier.
func get_plant_by_id(plant_id: StringName) -> PlantData:
	for plant_data: PlantData in all_plants:
		if (
			plant_data != null
			and plant_data.seed_item_id == plant_id
		):
			return plant_data

	return null


# Returns whether one plant definition is permanently unlocked.
func is_plant_available(plant_data: PlantData) -> bool:
	if plant_data == null:
		return false

	return ProgressionSystem.is_plant_unlocked(
		plant_data.seed_item_id
	)


# Returns the currently selected plant definition.
func get_current_plant() -> PlantData:
	return current_plant_data


# Returns the list index of a plant definition.
func get_index_for_plant(plant_data: PlantData) -> int:
	if plant_data == null:
		return -1

	for index in range(available_plants.size()):
		var candidate := available_plants[index]

		if candidate.seed_item_id == plant_data.seed_item_id:
			return index

	return -1


# Returns whether the given plant is currently selected.
func is_selected(plant_data: PlantData) -> bool:
	if plant_data == null or current_plant_data == null:
		return false

	return (
		current_plant_data.seed_item_id
		== plant_data.seed_item_id
	)


# Selects a plant by list index.
func set_plant_by_index(index: int) -> bool:
	if index < 0 or index >= available_plants.size():
		return false

	return set_plant(available_plants[index])


# Selects a plant definition.
func set_plant(plant_data: PlantData) -> bool:
	if not is_plant_available(plant_data):
		if debug_log:
			print(
				"[PlantSelection] rejected locked plant=",
				plant_data.display_name if plant_data != null else "NONE"
			)
		return false

	var resolved_index := get_index_for_plant(plant_data)

	if resolved_index < 0:
		return false

	if is_selected(plant_data):
		return true

	current_index = resolved_index
	current_plant_data = available_plants[current_index]
	selection_changed.emit(current_plant_data, current_index)

	if debug_log:
		print(
			"[PlantSelection] selected plant=",
			current_plant_data.display_name,
			" index=",
			current_index,
			" seed=",
			String(current_plant_data.seed_item_id),
			" available=",
			InventorySystem.get_amount(
				current_plant_data.seed_item_id
			)
		)

	return true


# Clears the current plant selection.
func deselect_plant() -> bool:
	if current_plant_data == null:
		return false

	var previous_name := current_plant_data.display_name
	current_index = -1
	current_plant_data = null
	selection_changed.emit(null, -1)

	if debug_log:
		print(
			"[PlantSelection] deselected plant=",
			previous_name
		)

	return true


# Selects or deselects one plant.
func toggle_plant(plant_data: PlantData) -> bool:
	if is_selected(plant_data):
		return deselect_plant()

	return set_plant(plant_data)


# Rebuilds the selectable list from progression unlock state.
func _refresh_available_plants() -> void:
	available_plants.clear()

	for plant_data: PlantData in all_plants:
		if (
			plant_data != null
			and ProgressionSystem.is_plant_unlocked(
				plant_data.seed_item_id
			)
		):
			available_plants.append(plant_data)

	if (
		current_plant_data != null
		and not is_plant_available(current_plant_data)
	):
		current_index = -1
		current_plant_data = null
		selection_changed.emit(null, -1)
	elif current_plant_data != null:
		current_index = get_index_for_plant(
			current_plant_data
		)

	available_plants_changed.emit(
		get_all_available_plants()
	)

	if debug_log:
		print(
			"[PlantSelection] available plants=",
			_get_available_ids()
		)


# Returns a protected copy of the selectable plant list.
func get_all_available_plants() -> Array[PlantData]:
	var result: Array[PlantData] = []

	for plant_data: PlantData in available_plants:
		result.append(plant_data)

	return result


# Refreshes availability after one plant unlock.
func _on_plant_unlock_changed(
	_plant_id: StringName,
	_unlocked: bool
) -> void:
	_refresh_available_plants()


# Refreshes availability after a complete progression reset.
func _on_progression_reset() -> void:
	_refresh_available_plants()


# Returns plant identifiers for detailed debug logging.
func _get_available_ids() -> Array[StringName]:
	var result: Array[StringName] = []

	for plant_data: PlantData in available_plants:
		if plant_data != null:
			result.append(plant_data.seed_item_id)

	return result


# Selects the next plant definition.
func next_plant() -> void:
	if available_plants.is_empty():
		return

	if current_index < 0:
		set_plant_by_index(0)
	else:
		set_plant_by_index(
			posmod(current_index + 1, available_plants.size())
		)


# Selects the previous plant definition.
func previous_plant() -> void:
	if available_plants.is_empty():
		return

	if current_index < 0:
		set_plant_by_index(available_plants.size() - 1)
	else:
		set_plant_by_index(
			posmod(current_index - 1, available_plants.size())
		)
