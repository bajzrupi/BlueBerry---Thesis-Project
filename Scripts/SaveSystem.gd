extends Node

# Versioned JSON save/load service with three independent garden slots.

signal save_completed(path: String)
signal autosave_completed(
	path: String,
	slot: int,
	reason: String
)
signal load_completed(path: String)
signal save_failed(reason: String)
signal load_failed(reason: String)
signal save_deleted(slot: int)
signal active_slot_changed(slot: int)

const SAVE_VERSION: int = 1
const MAX_SAVE_SLOTS: int = 3

# Previous single-save path. It is migrated to Garden 1 once when no slot saves exist.
const LEGACY_SAVE_PATH: String = "user://blueberry_save_v1.json"
const SLOT_SAVE_PATH_TEMPLATE: String = "user://blueberry_save_slot_%d.json"
const PROFILE_PATH: String = "user://blueberry_profile_v1.json"

const BIOME_NUMERIC_KEYS: Array[String] = [
	"moisture",
	"nutrients",
	"ph",
	"humidity",
	"temperature",
	"light",
	"pest_pressure",
	"disease_pressure"
]

@export_category("Autosave")

# Master switch for periodic autosaving.
@export var autosave_enabled: bool = true

# Real, unpaused gameplay seconds between periodic autosaves.
# Three minutes is frequent enough for an alpha without writing constantly.
@export_range(30.0, 900.0, 10.0)
var autosave_interval_seconds: float = 180.0

# A brand-new Garden has no save file yet. Its first autosave happens sooner
# so Continue becomes available without requiring a manual Pause Menu save.
@export_range(5.0, 120.0, 5.0)
var autosave_new_garden_delay_seconds: float = 15.0

# New in-game days may also request an autosave. The minimum spacing prevents
# the current accelerated development clock from writing every 30 seconds.
@export var autosave_on_day_change: bool = true

@export_range(30.0, 600.0, 10.0)
var autosave_minimum_spacing_seconds: float = 120.0

# Small non-modal notification in the existing SaveSystem toast.
@export var autosave_show_toast: bool = true


@export_category("Debug Logging")
@export var debug_log: bool = false

var _tilemap: TileMap
var _player: CharacterBody2D
var _load_in_progress: bool = false
var _active_slot: int = 1

var _autosave_elapsed: float = 0.0
var _seconds_since_last_save: float = 0.0
var _autosave_in_progress: bool = false

var _toast_layer: CanvasLayer
var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_tween: Tween


# Initializes this system when the node becomes ready.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_toast()
	_migrate_legacy_save_if_needed()
	_load_profile()

	if not Clock.day_changed.is_connected(
		_on_autosave_day_changed
	):
		Clock.day_changed.connect(
			_on_autosave_day_changed
		)

	if debug_log:
		print(
			"[SaveSystem] ready active_slot=",
			_active_slot,
			" path=",
			get_active_save_path(),
			" any_save=",
			has_any_save(),
			" autosave=",
			autosave_enabled,
			" interval=",
			autosave_interval_seconds,
			"s"
		)


# Connects save/load to the active gameplay world.
func configure(
	tilemap: TileMap,
	player: CharacterBody2D
) -> void:
	_tilemap = tilemap
	_player = player

	_autosave_elapsed = 0.0
	_seconds_since_last_save = 0.0
	_autosave_in_progress = false

	# New Garden: make the first automatic save much sooner than the normal
	# periodic interval. Existing Gardens use the full interval after load.
	if (
		autosave_enabled
		and not has_save()
	):
		_autosave_elapsed = maxf(
			autosave_interval_seconds
			- autosave_new_garden_delay_seconds,
			0.0
		)

	if debug_log:
		print(
			"[SaveSystem] configured active_slot=",
			_active_slot,
			" save_exists=",
			has_save(),
			" first_autosave_in=",
			_get_seconds_until_next_autosave()
		)


# Disconnects this system from the current world references.
func unconfigure(tilemap: TileMap) -> void:
	if _tilemap != tilemap:
		return

	_tilemap = null
	_player = null

	_autosave_elapsed = 0.0
	_seconds_since_last_save = 0.0
	_autosave_in_progress = false


# Autosave counts only active, unpaused gameplay time. SaveSystem itself uses
# PROCESS_MODE_ALWAYS, so explicitly ignoring paused time prevents menu/modal
# screens from consuming the autosave interval.
func _process(delta: float) -> void:
	if not autosave_enabled:
		return

	if not _can_autosave_now():
		return

	_autosave_elapsed += delta
	_seconds_since_last_save += delta

	if (
		_autosave_elapsed
		>= autosave_interval_seconds
	):
		perform_autosave("INTERVAL")


# Public hook for future systems that want a safe automatic save after an
# important event. Returns false when gameplay is not currently saveable.
func perform_autosave(
	reason: String = "REQUESTED"
) -> bool:
	if not autosave_enabled:
		return false

	if _autosave_in_progress:
		return false

	if not _can_autosave_now():
		return false

	_autosave_in_progress = true

	var saved: bool = save_game(
		true,
		reason
	)

	_autosave_in_progress = false
	return saved


# Handles the autosave day changed signal or callback.
func _on_autosave_day_changed(
	new_day: int
) -> void:
	if (
		not autosave_enabled
		or not autosave_on_day_change
	):
		return

	if not _can_autosave_now():
		return

	if (
		_seconds_since_last_save
		< autosave_minimum_spacing_seconds
	):
		if debug_log:
			print(
				"[SaveSystem] autosave day=",
				new_day,
				" skipped cooldown=",
				snappedf(
					autosave_minimum_spacing_seconds
					- _seconds_since_last_save,
					0.1
				),
				"s"
			)
		return

	# Defer out of Clock.day_changed so the save captures the fully completed
	# rollover and any other day-change subscribers that update immediately.
	call_deferred(
		"_perform_day_change_autosave",
		new_day
	)


# Handles perform day change autosave.
func _perform_day_change_autosave(
	new_day: int
) -> void:
	perform_autosave(
		"NEW_DAY_%d" % new_day
	)


# Checks whether autosave now is allowed.
func _can_autosave_now() -> bool:
	return (
		_is_world_configured()
		and not _load_in_progress
		and not _autosave_in_progress
		and not get_tree().paused
	)


# Returns the seconds until next autosave.
func _get_seconds_until_next_autosave() -> float:
	if not autosave_enabled:
		return -1.0

	return maxf(
		autosave_interval_seconds
		- _autosave_elapsed,
		0.0
	)


# Checks whether the requested slot index is valid.
func is_valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= MAX_SAVE_SLOTS


# Returns the active slot.
func get_active_slot() -> int:
	return _active_slot


# Returns the save path.
func get_save_path(slot: int) -> String:
	if not is_valid_slot(slot):
		return ""

	return SLOT_SAVE_PATH_TEMPLATE % slot


# Returns the active save path.
func get_active_save_path() -> String:
	return get_save_path(_active_slot)


# With no argument, checks the currently active garden.
func has_save(slot: int = -1) -> bool:
	var resolved_slot: int = (
		_active_slot if slot == -1 else slot
	)

	if not is_valid_slot(resolved_slot):
		return false

	return FileAccess.file_exists(
		get_save_path(resolved_slot)
	)


# Checks whether any save exists or is available.
func has_any_save() -> bool:
	for slot in range(1, MAX_SAVE_SLOTS + 1):
		if has_save(slot):
			return true

	return false


# Returns the existing slots.
func get_existing_slots() -> Array[int]:
	var slots: Array[int] = []

	for slot in range(1, MAX_SAVE_SLOTS + 1):
		if has_save(slot):
			slots.append(slot)

	return slots


# Returns the slot used by the Main Menu Continue button.
# The last active garden wins when it still exists; otherwise the first
# existing save becomes the preferred garden.
func get_preferred_continue_slot() -> int:
	if has_save(_active_slot):
		return _active_slot

	var existing_slots := get_existing_slots()

	if existing_slots.is_empty():
		return -1

	return existing_slots[0]


# Sets the active slot.
func set_active_slot(slot: int) -> bool:
	if not is_valid_slot(slot):
		push_warning(
			"[SaveSystem] invalid active slot=%d" % slot
		)
		return false

	var changed: bool = _active_slot != slot
	_active_slot = slot
	_write_profile()

	if changed:
		active_slot_changed.emit(_active_slot)

	if debug_log:
		print(
			"[SaveSystem] active slot=",
			_active_slot,
			" path=",
			get_active_save_path()
		)

	return true


# Deletes one garden save. During New Game, preserve_active_slot=true keeps
# the chosen empty slot active so the next Save writes into that garden.
func delete_save(
	slot: int,
	preserve_active_slot: bool = false
) -> bool:
	if not is_valid_slot(slot):
		push_warning(
			"[SaveSystem] delete invalid slot=%d" % slot
		)
		return false

	var path := get_save_path(slot)

	if FileAccess.file_exists(path):
		var absolute_path := ProjectSettings.globalize_path(
			path
		)
		var error: Error = DirAccess.remove_absolute(
			absolute_path
		)

		if error != OK:
			push_warning(
				"[SaveSystem] delete failed slot=%d error=%s"
				% [slot, error]
			)
			return false

	if (
		not preserve_active_slot
		and _active_slot == slot
	):
		var remaining_slots := get_existing_slots()

		if remaining_slots.is_empty():
			_active_slot = 1
		else:
			_active_slot = remaining_slots[0]

		active_slot_changed.emit(_active_slot)

	_write_profile()
	save_deleted.emit(slot)

	if debug_log:
		print(
			"[SaveSystem] DELETED slot=",
			slot,
			" active_slot=",
			_active_slot,
			" preserve_active=",
			preserve_active_slot
		)

	return true


# Lightweight metadata read for the Main Menu. This never changes gameplay
# state and therefore does not require the world to be configured.
func get_slot_metadata(slot: int) -> Dictionary:
	var result: Dictionary = {
		"slot": slot,
		"exists": false,
		"valid": false,
		"character_id": "male",
		"player_level": 0,
		"day": 1,
		"money": 0,
		"saved_at_unix": 0
	}

	if not is_valid_slot(slot):
		return result

	var path := get_save_path(slot)

	if not FileAccess.file_exists(path):
		return result

	result["exists"] = true

	var save_data := _read_save_dictionary(path)

	if save_data.is_empty():
		return result

	result["valid"] = (
		int(save_data.get("version", 0)) == SAVE_VERSION
	)

	var meta: Dictionary = _dictionary_section(
		save_data,
		"meta"
	)
	var player_state: Dictionary = _dictionary_section(
		save_data,
		"player"
	)
	var progression_state: Dictionary = _dictionary_section(
		save_data,
		"progression"
	)
	var clock_state: Dictionary = _dictionary_section(
		save_data,
		"clock"
	)
	var economy_state: Dictionary = _dictionary_section(
		save_data,
		"economy"
	)

	result["character_id"] = String(
		meta.get(
			"character_id",
			player_state.get("character_id", "male")
		)
	)
	result["player_level"] = int(
		meta.get(
			"player_level",
			progression_state.get("player_level", 0)
		)
	)
	result["day"] = int(
		meta.get(
			"day",
			clock_state.get("day", 1)
		)
	)
	result["money"] = int(
		meta.get(
			"money",
			economy_state.get("money", 0)
		)
	)
	result["saved_at_unix"] = int(
		meta.get("saved_at_unix", 0)
	)

	return result


# Returns the all slot metadata.
func get_all_slot_metadata() -> Array[Dictionary]:
	var metadata: Array[Dictionary] = []

	for slot in range(1, MAX_SAVE_SLOTS + 1):
		metadata.append(get_slot_metadata(slot))

	return metadata


# Saves the current game state to the active slot.
func save_game(
	is_autosave: bool = false,
	autosave_reason: String = ""
) -> bool:
	if not _is_world_configured():
		return _fail_save(
			"WORLD_NOT_CONFIGURED",
			is_autosave
		)

	var save_data: Dictionary = {
		"version": SAVE_VERSION,
		"meta": _capture_save_metadata(
			is_autosave,
			autosave_reason
		),
		"player": _capture_player_state(),
		"economy": {
			"money": EconomySystem.get_money()
		},
		"progression": _capture_progression_state(),
		"tools": Toolsystem.get_save_state(),
		"inventory": _capture_inventory_state(),
		"inventory_layout": _string_array(
			InventoryLayoutSystem.get_layout_ids()
		),
		"hotbar": _string_array(
			HotbarSystem.get_assignment_ids()
		),
		"plant_selection": _capture_selection_state(),
		"clock": {
			"day": Clock.day,
			"minute_of_day": Clock.minute_of_day
		},
		"weather": WeatherSystem.get_save_state(),
		"random_events": _capture_random_event_state(),
		"build": BuildSystem.get_save_state(),
		"sprinklers": SprinklerSystem.get_save_state(),
		"fertilizer_injectors": FertilizerInjectorSystem.get_save_state(),
		"soil_neutralizers": SoilNeutralizerSystem.get_save_state(),
		"plant_protection_stations": PlantProtectionStationSystem.get_save_state(),
		"seed_storage": ChestSystem.get_save_state(),
		"biome": _capture_biome_state(),
		"plants": _capture_plants_state()
	}

	var save_path := get_active_save_path()

	var file := FileAccess.open(
		save_path,
		FileAccess.WRITE
	)

	if file == null:
		return _fail_save(
			"FILE_OPEN_ERROR_%s"
			% FileAccess.get_open_error(),
			is_autosave
		)

	var json_text: String = JSON.stringify(
		save_data,
		"\t"
	)

	file.store_string(json_text)
	file.flush()

	# Every successful save restarts the automatic-save clocks. A manual save
	# therefore prevents an autosave from firing immediately afterwards.
	_autosave_elapsed = 0.0
	_seconds_since_last_save = 0.0

	save_completed.emit(save_path)

	if is_autosave:
		autosave_completed.emit(
			save_path,
			_active_slot,
			autosave_reason
		)

		if autosave_show_toast:
			_show_toast(
				"AUTOSAVED • GARDEN %d"
				% _active_slot
			)
	else:
		_show_toast("GAME SAVED")

	if debug_log:
		print(
			"[SaveSystem] ",
			"AUTOSAVED" if is_autosave else "SAVED",
			" slot=",
			_active_slot,
			" reason=",
			(
				autosave_reason
				if is_autosave
				else "MANUAL"
			),
			" version=",
			SAVE_VERSION,
			" bytes=",
			json_text.length(),
			" builds=",
			Array(save_data.get("build", [])).size(),
			" plants=",
			Array(save_data.get("plants", [])).size(),
			" sprinklers=",
			Array(
				save_data.get(
					"sprinklers",
					[]
				)
			).size(),
			" fertilizer_injectors=",
			Array(
				save_data.get(
					"fertilizer_injectors",
					[]
				)
			).size(),
			" soil_neutralizers=",
			Array(
				save_data.get(
					"soil_neutralizers",
					[]
				)
			).size(),
			" plant_protection_stations=",
			Array(
				save_data.get(
					"plant_protection_stations",
					[]
				)
			).size(),
			" seed_storage=",
			Array(
				save_data.get(
					"seed_storage",
					[]
				)
			).size(),
			" character=",
			CharacterSystem.get_current_character_id(),
			" day=",
			Clock.day,
			" time=",
			Clock.format_time()
		)

	return true


# Loads the active save slot and restores the game state.
func load_game() -> bool:
	if _load_in_progress:
		return _fail_load("LOAD_ALREADY_IN_PROGRESS")

	if not _is_world_configured():
		return _fail_load("WORLD_NOT_CONFIGURED")

	if not has_save():
		return _fail_load("SAVE_FILE_NOT_FOUND")

	var save_path := get_active_save_path()

	var file := FileAccess.open(
		save_path,
		FileAccess.READ
	)

	if file == null:
		return _fail_load(
			"FILE_OPEN_ERROR_%s" % FileAccess.get_open_error()
		)

	var raw_text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(raw_text)

	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail_load("INVALID_JSON_ROOT")

	var save_data: Dictionary = parsed
	var version: int = int(save_data.get("version", 0))

	if version != SAVE_VERSION:
		return _fail_load(
			"UNSUPPORTED_SAVE_VERSION_%d" % version
		)

	# Snapshot runtime execution state before touching any game system.
	var previous_tree_paused: bool = get_tree().paused
	var previous_mouse_mode: int = Input.get_mouse_mode()
	var previous_clock_paused: bool = bool(
		Clock.get("_paused")
	)
	var previous_player_physics: bool = (
		_player.is_physics_processing()
	)
	var previous_player_process: bool = (
		_player.is_processing()
	)

	_load_in_progress = true

	# Loading is a synchronous world transaction. Pausing prevents a physics
	# frame/tick from observing a half-restored map, but the exact previous
	# execution state is restored before load_game returns.
	get_tree().paused = true
	Clock.set_paused(true)
	_player.velocity = Vector2.ZERO

	if debug_log:
		print(
			"[SaveSystem] LOAD BEGIN slot=",
			_active_slot,
			" tree_paused=",
			previous_tree_paused,
			" clock_paused=",
			previous_clock_paused,
			" player_physics=",
			previous_player_physics,
			" mouse_mode=",
			previous_mouse_mode
		)

	# Progression first: unlocked plant definitions are required by the
	# inventory/hotbar/selection restore steps.
	_restore_progression_state(
		_dictionary_section(
			save_data,
			"progression"
		)
	)
	_restore_economy_state(
		_dictionary_section(
			save_data,
			"economy"
		)
	)
	Toolsystem.load_save_state(
		_dictionary_section(
			save_data,
			"tools"
		)
	)
	_restore_inventory_state(
		_dictionary_section(
			save_data,
			"inventory"
		)
	)
	_restore_inventory_layout(
		_array_section(
			save_data,
			"inventory_layout"
		)
	)
	_restore_hotbar(
		_array_section(
			save_data,
			"hotbar"
		)
	)

	# Rebuild the map before restoring biome zones and living plants.
	BuildSystem.load_save_state(
		_array_section(
			save_data,
			"build"
		)
	)

	var seed_storage_state: Array = _array_section(
		save_data,
		"seed_storage"
	)

	if (
		seed_storage_state.is_empty()
		and save_data.has("chests")
	):
		seed_storage_state = _array_section(
			save_data,
			"chests"
		)

	ChestSystem.load_save_state(
		seed_storage_state
	)

	_restore_clock_state(
		_dictionary_section(
			save_data,
			"clock"
		)
	)

	# Sprinkler machine state depends on both the restored BuildSystem cells
	# and the restored game clock. Old saves without this section receive the
	# default Level 1 / 3-hour / enabled configuration automatically.
	SprinklerSystem.load_save_state(
		_array_section(
			save_data,
			"sprinklers"
		)
	)

	# New automation-machine saves are backward compatible: old Gardens without
	# this section simply rebuild Level 1/default configuration from BuildSystem.
	FertilizerInjectorSystem.load_save_state(
		_array_section(
			save_data,
			"fertilizer_injectors"
		)
	)

	SoilNeutralizerSystem.load_save_state(
		_array_section(
			save_data,
			"soil_neutralizers"
		)
	)

	PlantProtectionStationSystem.load_save_state(
		_array_section(
			save_data,
			"plant_protection_stations"
		)
	)

	_restore_biome_state(
		_array_section(
			save_data,
			"biome"
		)
	)
	_restore_weather_state(
		_dictionary_section(
			save_data,
			"weather"
		)
	)

	_restore_random_event_state(
		_dictionary_section(
			save_data,
			"random_events"
		)
	)

	_restore_player_state(
		_dictionary_section(
			save_data,
			"player"
		)
	)
	_restore_plants_state(
		_array_section(
			save_data,
			"plants"
		)
	)
	_restore_selection_state(
		_dictionary_section(
			save_data,
			"plant_selection"
		)
	)

	# Time speed is a session/UI preference, not Garden save data.
	# Every successful load resumes at the safe 1x simulation speed.
	Clock.reset_time_scale()

	# Explicitly restore every execution/input state that can make the game
	# appear frozen. This is intentionally independent from saved gameplay data.
	Clock.set_paused(previous_clock_paused)
	_player.set_physics_process(
		previous_player_physics
	)
	_player.set_process(
		previous_player_process
	)
	get_tree().paused = previous_tree_paused
	Input.set_mouse_mode(previous_mouse_mode)

	_load_in_progress = false

	# Loading is itself a fresh persistence checkpoint. Start a full autosave
	# interval after Continue rather than immediately rewriting the file.
	_autosave_elapsed = 0.0
	_seconds_since_last_save = 0.0

	# A deferred second pass catches any deferred callback emitted during load
	# that attempts to leave the SceneTree/clock/player in a paused state.
	call_deferred(
		"_post_load_runtime_sanity",
		previous_tree_paused,
		previous_clock_paused,
		previous_player_physics,
		previous_player_process,
		previous_mouse_mode
	)

	load_completed.emit(save_path)
	_show_toast("GAME LOADED")

	if debug_log:
		print(
			"[SaveSystem] LOADED slot=",
			_active_slot,
			" version=",
			version,
			" builds=",
			_array_section(save_data, "build").size(),
			" plants=",
			_array_section(save_data, "plants").size(),
			" sprinklers=",
			_array_section(save_data, "sprinklers").size(),
			" fertilizer_injectors=",
			_array_section(
				save_data,
				"fertilizer_injectors"
			).size(),
			" soil_neutralizers=",
			_array_section(
				save_data,
				"soil_neutralizers"
			).size(),
			" plant_protection_stations=",
			_array_section(
				save_data,
				"plant_protection_stations"
			).size(),
			" seed_storage=",
			seed_storage_state.size(),
			" money=",
			EconomySystem.get_money(),
			" player_level=",
			ProgressionSystem.player_level,
			" credits=",
			ProgressionSystem.build_cell_credits,
			" character=",
			CharacterSystem.get_current_character_id(),
			" day=",
			Clock.day,
			" time=",
			Clock.format_time(),
			" tree_paused=",
			get_tree().paused,
			" clock_paused=",
			bool(Clock.get("_paused")),
			" player_physics=",
			_player.is_physics_processing()
		)

	return true


# Handles post load runtime sanity.
func _post_load_runtime_sanity(
	expected_tree_paused: bool,
	expected_clock_paused: bool,
	expected_player_physics: bool,
	expected_player_process: bool,
	expected_mouse_mode: int
) -> void:
	if _player == null:
		return

	var corrected: bool = false

	if get_tree().paused != expected_tree_paused:
		get_tree().paused = expected_tree_paused
		corrected = true

	if bool(Clock.get("_paused")) != expected_clock_paused:
		Clock.set_paused(expected_clock_paused)
		corrected = true

	if (
		_player.is_physics_processing()
		!= expected_player_physics
	):
		_player.set_physics_process(
			expected_player_physics
		)
		corrected = true

	if _player.is_processing() != expected_player_process:
		_player.set_process(
			expected_player_process
		)
		corrected = true

	if Input.get_mouse_mode() != expected_mouse_mode:
		Input.set_mouse_mode(expected_mouse_mode)
		corrected = true

	if debug_log:
		print(
			"[SaveSystem] POST-LOAD runtime sanity corrected=",
			corrected,
			" tree_paused=",
			get_tree().paused,
			" clock_paused=",
			bool(Clock.get("_paused")),
			" player_physics=",
			_player.is_physics_processing(),
			" player_process=",
			_player.is_processing(),
			" mouse_mode=",
			Input.get_mouse_mode(),
			" build_active=",
			BuildSystem.is_active()
		)



# Captures the save metadata for save, restore, or validation.
func _capture_save_metadata(
	is_autosave: bool = false,
	autosave_reason: String = ""
) -> Dictionary:
	return {
		"slot": _active_slot,
		"character_id": String(
			CharacterSystem.get_current_character_id()
		),
		"player_level": ProgressionSystem.player_level,
		"day": Clock.day,
		"money": EconomySystem.get_money(),
		"saved_at_unix": int(
			Time.get_unix_time_from_system()
		),
		"save_kind": (
			"autosave"
			if is_autosave
			else "manual"
		),
		"save_reason": (
			autosave_reason
			if is_autosave
			else "MANUAL"
		)
	}


# Reads the save dictionary.
func _read_save_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(
		path,
		FileAccess.READ
	)

	if file == null:
		return {}

	var parsed: Variant = JSON.parse_string(
		file.get_as_text()
	)

	if typeof(parsed) != TYPE_DICTIONARY:
		return {}

	var result: Dictionary = parsed
	return result


# Loads the profile.
func _load_profile() -> void:
	_active_slot = 1

	if not FileAccess.file_exists(PROFILE_PATH):
		var preferred := get_preferred_continue_slot()

		if preferred != -1:
			_active_slot = preferred

		_write_profile()
		return

	var profile := _read_save_dictionary(PROFILE_PATH)
	var saved_slot: int = int(
		profile.get("last_active_slot", 1)
	)

	if is_valid_slot(saved_slot):
		_active_slot = saved_slot

	# If that garden was deleted outside the game, Continue falls back cleanly.
	if not has_save(_active_slot):
		var existing_slots := get_existing_slots()

		if not existing_slots.is_empty():
			_active_slot = existing_slots[0]

	_write_profile()


# Writes the profile.
func _write_profile() -> void:
	var file := FileAccess.open(
		PROFILE_PATH,
		FileAccess.WRITE
	)

	if file == null:
		push_warning(
			"[SaveSystem] could not write profile error=%s"
			% FileAccess.get_open_error()
		)
		return

	file.store_string(
		JSON.stringify(
			{
				"version": 1,
				"last_active_slot": _active_slot
			},
			"\t"
		)
	)
	file.flush()


# Migrates the legacy save if needed to the current data format.
func _migrate_legacy_save_if_needed() -> void:
	if not FileAccess.file_exists(LEGACY_SAVE_PATH):
		return

	if has_any_save():
		return

	var legacy_file := FileAccess.open(
		LEGACY_SAVE_PATH,
		FileAccess.READ
	)

	if legacy_file == null:
		return

	var legacy_text := legacy_file.get_as_text()
	var slot_one_path := get_save_path(1)
	var slot_file := FileAccess.open(
		slot_one_path,
		FileAccess.WRITE
	)

	if slot_file == null:
		push_warning(
			"[SaveSystem] legacy migration could not create Garden 1"
		)
		return

	slot_file.store_string(legacy_text)
	slot_file.flush()

	var legacy_absolute := ProjectSettings.globalize_path(
		LEGACY_SAVE_PATH
	)
	DirAccess.remove_absolute(legacy_absolute)

	_active_slot = 1

	if debug_log:
		print(
			"[SaveSystem] migrated legacy save -> Garden 1"
		)


# Captures the player state for save, restore, or validation.
func _capture_player_state() -> Dictionary:
	return {
		"x": _player.global_position.x,
		"y": _player.global_position.y,
		"character_id": String(
			CharacterSystem.get_current_character_id()
		)
	}


# Restores the player state from saved or temporary state.
func _restore_player_state(state: Dictionary) -> void:
	var saved_character_text: String = String(
		state.get(
			"character_id",
			String(
				CharacterSystem.get_current_character_id()
			)
		)
	)
	var saved_character_id := StringName(saved_character_text)

	if CharacterSystem.is_valid_character(saved_character_id):
		CharacterSystem.set_character(saved_character_id)
	else:
		push_warning(
			"[SaveSystem] invalid saved character id=%s; keeping current=%s"
			% [
				String(saved_character_id),
				String(
					CharacterSystem.get_current_character_id()
				)
			]
		)

	_player.global_position = Vector2(
		float(state.get("x", _player.global_position.x)),
		float(state.get("y", _player.global_position.y))
	)
	_player.velocity = Vector2.ZERO


# Captures the random event state for save, restore, or validation.
func _capture_random_event_state() -> Dictionary:
	var event_system: Node = get_node_or_null(
		"/root/RandomEventSystem"
	)

	if (
		event_system != null
		and event_system.has_method("get_save_state")
	):
		var state_variant: Variant = event_system.call(
			"get_save_state"
		)

		if typeof(state_variant) == TYPE_DICTIONARY:
			return state_variant

	return {}


# Restores the random event state from saved or temporary state.
func _restore_random_event_state(state: Dictionary) -> void:
	var event_system: Node = get_node_or_null(
		"/root/RandomEventSystem"
	)

	if event_system == null:
		return

	if event_system.has_method("load_save_state"):
		event_system.call("load_save_state", state)


# Captures the progression state for save, restore, or validation.
func _capture_progression_state() -> Dictionary:
	return {
		"player_level": ProgressionSystem.player_level,
		"player_xp": ProgressionSystem.player_xp,
		"plant_unlock_tokens": ProgressionSystem.plant_unlock_tokens,
		"build_cell_credits": ProgressionSystem.build_cell_credits,
		"plant_levels": _string_key_dictionary(
			ProgressionSystem.get("_plant_levels")
		),
		"plant_xp": _string_key_dictionary(
			ProgressionSystem.get("_plant_xp")
		),
		"plant_unlocked": _string_key_dictionary(
			ProgressionSystem.get("_plant_unlocked")
		),
		"terrain_levels": _string_key_dictionary(
			ProgressionSystem.get("_terrain_levels")
		),
		"equipment_levels": _string_key_dictionary(
			ProgressionSystem.get("_equipment_levels")
		)
	}


# Restores the progression state from saved or temporary state.
func _restore_progression_state(state: Dictionary) -> void:
	var previous_tokens: int = ProgressionSystem.plant_unlock_tokens
	var previous_credits: int = ProgressionSystem.build_cell_credits

	var previous_unlocks: Dictionary = _copy_variant_dictionary(
		ProgressionSystem.get("_plant_unlocked")
	)
	var previous_terrains: Dictionary = _copy_variant_dictionary(
		ProgressionSystem.get("_terrain_levels")
	)
	var previous_equipment: Dictionary = _copy_variant_dictionary(
		ProgressionSystem.get("_equipment_levels")
	)

	ProgressionSystem.player_level = maxi(
		int(state.get("player_level", 0)),
		0
	)
	ProgressionSystem.player_xp = maxi(
		int(state.get("player_xp", 0)),
		0
	)
	ProgressionSystem.plant_unlock_tokens = maxi(
		int(state.get("plant_unlock_tokens", 0)),
		0
	)
	ProgressionSystem.build_cell_credits = maxi(
		int(state.get("build_cell_credits", 0)),
		0
	)

	var saved_plant_levels: Dictionary = _dictionary_value(
		state.get("plant_levels", {})
	)
	var saved_plant_xp: Dictionary = _dictionary_value(
		state.get("plant_xp", {})
	)
	var saved_unlocks: Dictionary = _dictionary_value(
		state.get("plant_unlocked", {})
	)
	var saved_terrains: Dictionary = _dictionary_value(
		state.get("terrain_levels", {})
	)
	var saved_equipment: Dictionary = _dictionary_value(
		state.get("equipment_levels", {})
	)

	var plant_levels: Dictionary = {}
	var plant_xp: Dictionary = {}
	var plant_unlocked: Dictionary = {}

	for plant_id: StringName in ProgressionSystem.TRACKED_PLANTS:
		var key := String(plant_id)
		plant_levels[plant_id] = clampi(
			int(saved_plant_levels.get(key, 0)),
			0,
			ProgressionSystem.MAX_PLANT_LEVEL
		)
		plant_xp[plant_id] = maxi(
			int(saved_plant_xp.get(key, 0)),
			0
		)
		plant_unlocked[plant_id] = bool(
			saved_unlocks.get(
				key,
				ProgressionSystem.STARTING_UNLOCKED_PLANTS.has(
					plant_id
				)
			)
		)

	var terrain_levels: Dictionary = {}

	for terrain_id: StringName in ProgressionSystem.TRACKED_TERRAINS:
		var key := String(terrain_id)
		terrain_levels[terrain_id] = clampi(
			int(saved_terrains.get(key, 1)),
			1,
			ProgressionSystem.MAX_TERRAIN_LEVEL
		)

	var equipment_levels: Dictionary = {}

	for equipment_id: StringName in ProgressionSystem.TRACKED_EQUIPMENT:
		var key := String(equipment_id)
		equipment_levels[equipment_id] = clampi(
			int(saved_equipment.get(key, 1)),
			1,
			ProgressionSystem.MAX_EQUIPMENT_LEVEL
		)

	ProgressionSystem.set("_plant_levels", plant_levels)
	ProgressionSystem.set("_plant_xp", plant_xp)
	ProgressionSystem.set("_plant_unlocked", plant_unlocked)
	ProgressionSystem.set("_terrain_levels", terrain_levels)
	ProgressionSystem.set("_equipment_levels", equipment_levels)

	# Refresh dependent UI/systems without emitting player_level_changed or
	# milestone signals, so loading a save never awards or announces a level.
	ProgressionSystem.progression_reset.emit()
	ProgressionSystem.call("_emit_player_progress")

	for plant_id: StringName in ProgressionSystem.TRACKED_PLANTS:
		ProgressionSystem.call(
			"_emit_plant_progress",
			plant_id
		)

		var old_unlocked: bool = bool(
			previous_unlocks.get(plant_id, false)
		)
		var new_unlocked: bool = bool(
			plant_unlocked.get(plant_id, false)
		)

		if old_unlocked != new_unlocked:
			ProgressionSystem.plant_unlock_changed.emit(
				plant_id,
				new_unlocked
			)

	for terrain_id: StringName in ProgressionSystem.TRACKED_TERRAINS:
		var old_level: int = int(
			previous_terrains.get(terrain_id, 1)
		)
		var new_level: int = int(
			terrain_levels.get(terrain_id, 1)
		)

		if old_level != new_level:
			ProgressionSystem.terrain_level_changed.emit(
				terrain_id,
				old_level,
				new_level
			)

	for equipment_id: StringName in ProgressionSystem.TRACKED_EQUIPMENT:
		var old_level: int = int(
			previous_equipment.get(equipment_id, 1)
		)
		var new_level: int = int(
			equipment_levels.get(equipment_id, 1)
		)

		if old_level != new_level:
			ProgressionSystem.equipment_level_changed.emit(
				equipment_id,
				old_level,
				new_level
			)

	if previous_tokens != ProgressionSystem.plant_unlock_tokens:
		ProgressionSystem.plant_unlock_tokens_changed.emit(
			previous_tokens,
			ProgressionSystem.plant_unlock_tokens,
			ProgressionSystem.plant_unlock_tokens - previous_tokens,
			"LOAD"
		)

	if previous_credits != ProgressionSystem.build_cell_credits:
		ProgressionSystem.build_cell_credits_changed.emit(
			previous_credits,
			ProgressionSystem.build_cell_credits,
			ProgressionSystem.build_cell_credits - previous_credits,
			"LOAD"
		)


# Restores the economy state from saved or temporary state.
func _restore_economy_state(state: Dictionary) -> void:
	EconomySystem.set_money(
		int(state.get("money", 0)),
		"LOAD"
	)


# Captures the inventory state for save, restore, or validation.
func _capture_inventory_state() -> Dictionary:
	return _string_key_dictionary(
		InventorySystem.get_all_items()
	)


# Restores the inventory state from saved or temporary state.
func _restore_inventory_state(state: Dictionary) -> void:
	var loaded_items: Dictionary = {}

	for key_variant: Variant in state.keys():
		var item_id := StringName(String(key_variant))
		loaded_items[item_id] = maxi(
			int(state.get(key_variant, 0)),
			0
		)

	InventorySystem.set("_items", loaded_items)
	InventorySystem.inventory_reset.emit(
		InventorySystem.get_all_items()
	)

	if debug_log:
		print(
			"[SaveSystem] inventory restored items=",
			InventorySystem.get_all_items()
		)


# Restores the inventory layout from saved or temporary state.
func _restore_inventory_layout(saved_ids: Array) -> void:
	InventoryLayoutSystem.reset_to_defaults()

	var count: int = mini(
		saved_ids.size(),
		InventoryLayoutSystem.get_slot_count()
	)

	for slot_index: int in range(count):
		var item_id := StringName(
			String(saved_ids[slot_index])
		)

		if (
			item_id == &""
			or not ItemCatalogSystem.has_item(item_id)
		):
			continue

		InventoryLayoutSystem.move_item_to_slot(
			item_id,
			slot_index
		)


# Restores the hotbar from saved or temporary state.
func _restore_hotbar(saved_ids: Array) -> void:
	for slot_index: int in range(
		HotbarSystem.get_slot_count()
	):
		HotbarSystem.clear_slot(slot_index)

	var count: int = mini(
		saved_ids.size(),
		HotbarSystem.get_slot_count()
	)

	for slot_index: int in range(count):
		var item_id := StringName(
			String(saved_ids[slot_index])
		)

		if (
			item_id == &""
			or not ItemCatalogSystem.has_item(item_id)
		):
			continue

		HotbarSystem.assign_item(
			slot_index,
			item_id
		)


# Captures the selection state for save, restore, or validation.
func _capture_selection_state() -> Dictionary:
	var current: PlantData = (
		PlantSelectionSystem.get_current_plant()
	)

	return {
		"selected_id": (
			""
			if current == null
			else String(current.seed_item_id)
		)
	}


# Restores the selection state from saved or temporary state.
func _restore_selection_state(state: Dictionary) -> void:
	var selected_id: String = String(
		state.get("selected_id", "")
	)

	if selected_id == "":
		PlantSelectionSystem.deselect_plant()
		return

	var plant_data: PlantData = (
		PlantSelectionSystem.get_plant_by_id(
			StringName(selected_id)
		)
	)

	if (
		plant_data != null
		and PlantSelectionSystem.is_plant_available(
			plant_data
		)
	):
		PlantSelectionSystem.set_plant(plant_data)
	else:
		PlantSelectionSystem.deselect_plant()


# Captures the biome state for save, restore, or validation.
func _capture_biome_state() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var plantable_layer: int = _find_layer_by_name(
		"Plantable"
	)

	if plantable_layer < 0:
		return result

	for cell: Vector2i in _tilemap.get_used_cells(
		plantable_layer
	):
		var stats: Dictionary = BiomeSystem.get_zone_stats(
			cell
		)

		if stats.is_empty():
			continue

		var saved_stats: Dictionary = {}

		for key: String in BIOME_NUMERIC_KEYS:
			saved_stats[key] = float(
				stats.get(key, 0.0)
			)

		result.append({
			"x": cell.x,
			"y": cell.y,
			"stats": saved_stats
		})

	return result


# Restores the biome state from saved or temporary state.
func _restore_biome_state(entries: Array) -> void:
	var zone_stats_variant: Variant = BiomeSystem.get(
		"_zone_stats"
	)

	if typeof(zone_stats_variant) != TYPE_DICTIONARY:
		return

	var zone_stats: Dictionary = zone_stats_variant
	var applied_zones: Dictionary = {}

	for entry_variant: Variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue

		var entry: Dictionary = entry_variant
		var cell := Vector2i(
			int(entry.get("x", 0)),
			int(entry.get("y", 0))
		)
		var zone_id: int = BiomeSystem.get_zone_id(cell)

		if zone_id < 0 or applied_zones.has(zone_id):
			continue

		var stats_variant: Variant = entry.get("stats", {})

		if typeof(stats_variant) != TYPE_DICTIONARY:
			continue

		var saved_stats: Dictionary = stats_variant
		var current_stats: Dictionary = zone_stats.get(
			zone_id,
			{}
		)

		if current_stats.is_empty():
			continue

		for key: String in BIOME_NUMERIC_KEYS:
			if saved_stats.has(key):
				current_stats[key] = float(
					saved_stats[key]
				)

		zone_stats[zone_id] = current_stats
		applied_zones[zone_id] = true

	BiomeSystem.set("_zone_stats", zone_stats)

	if debug_log:
		print(
			"[SaveSystem] biome restored zones=",
			applied_zones.size()
		)


# Restores the clock state from saved or temporary state.
func _restore_clock_state(state: Dictionary) -> void:
	Clock.day = maxi(
		int(state.get("day", Clock.start_day)),
		1
	)
	Clock.minute_of_day = clampi(
		int(
			state.get(
				"minute_of_day",
				Clock.start_minute_of_day
			)
		),
		0,
		Clock.MINUTES_PER_DAY - 1
	)
	Clock.set("_game_seconds_accum", 0.0)

	Clock.time_changed.emit(
		Clock.day,
		Clock.minute_of_day,
		Clock.get_time_of_day()
	)
	Clock.hour_changed.emit(
		Clock.get_hour()
	)


# Restores the weather state from saved or temporary state.
func _restore_weather_state(state: Dictionary) -> void:
	WeatherSystem.load_save_state(state)

	# Re-publish the saved time/weather climate without advancing simulation
	# or adding rain moisture.
	WeatherSystem.on_world_tick(
		Clock.day,
		Clock.minute_of_day,
		0
	)

	if debug_log:
		print(
			"[SaveSystem] weather restored value=",
			WeatherSystem.current_weather,
			" remaining=",
			WeatherSystem.weather_remaining_minutes,
			"m"
		)


# Captures the plants state for save, restore, or validation.
func _capture_plants_state() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var plants_parent: Node = _get_plants_parent()

	if plants_parent == null:
		return result

	for child: Node in plants_parent.get_children():
		var data_variant: Variant = child.get("data")

		if data_variant == null:
			continue

		var seed_id_variant: Variant = data_variant.get(
			"seed_item_id"
		)
		var seed_id: String = String(seed_id_variant)

		if seed_id == "":
			continue

		var anchor_variant: Variant = child.get(
			"anchor_cell"
		)
		var anchor: Vector2i = Vector2i.ZERO

		if typeof(anchor_variant) == TYPE_VECTOR2I:
			anchor = anchor_variant

		var occupied_cells: Array = []
		var occupied_variant: Variant = child.get(
			"occupied_cells"
		)

		if typeof(occupied_variant) == TYPE_ARRAY:
			for cell_variant: Variant in occupied_variant:
				if typeof(cell_variant) != TYPE_VECTOR2I:
					continue

				var occupied_cell: Vector2i = cell_variant
				occupied_cells.append({
					"x": occupied_cell.x,
					"y": occupied_cell.y
				})

		var node_2d := child as Node2D

		if node_2d == null:
			continue

		result.append({
			"seed_item_id": seed_id,
			"anchor_x": anchor.x,
			"anchor_y": anchor.y,
			"occupied_cells": occupied_cells,
			"world_x": node_2d.global_position.x,
			"world_y": node_2d.global_position.y,
			"stage": int(child.get("stage")),
			"health": float(child.get("health")),
			"growth_hours_accum": float(
				child.get("_growth_hours_accum")
			),
			"pest_level": float(
				child.get("pest_level")
			),
			"disease_level": float(
				child.get("disease_level")
			),
			"is_dead": bool(child.get("is_dead"))
		})

	return result


# Restores the plants state from saved or temporary state.
func _restore_plants_state(entries: Array) -> void:
	var plants_parent: Node = _get_plants_parent()
	var plant_scene: PackedScene = _get_plant_scene()

	if plants_parent == null or plant_scene == null:
		push_warning(
			"[SaveSystem] plant restore skipped: scene/parent missing."
		)
		return

	# Remove current runtime plants and immediately free their registry cells.
	for child: Node in plants_parent.get_children():
		if (
			child.get("data") != null
			and child.has_method("despawn")
		):
			child.call("despawn")

	var restored_count: int = 0

	for entry_variant: Variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue

		var entry: Dictionary = entry_variant
		var seed_id := StringName(
			String(entry.get("seed_item_id", ""))
		)
		var plant_data: PlantData = (
			PlantSelectionSystem.get_plant_by_id(
				seed_id
			)
		)

		if plant_data == null:
			push_warning(
				"[SaveSystem] saved plant definition missing id=%s"
				% String(seed_id)
			)
			continue

		var plant := plant_scene.instantiate() as Node2D

		if plant == null:
			continue

		var anchor := Vector2i(
			int(entry.get("anchor_x", 0)),
			int(entry.get("anchor_y", 0))
		)
		var occupied: Array[Vector2i] = []

		var occupied_variant: Variant = entry.get(
			"occupied_cells",
			[]
		)

		if typeof(occupied_variant) == TYPE_ARRAY:
			for cell_entry_variant: Variant in occupied_variant:
				if typeof(cell_entry_variant) != TYPE_DICTIONARY:
					continue

				var cell_entry: Dictionary = cell_entry_variant
				occupied.append(
					Vector2i(
						int(cell_entry.get("x", 0)),
						int(cell_entry.get("y", 0))
					)
				)

		if occupied.is_empty():
			occupied.append(anchor)

		var saved_stage: int = maxi(
			int(entry.get("stage", 0)),
			0
		)

		plant.name = "%s_%s_%s" % [
			plant_data.display_name,
			anchor.x,
			anchor.y
		]
		plant.set("data", plant_data)
		plant.set("start_stage", saved_stage)
		plant.set("anchor_cell", anchor)
		plant.set("occupied_cells", occupied)
		plant.global_position = Vector2(
			float(entry.get("world_x", 0.0)),
			float(entry.get("world_y", 0.0))
		)

		plants_parent.add_child(plant)

		plant.set("stage", saved_stage)
		plant.set(
			"health",
			clampf(
				float(
					entry.get(
						"health",
						plant_data.max_health
					)
				),
				0.0,
				plant_data.max_health
			)
		)
		plant.set(
			"_growth_hours_accum",
			maxf(
				float(
					entry.get(
						"growth_hours_accum",
						0.0
					)
				),
				0.0
			)
		)
		plant.set(
			"pest_level",
			clampf(
				float(entry.get("pest_level", 0.0)),
				0.0,
				1.0
			)
		)
		plant.set(
			"disease_level",
			clampf(
				float(entry.get("disease_level", 0.0)),
				0.0,
				1.0
			)
		)

		var dead: bool = bool(
			entry.get("is_dead", false)
		)
		plant.set("is_dead", dead)

		if dead:
			plant.set("enable_spread", false)

		if plant.has_method("_apply_stage"):
			plant.call("_apply_stage")

		if plant.has_method("_update_visual"):
			plant.call("_update_visual")

		if plant.has_method("_refresh_harvest_readiness"):
			plant.call("_refresh_harvest_readiness")

		if plant.has_method("_refresh_status_from_zone"):
			plant.call("_refresh_status_from_zone")

		for occupied_cell: Vector2i in occupied:
			PlantRegistry.register(
				occupied_cell,
				plant
			)

		restored_count += 1

	if debug_log:
		print(
			"[SaveSystem] plants restored count=",
			restored_count
		)


# Returns the plants parent.
func _get_plants_parent() -> Node:
	if _player == null:
		return null

	var parent_variant: Variant = _player.get(
		"plants_parent"
	)

	if parent_variant is Node:
		return parent_variant as Node

	return null


# Returns the plant scene.
func _get_plant_scene() -> PackedScene:
	if _player == null:
		return null

	var scene_variant: Variant = _player.get(
		"plant_scene"
	)

	if scene_variant is PackedScene:
		return scene_variant as PackedScene

	return null


# Finds the layer by name.
func _find_layer_by_name(layer_name: String) -> int:
	if _tilemap == null:
		return -1

	for index: int in range(
		_tilemap.get_layers_count()
	):
		if _tilemap.get_layer_name(index) == layer_name:
			return index

	return -1


# Handles string key dictionary.
func _string_key_dictionary(value: Variant) -> Dictionary:
	var result: Dictionary = {}

	if typeof(value) != TYPE_DICTIONARY:
		return result

	var source: Dictionary = value

	for key_variant: Variant in source.keys():
		result[String(key_variant)] = source[key_variant]

	return result


# Copies the variant dictionary.
func _copy_variant_dictionary(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}

	var source: Dictionary = value
	return source.duplicate(true)


# Reads a Dictionary value used by the regression checks.
func _dictionary_value(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}

	return value


# Converts generic array data to a string array.
func _string_array(values: Array) -> Array[String]:
	var result: Array[String] = []

	for value: Variant in values:
		result.append(String(value))

	return result


# Handles dictionary section.
func _dictionary_section(
	root: Dictionary,
	key: String
) -> Dictionary:
	var value: Variant = root.get(key, {})

	if typeof(value) != TYPE_DICTIONARY:
		return {}

	return value


# Handles array section.
func _array_section(
	root: Dictionary,
	key: String
) -> Array:
	var value: Variant = root.get(key, [])

	if typeof(value) != TYPE_ARRAY:
		return []

	return value


# Checks whether the world is configured.
func _is_world_configured() -> bool:
	return (
		_tilemap != null
		and _player != null
		and BuildSystem.has_method("get_save_state")
		and BuildSystem.has_method("load_save_state")
		and SprinklerSystem.has_method("get_save_state")
		and SprinklerSystem.has_method("load_save_state")
	)


# Reports a failed save operation.
func _fail_save(
	reason: String,
	is_autosave: bool = false
) -> bool:
	save_failed.emit(reason)

	_show_toast(
		"AUTOSAVE FAILED"
		if is_autosave
		else "SAVE FAILED"
	)

	push_warning(
		"[SaveSystem] %s FAILED reason=%s"
		% [
			"AUTOSAVE"
				if is_autosave
				else "SAVE",
			reason
		]
	)
	return false


# Reports a failed load operation.
func _fail_load(reason: String) -> bool:
	load_failed.emit(reason)
	_show_toast("LOAD FAILED")

	push_warning(
		"[SaveSystem] LOAD FAILED reason=%s"
		% reason
	)
	return false


# Creates the toast.
func _create_toast() -> void:
	_toast_layer = CanvasLayer.new()
	_toast_layer.name = "SaveToastLayer"
	_toast_layer.layer = 38
	add_child(_toast_layer)

	_toast_panel = PanelContainer.new()
	_toast_panel.anchor_left = 0.5
	_toast_panel.anchor_right = 0.5
	_toast_panel.anchor_top = 0.0
	_toast_panel.anchor_bottom = 0.0
	_toast_panel.offset_left = -105.0
	_toast_panel.offset_right = 105.0
	_toast_panel.offset_top = 22.0
	_toast_panel.offset_bottom = 64.0
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.visible = false
	_toast_layer.add_child(_toast_panel)

	_toast_label = Label.new()
	_toast_label.custom_minimum_size = Vector2(
		210.0,
		38.0
	)
	_toast_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_toast_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)
	_toast_label.add_theme_font_size_override(
		"font_size",
		15
	)
	_toast_label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	_toast_panel.add_child(_toast_label)


# Shows the toast.
func _show_toast(message: String) -> void:
	if _toast_panel == null:
		return

	if (
		_toast_tween != null
		and _toast_tween.is_valid()
	):
		_toast_tween.kill()

	_toast_label.text = message
	_toast_panel.visible = true
	_toast_panel.modulate = Color.WHITE

	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.1)
	_toast_tween.tween_property(
		_toast_panel,
		"modulate:a",
		0.0,
		0.25
	)
	_toast_tween.finished.connect(
		_hide_toast
	)


# Hides the toast.
func _hide_toast() -> void:
	_toast_panel.visible = false
	_toast_panel.modulate = Color.WHITE
