extends Node

# Seed storage backend for both the original map storage corner and
# player-built Seed Storage sacks. This remains the single ChestSystem autoload.

signal chest_opened(station_id: StringName)
signal chest_closed(station_id: StringName)
signal chest_contents_changed(station_id: StringName)


const CHEST_SLOT_COUNT: int = 8

const CHEST_UI_SLOT_SIZE: Vector2 = Vector2(58.0, 58.0)
const CHEST_UI_ICON_SIZE: Vector2 = Vector2(42.0, 42.0)
const CHEST_UI_SLOT_GAP: float = 4.0

const BUILD_ID_SEED_STORAGE: StringName = &"seed_storage"
const MAIN_STATION_ID: StringName = &"seed_storage_main"

# Original-map sack/pot cells inside the fenced storage corner.
const MAIN_STORAGE_PROP_CELLS: Array[Vector2i] = [
	Vector2i(-16, 26),
	Vector2i(-13, 26),
	Vector2i(-12, 26),
	Vector2i(-16, 27),
	Vector2i(-15, 27),
	Vector2i(-14, 27),
	Vector2i(-13, 27),
	Vector2i(-12, 27)
]

const EMPTY_SLOT: Dictionary = {
	"item_id": "",
	"amount": 0
}


@export_category("Map")

@export var storage_layer_name: StringName = &"Intersections"


@export_category("Interaction")

@export_range(32.0, 160.0, 1.0)
var interaction_range_pixels: float = 92.0

@export var prompt_world_offset: Vector2 = Vector2(0.0, -28.0)

@export_range(0.0, 12.0, 0.5)
var prompt_bob_pixels: float = 3.0

@export_range(0.5, 6.0, 0.1)
var prompt_bob_speed: float = 2.2

@export_range(0.0, 1.0, 0.01)
var prompt_alpha_min: float = 0.58

@export_range(0.0, 1.0, 0.01)
var prompt_alpha_max: float = 0.92


@export_category("Debug Logging")

@export var debug_log: bool = false


var _tilemap: TileMap
var _player: CharacterBody2D
var _configured: bool = false
var _storage_layer: int = -1

# station_id -> {
#   "id": StringName,
#   "cells": Array[Vector2i],
#   "build_cell": Vector2i or null
# }
var _stations: Dictionary = {}

# station_id -> Array[Dictionary]
var _storage: Dictionary = {}

var _nearby_station_id: StringName = &""
var _open_station_id: StringName = &""
var _is_open: bool = false

var _previous_tree_paused: bool = false
var _previous_mouse_mode: int = Input.MOUSE_MODE_HIDDEN

var _ui_layer: CanvasLayer
var _backdrop: ColorRect
var _panel: Panel
var _prompt_label: Label
var _inventory_buttons: Array[Button] = []
var _storage_buttons: Array[Button] = []
var _inventory_icons: Array[TextureRect] = []
var _storage_icons: Array[TextureRect] = []
var _inventory_amount_labels: Array[Label] = []
var _storage_amount_labels: Array[Label] = []
var _inventory_number_labels: Array[Label] = []
var _storage_number_labels: Array[Label] = []


# Initializes this system when the node becomes ready.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_ui()

	if not BuildSystem.build_cell_placed.is_connected(
		_on_build_cell_changed
	):
		BuildSystem.build_cell_placed.connect(
			_on_build_cell_changed
		)

	if not BuildSystem.build_cell_removed.is_connected(
		_on_build_cell_changed
	):
		BuildSystem.build_cell_removed.connect(
			_on_build_cell_changed
		)

	if not BuildSystem.build_world_rebuilt.is_connected(
		_on_build_world_rebuilt
	):
		BuildSystem.build_world_rebuilt.connect(
			_on_build_world_rebuilt
		)

	if not InventorySystem.item_amount_changed.is_connected(
		_on_inventory_item_amount_changed
	):
		InventorySystem.item_amount_changed.connect(
			_on_inventory_item_amount_changed
		)

	if not InventoryLayoutSystem.item_slot_changed.is_connected(
		_on_inventory_layout_changed
	):
		InventoryLayoutSystem.item_slot_changed.connect(
			_on_inventory_layout_changed
		)

	if not InventoryLayoutSystem.layout_reset.is_connected(
		_on_inventory_layout_reset
	):
		InventoryLayoutSystem.layout_reset.connect(
			_on_inventory_layout_reset
		)

	if debug_log:
		print(
			"[ChestSystem] ready mode=seed_storage slots=",
			CHEST_SLOT_COUNT,
			" range=",
			interaction_range_pixels
		)


# Connects this system to the current world references.
func configure(
	tilemap: TileMap,
	player: CharacterBody2D
) -> void:
	if tilemap == null or player == null:
		push_error(
			"[ChestSystem] configure received missing world references."
		)
		return

	if _tilemap != null and _tilemap != tilemap:
		unconfigure(_tilemap)

	_tilemap = tilemap
	_player = player
	_storage_layer = _find_layer_by_name(
		storage_layer_name
	)

	if _storage_layer < 0:
		push_error(
			"[ChestSystem] TileMap layer not found: %s"
			% String(storage_layer_name)
		)
		return

	_configured = true

	_validate_original_storage_corner()
	_rebuild_stations_from_world()
	_refresh_prompt()

	if debug_log:
		print(
			"[ChestSystem] configured mode=seed_storage layer=",
			_storage_layer,
			" stations=",
			_stations.size()
		)


# Disconnects this system from the current world references.
func unconfigure(tilemap: TileMap) -> void:
	if _tilemap != tilemap:
		return

	if _is_open:
		close_chest()

	_tilemap = null
	_player = null
	_storage_layer = -1
	_configured = false
	_stations.clear()
	_nearby_station_id = &""
	_prompt_label.visible = false

	if debug_log:
		print("[ChestSystem] unconfigured")


# Updates this system every frame.
func _process(_delta: float) -> void:
	if not _configured:
		_prompt_label.visible = false
		return

	if _is_open:
		_prompt_label.visible = false
		return

	if (
		get_tree().paused
		or BuildSystem.is_active()
	):
		_nearby_station_id = &""
		_prompt_label.visible = false
		return

	_find_nearby_station()
	_refresh_prompt()


# Handles direct player input.
func _input(event: InputEvent) -> void:
	if _is_open:
		if (
			event.is_action_pressed("interact")
			or (
				event is InputEventKey
				and (event as InputEventKey).pressed
				and not (event as InputEventKey).echo
				and (event as InputEventKey).keycode == KEY_ESCAPE
			)
		):
			close_chest()
			get_viewport().set_input_as_handled()
		return

	if (
		not _configured
		or get_tree().paused
		or BuildSystem.is_active()
		or Input.is_action_pressed("aim_mode")
	):
		return

	if (
		event.is_action_pressed("interact")
		and _nearby_station_id != &""
	):
		open_chest(_nearby_station_id)
		get_viewport().set_input_as_handled()


# Opens the chest.
func open_chest(
	station_id: StringName = &""
) -> bool:
	var resolved_id: StringName = (
		_nearby_station_id
		if station_id == &""
		else station_id
	)

	if (
		not _configured
		or _is_open
		or resolved_id == &""
		or not _stations.has(resolved_id)
	):
		return false

	_ensure_storage(resolved_id)

	_open_station_id = resolved_id
	_is_open = true
	_previous_tree_paused = get_tree().paused
	_previous_mouse_mode = Input.get_mouse_mode()

	get_tree().paused = true
	Input.set_mouse_mode(
		Input.MOUSE_MODE_VISIBLE
	)

	_backdrop.visible = true
	_panel.visible = true
	_prompt_label.visible = false

	_refresh_ui()
	chest_opened.emit(resolved_id)

	if debug_log:
		print(
			"[ChestSystem] opened station=",
			resolved_id,
			" contents=",
			_storage_debug_string(resolved_id)
		)

	return true


# Closes the chest.
func close_chest() -> void:
	if not _is_open:
		return

	var closed_id: StringName = _open_station_id

	_is_open = false
	_open_station_id = &""
	_backdrop.visible = false
	_panel.visible = false

	get_tree().paused = _previous_tree_paused
	Input.set_mouse_mode(
		_previous_mouse_mode
	)

	chest_closed.emit(closed_id)

	if debug_log:
		print(
			"[ChestSystem] closed station=",
			closed_id
		)


# Checks whether the Storage interface is open.
func is_chest_open() -> bool:
	return _is_open


# BuildSystem calls this before replacing/demolishing a player-built storage.
func is_chest_empty(
	cell: Vector2i = Vector2i.ZERO
) -> bool:
	var station_id: StringName = _station_id_for_cell(cell)

	if station_id == &"" or not _storage.has(station_id):
		return true

	for slot_variant: Variant in _storage[station_id]:
		if typeof(slot_variant) != TYPE_DICTIONARY:
			continue

		if int(
			(slot_variant as Dictionary).get(
				"amount",
				0
			)
		) > 0:
			return false

	return true


# Returns the serializable state of this system.
func get_save_state() -> Array[Dictionary]:
	if not _configured:
		return []

	var result: Array[Dictionary] = []

	for station_id_variant: Variant in _stations.keys():
		var station_id := StringName(
			String(station_id_variant)
		)
		_ensure_storage(station_id)

		var station: Dictionary = _stations[station_id]
		var entry: Dictionary = {
			"station_id": String(station_id),
			"slots": []
		}

		var build_cell_variant: Variant = (
			station.get("build_cell")
		)

		if build_cell_variant is Vector2i:
			var build_cell: Vector2i = (
				build_cell_variant
			)
			entry["x"] = build_cell.x
			entry["y"] = build_cell.y

		var saved_slots: Array = []

		for slot_variant: Variant in _storage[station_id]:
			if typeof(slot_variant) != TYPE_DICTIONARY:
				saved_slots.append(
					EMPTY_SLOT.duplicate(true)
				)
				continue

			var slot: Dictionary = slot_variant
			saved_slots.append({
				"item_id": String(
					slot.get("item_id", "")
				),
				"amount": maxi(
					int(slot.get("amount", 0)),
					0
				)
			})

		entry["slots"] = saved_slots
		result.append(entry)

	return result


# Restores this system from saved data.
func load_save_state(entries: Array) -> void:
	if not _configured:
		return

	_rebuild_stations_from_world()

	var previous_storage: Dictionary = _storage.duplicate(
		true
	)
	_storage.clear()

	for station_id_variant: Variant in _stations.keys():
		var station_id := StringName(
			String(station_id_variant)
		)

		if previous_storage.has(station_id):
			_storage[station_id] = (
				previous_storage[station_id]
			)
		else:
			_storage[station_id] = (
				_make_empty_slots()
			)

	var legacy_entries: Array[Dictionary] = []

	for entry_variant: Variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue

		var entry: Dictionary = entry_variant
		var station_id := StringName(
			String(
				entry.get(
					"station_id",
					""
				)
			)
		)

		if (
			station_id == &""
			and entry.has("x")
			and entry.has("y")
		):
			station_id = _build_station_id(
				Vector2i(
					int(entry.get("x", 0)),
					int(entry.get("y", 0))
				)
			)

		if not _stations.has(station_id):
			legacy_entries.append(entry)
			continue

		_storage[station_id] = (
			_slots_from_save_entry(entry)
		)

	# Migration fallback from the previously proposed generic buildable chest:
	# if its build object no longer exists, keep its seed contents by merging
	# them into the original map storage rather than silently discarding them.
	for entry: Dictionary in legacy_entries:
		_merge_legacy_seed_slots_into_main(
			_slots_from_save_entry(entry)
		)

	if _is_open:
		if not _stations.has(_open_station_id):
			close_chest()
		else:
			_refresh_ui()

	if debug_log:
		print(
			"[ChestSystem] save state loaded stations=",
			_storage.size(),
			" state=",
			_storage_debug_all()
		)


# Rebuilds the stations from world.
func _rebuild_stations_from_world() -> void:
	if not _configured:
		return

	var previous_storage: Dictionary = _storage.duplicate(
		true
	)
	_stations.clear()

	_stations[MAIN_STATION_ID] = {
		"id": MAIN_STATION_ID,
		"cells": MAIN_STORAGE_PROP_CELLS.duplicate(),
		"build_cell": null
	}

	var built_cells: Dictionary = (
		BuildSystem.get_player_built_cells()
	)

	for cell_variant: Variant in built_cells.keys():
		var cell: Vector2i = cell_variant
		var record_variant: Variant = built_cells[cell]

		if typeof(record_variant) != TYPE_DICTIONARY:
			continue

		var record: Dictionary = record_variant
		var object_id := StringName(
			record.get("object_build_id", &"")
		)

		if object_id != BUILD_ID_SEED_STORAGE:
			continue

		var station_id: StringName = (
			_build_station_id(cell)
		)
		var station_cells: Array[Vector2i] = [cell]
		var object_cells_variant: Variant = record.get(
			"object_cells",
			[]
		)

		if typeof(object_cells_variant) == TYPE_ARRAY:
			station_cells.clear()

			for object_cell_variant: Variant in object_cells_variant:
				if object_cell_variant is Vector2i:
					station_cells.append(object_cell_variant)

		if station_cells.is_empty():
			station_cells = [cell]

		_stations[station_id] = {
			"id": station_id,
			"cells": station_cells,
			"build_cell": cell
		}

	_storage.clear()

	for station_id_variant: Variant in _stations.keys():
		var station_id := StringName(
			String(station_id_variant)
		)

		if previous_storage.has(station_id):
			_storage[station_id] = (
				previous_storage[station_id]
			)
		else:
			_storage[station_id] = (
				_make_empty_slots()
			)

	if (
		_is_open
		and not _stations.has(_open_station_id)
	):
		close_chest()

	if debug_log:
		print(
			"[ChestSystem] stations rebuilt count=",
			_stations.size(),
			" ids=",
			_stations.keys()
		)


# Builds a stable station ID from a world cell.
func _station_id_for_cell(cell: Vector2i) -> StringName:
	var direct_id: StringName = _build_station_id(cell)

	if _stations.has(direct_id):
		return direct_id

	for station_id_variant: Variant in _stations.keys():
		var station_id := StringName(
			String(station_id_variant)
		)
		var station: Dictionary = _stations[station_id]
		var cells_variant: Variant = station.get(
			"cells",
			[]
		)

		if typeof(cells_variant) != TYPE_ARRAY:
			continue

		for station_cell_variant: Variant in cells_variant:
			if (
				station_cell_variant is Vector2i
				and station_cell_variant == cell
			):
				return station_id

	return &""


# Finds the nearby station.
func _find_nearby_station() -> void:
	_nearby_station_id = &""

	if _player == null or _tilemap == null:
		return

	var best_distance: float = INF

	for station_id_variant: Variant in _stations.keys():
		var station_id := StringName(
			String(station_id_variant)
		)
		var distance: float = _distance_to_station(
			station_id
		)

		if (
			distance <= interaction_range_pixels
			and distance < best_distance
		):
			best_distance = distance
			_nearby_station_id = station_id


# Calculates the player distance to an interaction station.
func _distance_to_station(
	station_id: StringName
) -> float:
	if (
		_player == null
		or _tilemap == null
		or not _stations.has(station_id)
	):
		return INF

	var station: Dictionary = _stations[station_id]
	var cells_variant: Variant = station.get(
		"cells",
		[]
	)

	if typeof(cells_variant) != TYPE_ARRAY:
		return INF

	var best_distance: float = INF

	for cell_variant: Variant in cells_variant:
		if not (cell_variant is Vector2i):
			continue

		var cell: Vector2i = cell_variant
		var world_position: Vector2 = (
			_tilemap.to_global(
				_tilemap.map_to_local(cell)
			)
		)
		best_distance = minf(
			best_distance,
			_player.global_position.distance_to(
				world_position
			)
		)

	return best_distance


# Builds the station ID.
func _build_station_id(
	cell: Vector2i
) -> StringName:
	return StringName(
		"seed_storage_build_%d_%d"
		% [cell.x, cell.y]
	)


# Deposits the from inventory slot.
func _deposit_from_inventory_slot(
	inventory_slot_index: int
) -> void:
	if not _is_open:
		return

	var item_id: StringName = (
		InventoryLayoutSystem.get_item_id(
			inventory_slot_index
		)
	)

	if (
		item_id == &""
		or not _is_seed_item(item_id)
	):
		return

	var available: int = (
		InventorySystem.get_amount(item_id)
	)

	if available <= 0:
		return

	var transfer_amount: int = (
		available
		if Input.is_physical_key_pressed(KEY_SHIFT)
		else 1
	)

	var deposited: int = _deposit_seed(
		_open_station_id,
		item_id,
		transfer_amount
	)

	if deposited <= 0:
		return

	if not InventorySystem.remove_item(
		item_id,
		deposited
	):
		_withdraw_internal(
			_open_station_id,
			item_id,
			deposited
		)
		return

	chest_contents_changed.emit(
		_open_station_id
	)
	_refresh_ui()

	if debug_log:
		print(
			"[ChestSystem] seed deposit station=",
			_open_station_id,
			" item=",
			item_id,
			" amount=",
			deposited,
			" contents=",
			_storage_debug_string(
				_open_station_id
			)
		)


# Withdraws the from storage slot.
func _withdraw_from_storage_slot(
	storage_slot_index: int
) -> void:
	if not _is_open:
		return

	_ensure_storage(_open_station_id)
	var slots: Array = (
		_storage[_open_station_id]
	)

	if (
		storage_slot_index < 0
		or storage_slot_index >= slots.size()
		or typeof(slots[storage_slot_index])
		!= TYPE_DICTIONARY
	):
		return

	var slot: Dictionary = slots[storage_slot_index]
	var item_id := StringName(
		String(slot.get("item_id", ""))
	)
	var available: int = int(
		slot.get("amount", 0)
	)

	if item_id == &"" or available <= 0:
		return

	var requested: int = (
		available
		if Input.is_physical_key_pressed(KEY_SHIFT)
		else 1
	)

	var item_data: ItemData = (
		ItemCatalogSystem.get_item(item_id)
	)
	var inventory_capacity: int = requested

	if item_data != null:
		inventory_capacity = maxi(
			item_data.stack_limit
			- InventorySystem.get_amount(item_id),
			0
		)

	var transfer_amount: int = mini(
		requested,
		inventory_capacity
	)

	if transfer_amount <= 0:
		return

	if not InventorySystem.add_item(
		item_id,
		transfer_amount
	):
		return

	var remaining: int = available - transfer_amount

	if remaining <= 0:
		slots[storage_slot_index] = (
			EMPTY_SLOT.duplicate(true)
		)
	else:
		slot["amount"] = remaining
		slots[storage_slot_index] = slot

	_storage[_open_station_id] = slots

	InventoryLayoutSystem.ensure_item_present(
		item_id
	)
	chest_contents_changed.emit(
		_open_station_id
	)
	_refresh_ui()

	if debug_log:
		print(
			"[ChestSystem] seed withdraw station=",
			_open_station_id,
			" item=",
			item_id,
			" amount=",
			transfer_amount,
			" contents=",
			_storage_debug_string(
				_open_station_id
			)
		)


# Deposits the seed.
func _deposit_seed(
	station_id: StringName,
	item_id: StringName,
	requested_amount: int
) -> int:
	if (
		requested_amount <= 0
		or not _is_seed_item(item_id)
	):
		return 0

	_ensure_storage(station_id)
	var slots: Array = _storage[station_id]
	var item_data: ItemData = (
		ItemCatalogSystem.get_item(item_id)
	)
	var stack_limit: int = (
		item_data.stack_limit
		if item_data != null
		else 9999
	)

	for index: int in range(slots.size()):
		if typeof(slots[index]) != TYPE_DICTIONARY:
			continue

		var slot: Dictionary = slots[index]

		if StringName(
			String(slot.get("item_id", ""))
		) != item_id:
			continue

		var current: int = int(
			slot.get("amount", 0)
		)
		var moved: int = mini(
			requested_amount,
			maxi(stack_limit - current, 0)
		)

		if moved <= 0:
			return 0

		slot["amount"] = current + moved
		slots[index] = slot
		_storage[station_id] = slots
		return moved

	for index: int in range(slots.size()):
		var slot_variant: Variant = slots[index]

		if (
			typeof(slot_variant) == TYPE_DICTIONARY
			and int(
				(slot_variant as Dictionary).get(
					"amount",
					0
				)
			) > 0
		):
			continue

		var moved: int = mini(
			requested_amount,
			stack_limit
		)
		slots[index] = {
			"item_id": String(item_id),
			"amount": moved
		}
		_storage[station_id] = slots
		return moved

	return 0


# Withdraws the internal.
func _withdraw_internal(
	station_id: StringName,
	item_id: StringName,
	amount: int
) -> int:
	if (
		amount <= 0
		or not _storage.has(station_id)
	):
		return 0

	var slots: Array = _storage[station_id]

	for index: int in range(slots.size()):
		if typeof(slots[index]) != TYPE_DICTIONARY:
			continue

		var slot: Dictionary = slots[index]

		if StringName(
			String(slot.get("item_id", ""))
		) != item_id:
			continue

		var current: int = int(
			slot.get("amount", 0)
		)
		var moved: int = mini(
			current,
			amount
		)
		var remaining: int = current - moved

		if remaining <= 0:
			slots[index] = (
				EMPTY_SLOT.duplicate(true)
			)
		else:
			slot["amount"] = remaining
			slots[index] = slot

		_storage[station_id] = slots
		return moved

	return 0


# Ensures the storage exists and is ready to use.
func _ensure_storage(
	station_id: StringName
) -> void:
	if _storage.has(station_id):
		return

	_storage[station_id] = _make_empty_slots()


# Creates the empty slots.
func _make_empty_slots() -> Array:
	var result: Array = []

	for _index: int in range(
		CHEST_SLOT_COUNT
	):
		result.append(
			EMPTY_SLOT.duplicate(true)
		)

	return result


# Converts saved slot data back to runtime storage slots.
func _slots_from_save_entry(
	entry: Dictionary
) -> Array:
	var result: Array = _make_empty_slots()
	var slots_variant: Variant = entry.get(
		"slots",
		[]
	)

	if typeof(slots_variant) != TYPE_ARRAY:
		return result

	var saved_slots: Array = slots_variant
	var count: int = mini(
		saved_slots.size(),
		CHEST_SLOT_COUNT
	)

	for index: int in range(count):
		if (
			typeof(saved_slots[index])
			!= TYPE_DICTIONARY
		):
			continue

		var saved_slot: Dictionary = (
			saved_slots[index]
		)
		var item_id := StringName(
			String(
				saved_slot.get(
					"item_id",
					""
				)
			)
		)
		var amount: int = maxi(
			int(
				saved_slot.get(
					"amount",
					0
				)
			),
			0
		)

		if (
			item_id == &""
			or amount <= 0
			or not _is_seed_item(item_id)
		):
			continue

		var item_data: ItemData = (
			ItemCatalogSystem.get_item(item_id)
		)

		if item_data != null:
			amount = mini(
				amount,
				item_data.stack_limit
			)

		result[index] = {
			"item_id": String(item_id),
			"amount": amount
		}

	return result


# Merges the legacy seed slots into main.
func _merge_legacy_seed_slots_into_main(
	legacy_slots: Array
) -> void:
	for slot_variant: Variant in legacy_slots:
		if typeof(slot_variant) != TYPE_DICTIONARY:
			continue

		var slot: Dictionary = slot_variant
		var item_id := StringName(
			String(slot.get("item_id", ""))
		)
		var amount: int = int(
			slot.get("amount", 0)
		)

		if (
			item_id == &""
			or amount <= 0
			or not _is_seed_item(item_id)
		):
			continue

		_deposit_seed(
			MAIN_STATION_ID,
			item_id,
			amount
		)


# Checks whether the item is a seed item.
func _is_seed_item(
	item_id: StringName
) -> bool:
	return ItemCatalogSystem.is_seed_item(
		item_id
	)


# Validates the original storage corner.
func _validate_original_storage_corner() -> void:
	var detected_props: int = 0

	for cell: Vector2i in MAIN_STORAGE_PROP_CELLS:
		if (
			_tilemap.get_cell_source_id(
				_storage_layer,
				cell
			)
			>= 0
		):
			detected_props += 1

	if detected_props <= 0:
		push_warning(
			"[ChestSystem] Original seed-storage props were not found at the expected map cells."
		)

	if debug_log:
		print(
			"[ChestSystem] seed storage corner props=",
			detected_props,
			"/",
			MAIN_STORAGE_PROP_CELLS.size()
		)


# Finds the layer by name.
func _find_layer_by_name(
	layer_name: StringName
) -> int:
	if _tilemap == null:
		return -1

	for layer_index: int in range(
		_tilemap.get_layers_count()
	):
		if StringName(
			_tilemap.get_layer_name(
				layer_index
			)
		) == layer_name:
			return layer_index

	return -1


# Creates the UI.
func _create_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "SeedStorageUI"
	_ui_layer.layer = 24
	add_child(_ui_layer)

	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	_backdrop.color = Color(
		0.0,
		0.0,
		0.0,
		0.58
	)
	_backdrop.mouse_filter = (
		Control.MOUSE_FILTER_STOP
	)
	_backdrop.visible = false
	_ui_layer.add_child(_backdrop)

	_panel = Panel.new()
	_panel.name = "SeedStoragePanel"
	_panel.set_anchors_preset(
		Control.PRESET_CENTER
	)
	_panel.position = Vector2(
		-278.0,
		-175.0
	)
	_panel.size = Vector2(
		556.0,
		350.0
	)
	_panel.mouse_filter = (
		Control.MOUSE_FILTER_STOP
	)
	_panel.visible = false
	_panel.add_theme_stylebox_override(
		"panel",
		_create_chest_panel_style()
	)
	_ui_layer.add_child(_panel)

	var title_label := Label.new()
	title_label.position = Vector2(
		20.0,
		14.0
	)
	title_label.size = Vector2(
		516.0,
		28.0
	)
	title_label.text = "SEED STORAGE"
	title_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	title_label.add_theme_font_size_override(
		"font_size",
		18
	)
	title_label.add_theme_color_override(
		"font_color",
		Color(0.90, 0.94, 0.88, 1.0)
	)
	_panel.add_child(title_label)

	var storage_label := Label.new()
	storage_label.position = Vector2(
		26.0,
		56.0
	)
	storage_label.size = Vector2(
		504.0,
		20.0
	)
	storage_label.text = "SEED STORAGE"
	storage_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_LEFT
	)
	storage_label.add_theme_font_size_override(
		"font_size",
		12
	)
	storage_label.add_theme_color_override(
		"font_color",
		Color(0.70, 0.76, 0.68, 1.0)
	)
	_panel.add_child(storage_label)

	var storage_panel := PanelContainer.new()
	storage_panel.name = "StorageSlotsPanel"
	storage_panel.position = Vector2(
		24.0,
		78.0
	)
	storage_panel.size = Vector2(
		508.0,
		72.0
	)
	storage_panel.mouse_filter = (
		Control.MOUSE_FILTER_PASS
	)
	storage_panel.add_theme_stylebox_override(
		"panel",
		_create_hotbar_background()
	)
	_panel.add_child(storage_panel)

	var storage_margin := MarginContainer.new()
	storage_margin.add_theme_constant_override(
		"margin_left",
		6
	)
	storage_margin.add_theme_constant_override(
		"margin_top",
		6
	)
	storage_margin.add_theme_constant_override(
		"margin_right",
		6
	)
	storage_margin.add_theme_constant_override(
		"margin_bottom",
		6
	)
	storage_panel.add_child(storage_margin)

	var storage_row := HBoxContainer.new()
	storage_row.name = "StorageSlots"
	storage_row.add_theme_constant_override(
		"separation",
		int(CHEST_UI_SLOT_GAP)
	)
	storage_margin.add_child(storage_row)

	var inventory_label := Label.new()
	inventory_label.position = Vector2(
		26.0,
		170.0
	)
	inventory_label.size = Vector2(
		504.0,
		20.0
	)
	inventory_label.text = "PLAYER INVENTORY"
	inventory_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_LEFT
	)
	inventory_label.add_theme_font_size_override(
		"font_size",
		12
	)
	inventory_label.add_theme_color_override(
		"font_color",
		Color(0.70, 0.76, 0.68, 1.0)
	)
	_panel.add_child(inventory_label)

	var inventory_panel := PanelContainer.new()
	inventory_panel.name = "InventorySlotsPanel"
	inventory_panel.position = Vector2(
		24.0,
		192.0
	)
	inventory_panel.size = Vector2(
		508.0,
		72.0
	)
	inventory_panel.mouse_filter = (
		Control.MOUSE_FILTER_PASS
	)
	inventory_panel.add_theme_stylebox_override(
		"panel",
		_create_hotbar_background()
	)
	_panel.add_child(inventory_panel)

	var inventory_margin := MarginContainer.new()
	inventory_margin.add_theme_constant_override(
		"margin_left",
		6
	)
	inventory_margin.add_theme_constant_override(
		"margin_top",
		6
	)
	inventory_margin.add_theme_constant_override(
		"margin_right",
		6
	)
	inventory_margin.add_theme_constant_override(
		"margin_bottom",
		6
	)
	inventory_panel.add_child(inventory_margin)

	var inventory_row := HBoxContainer.new()
	inventory_row.name = "InventorySlots"
	inventory_row.add_theme_constant_override(
		"separation",
		int(CHEST_UI_SLOT_GAP)
	)
	inventory_margin.add_child(inventory_row)

	_inventory_buttons.clear()
	_storage_buttons.clear()
	_inventory_icons.clear()
	_storage_icons.clear()
	_inventory_amount_labels.clear()
	_storage_amount_labels.clear()
	_inventory_number_labels.clear()
	_storage_number_labels.clear()

	for index: int in range(CHEST_SLOT_COUNT):
		var storage_slot: Dictionary = _create_chest_slot(
			index,
			false
		)
		storage_row.add_child(
			storage_slot["button"]
		)
		_storage_buttons.append(
			storage_slot["button"]
		)
		_storage_icons.append(
			storage_slot["icon"]
		)
		_storage_amount_labels.append(
			storage_slot["amount_label"]
		)
		_storage_number_labels.append(
			storage_slot["number_label"]
		)
		_storage_buttons[index].pressed.connect(
			_withdraw_from_storage_slot.bind(
				index
			)
		)

		var inventory_slot: Dictionary = _create_chest_slot(
			index,
			true
		)
		inventory_row.add_child(
			inventory_slot["button"]
		)
		_inventory_buttons.append(
			inventory_slot["button"]
		)
		_inventory_icons.append(
			inventory_slot["icon"]
		)
		_inventory_amount_labels.append(
			inventory_slot["amount_label"]
		)
		_inventory_number_labels.append(
			inventory_slot["number_label"]
		)
		_inventory_buttons[index].pressed.connect(
			_deposit_from_inventory_slot.bind(
				index
			)
		)

	var hint_label := Label.new()
	hint_label.position = Vector2(
		24.0,
		288.0
	)
	hint_label.size = Vector2(
		508.0,
		24.0
	)
	hint_label.text = (
		"Click: move 1     Shift + Click: move stack     E / Esc: close"
	)
	hint_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	hint_label.add_theme_font_size_override(
		"font_size",
		11
	)
	hint_label.add_theme_color_override(
		"font_color",
		Color(0.62, 0.68, 0.60, 1.0)
	)
	_panel.add_child(hint_label)

	var close_button := Button.new()
	close_button.position = Vector2(
		510.0,
		12.0
	)
	close_button.size = Vector2(
		30.0,
		28.0
	)
	close_button.text = "X"
	close_button.focus_mode = (
		Control.FOCUS_NONE
	)
	close_button.add_theme_stylebox_override(
		"normal",
		_create_slot_style(
			false,
			false
		)
	)
	close_button.add_theme_stylebox_override(
		"hover",
		_create_slot_style(
			true,
			false
		)
	)
	close_button.add_theme_stylebox_override(
		"pressed",
		_create_slot_style(
			true,
			false
		)
	)
	close_button.pressed.connect(
		close_chest
	)
	_panel.add_child(close_button)

	_prompt_label = Label.new()
	_prompt_label.name = "SeedStorageWorldPrompt"
	_prompt_label.set_anchors_preset(
		Control.PRESET_TOP_LEFT
	)
	_prompt_label.position = Vector2.ZERO
	_prompt_label.custom_minimum_size = Vector2(
		28.0,
		28.0
	)
	_prompt_label.size = Vector2(
		28.0,
		28.0
	)
	_prompt_label.text = "E"
	_prompt_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_prompt_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)
	_prompt_label.add_theme_font_size_override(
		"font_size",
		17
	)
	_prompt_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.97, 0.76, 1.0)
	)
	_prompt_label.add_theme_color_override(
		"font_outline_color",
		Color(0.01, 0.015, 0.01, 0.95)
	)
	_prompt_label.add_theme_constant_override(
		"outline_size",
		3
	)
	_prompt_label.visible = false
	_prompt_label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	_ui_layer.add_child(_prompt_label)


# Creates the chest slot.
func _create_chest_slot(
	index: int,
	is_inventory_slot: bool
) -> Dictionary:
	var button := Button.new()
	button.name = (
		"InventorySlot%d" % (index + 1)
		if is_inventory_slot
		else "StorageSlot%d" % (index + 1)
	)
	button.custom_minimum_size = CHEST_UI_SLOT_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
	)
	button.text = ""

	var icon := TextureRect.new()
	icon.name = "ItemIcon"
	icon.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	icon.offset_left = (
		(CHEST_UI_SLOT_SIZE.x - CHEST_UI_ICON_SIZE.x)
		* 0.5
	)
	icon.offset_top = (
		(CHEST_UI_SLOT_SIZE.y - CHEST_UI_ICON_SIZE.y)
		* 0.5
	)
	icon.offset_right = -icon.offset_left
	icon.offset_bottom = -icon.offset_top
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)
	icon.texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST
	)
	icon.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	button.add_child(icon)

	var amount_label := Label.new()
	amount_label.name = "Amount"
	amount_label.set_anchors_preset(
		Control.PRESET_BOTTOM_RIGHT
	)
	amount_label.offset_left = -34.0
	amount_label.offset_top = -25.0
	amount_label.offset_right = -5.0
	amount_label.offset_bottom = -3.0
	amount_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	amount_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_BOTTOM
	)
	amount_label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	amount_label.add_theme_font_size_override(
		"font_size",
		15
	)
	amount_label.add_theme_color_override(
		"font_color",
		Color.WHITE
	)
	amount_label.add_theme_color_override(
		"font_outline_color",
		Color(0.03, 0.03, 0.03, 1.0)
	)
	amount_label.add_theme_constant_override(
		"outline_size",
		4
	)
	button.add_child(amount_label)

	var number_label := Label.new()
	number_label.name = "SlotNumber"
	number_label.text = str(index + 1)
	number_label.position = Vector2(
		5.0,
		2.0
	)
	number_label.size = Vector2(
		18.0,
		16.0
	)
	number_label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	number_label.add_theme_font_size_override(
		"font_size",
		9
	)
	number_label.add_theme_color_override(
		"font_color",
		Color(0.68, 0.72, 0.67, 1.0)
	)
	number_label.add_theme_color_override(
		"font_outline_color",
		Color(0.02, 0.02, 0.02, 1.0)
	)
	number_label.add_theme_constant_override(
		"outline_size",
		2
	)
	button.add_child(number_label)

	_apply_chest_slot_style(
		button,
		true
	)

	return {
		"button": button,
		"icon": icon,
		"amount_label": amount_label,
		"number_label": number_label
	}


# Creates the chest panel style.
func _create_chest_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(
		0.035,
		0.050,
		0.055,
		0.98
	)
	style.border_color = Color(
		0.18,
		0.21,
		0.17,
		1.0
	)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style


# Creates the hotbar background.
func _create_hotbar_background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(
		0.03,
		0.04,
		0.035,
		0.88
	)
	style.border_color = Color(
		0.12,
		0.15,
		0.12,
		0.95
	)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	return style


# Creates the slot style.
func _create_slot_style(
	hovered: bool,
	empty: bool
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()

	if empty:
		style.bg_color = Color(
			0.07,
			0.075,
			0.07,
			0.72
		)
		style.border_color = Color(
			0.17,
			0.18,
			0.17,
			0.75
		)
	elif hovered:
		style.bg_color = Color(
			0.16,
			0.17,
			0.15,
			0.96
		)
		style.border_color = Color(
			0.62,
			0.68,
			0.58,
			1.0
		)
	else:
		style.bg_color = Color(
			0.10,
			0.11,
			0.10,
			0.94
		)
		style.border_color = Color(
			0.34,
			0.37,
			0.33,
			1.0
		)

	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style


# Applies the chest slot style.
func _apply_chest_slot_style(
	button: Button,
	empty: bool
) -> void:
	button.add_theme_stylebox_override(
		"normal",
		_create_slot_style(
			false,
			empty
		)
	)
	button.add_theme_stylebox_override(
		"hover",
		_create_slot_style(
			true,
			false
		)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_create_slot_style(
			true,
			false
		)
	)
	button.add_theme_stylebox_override(
		"focus",
		_create_slot_style(
			false,
			empty
		)
	)
	button.add_theme_stylebox_override(
		"disabled",
		_create_slot_style(
			false,
			true
		)
	)


# Sets the chest slot visual.
func _set_chest_slot_visual(
	button: Button,
	icon_rect: TextureRect,
	amount_label: Label,
	item_data: ItemData,
	amount: int,
	disabled: bool,
	tooltip: String
) -> void:
	var empty: bool = (
		item_data == null
		or amount <= 0
	)

	button.text = ""
	button.disabled = disabled
	button.tooltip_text = tooltip

	if item_data != null and amount > 0:
		icon_rect.texture = (
			item_data.get_inventory_icon()
		)
		amount_label.text = str(amount)

		if disabled:
			icon_rect.modulate = Color(
				0.55,
				0.55,
				0.55,
				0.72
			)
			amount_label.add_theme_color_override(
				"font_color",
				Color(
					0.66,
					0.68,
					0.64,
					1.0
				)
			)
		else:
			icon_rect.modulate = Color.WHITE
			amount_label.add_theme_color_override(
				"font_color",
				Color.WHITE
			)
	else:
		icon_rect.texture = null
		icon_rect.modulate = Color.WHITE
		amount_label.text = ""

	_apply_chest_slot_style(
		button,
		empty or disabled
	)


# Refreshes the UI.
func _refresh_ui() -> void:
	if (
		not _is_open
		or not _storage.has(_open_station_id)
	):
		return

	var storage_slots: Array = (
		_storage[_open_station_id]
	)

	for index: int in range(CHEST_SLOT_COUNT):
		var item_id: StringName = (
			InventoryLayoutSystem.get_item_id(
				index
			)
		)
		var amount: int = (
			InventorySystem.get_amount(item_id)
			if item_id != &""
			else 0
		)
		var item_data: ItemData = (
			ItemCatalogSystem.get_item(item_id)
			if item_id != &""
			else null
		)

		var inventory_disabled: bool = true
		var inventory_tooltip: String = (
			"Empty slot"
		)

		if item_id != &"" and item_data != null:
			if item_data.is_seed():
				inventory_disabled = amount <= 0
				inventory_tooltip = (
					"%s x%d"
					% [
						item_data.display_name,
						amount
					]
				)
			else:
				inventory_disabled = true
				inventory_tooltip = (
					"%s - Seed Storage accepts seeds only."
					% item_data.display_name
				)
		elif item_id != &"":
			inventory_tooltip = String(item_id)

		_set_chest_slot_visual(
			_inventory_buttons[index],
			_inventory_icons[index],
			_inventory_amount_labels[index],
			item_data,
			amount,
			inventory_disabled,
			inventory_tooltip
		)

		var storage_slot: Dictionary = (
			storage_slots[index]
			if (
				index < storage_slots.size()
				and typeof(
					storage_slots[index]
				) == TYPE_DICTIONARY
			)
			else EMPTY_SLOT
		)
		var storage_item_id := StringName(
			String(
				storage_slot.get(
					"item_id",
					""
				)
			)
		)
		var storage_amount: int = int(
			storage_slot.get(
				"amount",
				0
			)
		)
		var storage_item: ItemData = (
			ItemCatalogSystem.get_item(
				storage_item_id
			)
			if storage_item_id != &""
			else null
		)
		var storage_tooltip: String = (
			"Empty storage slot"
		)

		if (
			storage_item != null
			and storage_amount > 0
		):
			storage_tooltip = (
				"%s x%d"
				% [
					storage_item.display_name,
					storage_amount
				]
			)
		elif storage_item_id != &"":
			storage_tooltip = String(
				storage_item_id
			)

		_set_chest_slot_visual(
			_storage_buttons[index],
			_storage_icons[index],
			_storage_amount_labels[index],
			storage_item,
			storage_amount,
			(
				storage_item == null
				or storage_amount <= 0
			),
			storage_tooltip
		)


# Refreshes the prompt.
func _refresh_prompt() -> void:
	var should_show: bool = (
		_configured
		and not _is_open
		and _nearby_station_id != &""
		and not get_tree().paused
		and not BuildSystem.is_active()
	)

	_prompt_label.visible = should_show

	if not should_show:
		return

	var world_position: Vector2 = _prompt_world_position(
		_nearby_station_id
	)

	if world_position == Vector2.INF:
		_prompt_label.visible = false
		return

	var screen_position: Vector2 = (
		get_viewport().get_canvas_transform()
		* (world_position + prompt_world_offset)
	)
	var animation_time: float = (
		float(Time.get_ticks_msec()) / 1000.0
	)
	var bob: float = sin(
		animation_time * prompt_bob_speed
	) * prompt_bob_pixels
	var pulse_01: float = (
		sin(
			animation_time
			* prompt_bob_speed
			* 0.85
		) * 0.5
		+ 0.5
	)
	var alpha: float = lerpf(
		prompt_alpha_min,
		prompt_alpha_max,
		pulse_01
	)

	_prompt_label.position = (
		screen_position
		- _prompt_label.size * 0.5
		+ Vector2(0.0, bob)
	)
	_prompt_label.modulate = Color(
		1.0,
		1.0,
		1.0,
		alpha
	)


# Returns the world position used by the interaction prompt.
func _prompt_world_position(
	station_id: StringName
) -> Vector2:
	if (
		_tilemap == null
		or _player == null
		or not _stations.has(station_id)
	):
		return Vector2.INF

	var station: Dictionary = _stations[station_id]
	var cells_variant: Variant = station.get(
		"cells",
		[]
	)

	if typeof(cells_variant) != TYPE_ARRAY:
		return Vector2.INF

	var best_position: Vector2 = Vector2.INF
	var best_distance: float = INF

	for cell_variant: Variant in cells_variant:
		if not (cell_variant is Vector2i):
			continue

		var cell: Vector2i = cell_variant
		var world_position: Vector2 = (
			_tilemap.to_global(
				_tilemap.map_to_local(cell)
			)
		)
		var distance: float = (
			_player.global_position.distance_to(
				world_position
			)
		)

		if distance < best_distance:
			best_distance = distance
			best_position = world_position

	return best_position


# Formats Storage state for debug output.
func _storage_debug_string(
	station_id: StringName
) -> String:
	if not _storage.has(station_id):
		return "[]"

	var parts: Array[String] = []

	for slot_variant: Variant in _storage[station_id]:
		if typeof(slot_variant) != TYPE_DICTIONARY:
			continue

		var slot: Dictionary = slot_variant
		var amount: int = int(
			slot.get("amount", 0)
		)

		if amount <= 0:
			continue

		parts.append(
			"%s:%d" % [
				String(
					slot.get(
						"item_id",
						""
					)
				),
				amount
			]
		)

	return "[%s]" % ", ".join(parts)


# Prints all Storage debug state.
func _storage_debug_all() -> Dictionary:
	var result: Dictionary = {}

	for station_id_variant: Variant in _storage.keys():
		var station_id := StringName(
			String(station_id_variant)
		)
		result[String(station_id)] = (
			_storage_debug_string(station_id)
		)

	return result


# Handles the build cell changed signal or callback.
func _on_build_cell_changed(
	_cell: Vector2i,
	_build_id: StringName,
	_value: int
) -> void:
	if not _configured:
		return

	call_deferred(
		"_rebuild_stations_from_world"
	)


# Handles the build world rebuilt signal or callback.
func _on_build_world_rebuilt() -> void:
	if not _configured:
		return

	_rebuild_stations_from_world()
	_find_nearby_station()
	_refresh_prompt()


# Handles the inventory item amount changed signal or callback.
func _on_inventory_item_amount_changed(
	_item_id: StringName,
	_previous_amount: int,
	_new_amount: int
) -> void:
	if _is_open:
		_refresh_ui()


# Handles the inventory layout changed signal or callback.
func _on_inventory_layout_changed(
	_slot_index: int,
	_item_id: StringName,
	_item_data: ItemData
) -> void:
	if _is_open:
		_refresh_ui()


# Handles the inventory layout reset signal or callback.
func _on_inventory_layout_reset() -> void:
	if _is_open:
		_refresh_ui()
