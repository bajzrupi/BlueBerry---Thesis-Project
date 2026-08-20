extends Node

# BlueBerry automated regression runner.
#
# Intended use:
# 1. Create a tiny dedicated RegressionTest.tscn with one Node.
# 2. Attach this script to that Node.
# 3. Run the current scene (F6).
#
# The runner instantiates the real gameplay scene, waits for every world-bound
# system to configure, captures an in-memory snapshot, runs transactional tests,
# restores the original runtime state, and prints one consolidated report.
#
# It NEVER calls SaveSystem.save_game() or load_game(), so existing Garden save
# files are not overwritten. The JSON test uses its own temporary file only.

@export_category("Runner")

@export_file("*.tscn")
var gameplay_scene_path: String = "res://Scenes/test_level.tscn"

@export var run_on_ready: bool = true

# Runs 30 in-game days by calling the real Clock tick path while autosave and
# natural Random Events are temporarily disabled.
@export var include_30_day_soak_test: bool = true

# Writes and reads one temporary JSON file:
# user://blueberry_regression_tmp.json
@export var include_temp_json_file_test: bool = true

# Useful for CI/headless runs later. Keep false for normal editor testing.
@export var quit_after_suite: bool = false

@export_category("Output")

@export var print_pass_lines: bool = true
@export var print_balance_snapshot: bool = true


const TEMP_JSON_PATH: String = "user://blueberry_regression_tmp.json"

var _passed: int = 0
var _failed: int = 0
var _warnings: int = 0

var _running: bool = false
var _gameplay_instance: Node = null
var _snapshot: Dictionary = {}

var _previous_tree_paused: bool = false
var _previous_clock_paused: bool = false
var _previous_autosave_enabled: bool = true
var _previous_event_chance: float = 0.0
var _previous_first_event_day: int = 1
var _previous_mouse_mode: int = Input.MOUSE_MODE_HIDDEN


# Initializes this system when the node becomes ready.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	if run_on_ready:
		call_deferred("_start_suite")


# Starts the suite.
func _start_suite() -> void:
	if _running:
		return

	_running = true

	print("")
	print("============================================================")
	print(" BLUEBERRY AUTOMATED REGRESSION")
	print("============================================================")

	if not _instantiate_gameplay_world():
		_fail("SETUP", "Gameplay scene could not be instantiated.")
		_finish_suite()
		return

	# Give TestLevel, Player UI, and every Autoload-bound configure() call time
	# to complete before touching runtime state.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	if not _validate_test_environment():
		_finish_suite()
		return

	_capture_execution_state()
	_prepare_test_environment()

	_snapshot = _capture_runtime_snapshot()

	if _snapshot.is_empty():
		_fail("SETUP", "Could not capture runtime snapshot.")
		_restore_execution_state()
		_finish_suite()
		return

	await _run_core_suite()

	# The soak test intentionally runs from the original captured world rather
	# than from the mutated unit-test state.
	if include_30_day_soak_test:
		_restore_runtime_snapshot(_snapshot)
		_prepare_test_environment()
		_test_30_day_soak()

	# Always leave the instantiated gameplay world exactly where it was before
	# the transactional tests began.
	_restore_runtime_snapshot(_snapshot)
	_restore_execution_state()

	if print_balance_snapshot:
		_print_balance_snapshot()

	_finish_suite()


# Creates a gameplay world instance for regression testing.
func _instantiate_gameplay_world() -> bool:
	if gameplay_scene_path.strip_edges() == "":
		return false

	var packed_variant: Variant = load(gameplay_scene_path)

	if not packed_variant is PackedScene:
		return false

	var packed := packed_variant as PackedScene
	_gameplay_instance = packed.instantiate()

	if _gameplay_instance == null:
		return false

	_gameplay_instance.name = "RegressionGameplayWorld"
	add_child(_gameplay_instance)

	return true


# Validates the test environment.
func _validate_test_environment() -> bool:
	_section("SETUP / AUTOLOADS")

	var required_autoloads: Array[String] = [
		"Clock",
		"WeatherSystem",
		"BiomeSystem",
		"EconomySystem",
		"ProgressionSystem",
		"InventorySystem",
		"PlantSelectionSystem",
		"InventoryLayoutSystem",
		"HotbarSystem",
		"Toolsystem",
		"BuildSystem",
		"SprinklerSystem",
		"ChestSystem",
		"RepairSystem",
		"RandomEventSystem",
		"SaveSystem",
		"GameFlowSystem",
		"PauseMenuSystem",
		"CharacterSystem",
		"PlantInspectorSystem",
		"TimeSpeedControlSystem",
		"FertilizerInjectorSystem",
		"FertilizerInjectorInteractionSystem",
		"SoilNeutralizerSystem",
		"SoilNeutralizerInteractionSystem",
		"PlantProtectionStationSystem",
		"PlantProtectionStationInteractionSystem"
	]

	var all_present: bool = true

	for singleton_name: String in required_autoloads:
		var singleton: Node = get_node_or_null(
			"/root/%s" % singleton_name
		)

		if singleton == null:
			_fail(
				"AUTOLOAD",
				"Missing /root/%s" % singleton_name
			)
			all_present = false
		else:
			_pass("AUTOLOAD", singleton_name)

	if not all_present:
		return false

	var tilemap_variant: Variant = SaveSystem.get("_tilemap")
	var player_variant: Variant = SaveSystem.get("_player")

	_assert_true(
		"WORLD",
		tilemap_variant is TileMap,
		"SaveSystem has configured TileMap"
	)
	_assert_true(
		"WORLD",
		player_variant is CharacterBody2D,
		"SaveSystem has configured Player"
	)
	_assert_true(
		"WORLD",
		bool(BuildSystem.call("_is_configured")),
		"BuildSystem configured"
	)
	_assert_true(
		"WORLD",
		bool(SprinklerSystem.get("_configured")),
		"SprinklerSystem configured"
	)

	var pending_event: String = String(
		RandomEventSystem.get("_pending_event_id")
	)

	if pending_event != "":
		_fail(
			"SETUP",
			"An unresolved Random Event popup is already open."
		)
		return false

	return _failed == 0


# Captures the execution state for save, restore, or validation.
func _capture_execution_state() -> void:
	_previous_tree_paused = get_tree().paused
	_previous_clock_paused = bool(
		Clock.get("_paused")
	)
	_previous_autosave_enabled = SaveSystem.autosave_enabled
	_previous_event_chance = RandomEventSystem.daily_event_chance
	_previous_first_event_day = RandomEventSystem.first_event_day
	_previous_mouse_mode = Input.get_mouse_mode()


# Prepares the test environment.
func _prepare_test_environment() -> void:
	# No production save writes and no surprise popup while the Clock is being
	# advanced directly by tests.
	SaveSystem.autosave_enabled = false
	RandomEventSystem.daily_event_chance = 0.0
	RandomEventSystem.first_event_day = 999999

	Clock.set_paused(true)
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if BuildSystem.is_active():
		BuildSystem.set_active(false)


# Restores the execution state from saved or temporary state.
func _restore_execution_state() -> void:
	SaveSystem.autosave_enabled = _previous_autosave_enabled
	RandomEventSystem.daily_event_chance = _previous_event_chance
	RandomEventSystem.first_event_day = _previous_first_event_day

	Clock.set_paused(_previous_clock_paused)
	get_tree().paused = _previous_tree_paused
	Input.set_mouse_mode(_previous_mouse_mode)


# Runs the main regression test suite.
func _run_core_suite() -> void:
	_test_default_contract()
	_test_economy()
	_test_progression()
	_test_inventory()
	_test_tools()
	_test_plant_data_catalog()
	_test_build_catalog()
	_test_biome_invariants()
	_test_clock_and_weather_timing()
	_test_time_speed_control()
	_test_maintenance_balance_contract()
	_test_pause_main_menu_contract()
	_test_health_harvest_rewards()
	_test_automation_unlock_framework()
	await _test_sprinkler_integration()
	await _test_fertilizer_injector_integration()
	await _test_soil_neutralizer_integration()
	await _test_plant_protection_integration()
	_test_random_event_modifiers()
	_test_memory_save_payload()

	if include_temp_json_file_test:
		_test_temp_json_roundtrip()


# ------------------------------------------------------------------
# Snapshot / restore
# ------------------------------------------------------------------

# Captures the runtime snapshot for save, restore, or validation.
func _capture_runtime_snapshot() -> Dictionary:
	var state: Dictionary = {
		"player": _call_dictionary(
			SaveSystem,
			"_capture_player_state"
		),
		"economy": {
			"money": EconomySystem.get_money()
		},
		"progression": _call_dictionary(
			SaveSystem,
			"_capture_progression_state"
		),
		"tools": Toolsystem.get_save_state().duplicate(true),
		"inventory": _call_dictionary(
			SaveSystem,
			"_capture_inventory_state"
		),
		"inventory_layout": _string_array(
			InventoryLayoutSystem.get_layout_ids()
		),
		"hotbar": _string_array(
			HotbarSystem.get_assignment_ids()
		),
		"plant_selection": _call_dictionary(
			SaveSystem,
			"_capture_selection_state"
		),
		"clock": {
			"day": Clock.day,
			"minute_of_day": Clock.minute_of_day
		},
		"weather": WeatherSystem.get_save_state().duplicate(true),
		"random_events": RandomEventSystem.get_save_state().duplicate(true),
		"build": BuildSystem.get_save_state().duplicate(true),
		"sprinklers": SprinklerSystem.get_save_state().duplicate(true),
		"fertilizer_injectors": FertilizerInjectorSystem.get_save_state().duplicate(true),
		"soil_neutralizers": SoilNeutralizerSystem.get_save_state().duplicate(true),
		"plant_protection_stations": PlantProtectionStationSystem.get_save_state().duplicate(true),
		"seed_storage": ChestSystem.get_save_state().duplicate(true),
		"biome": _call_array(
			SaveSystem,
			"_capture_biome_state"
		),
		"plants": _call_array(
			SaveSystem,
			"_capture_plants_state"
		)
	}

	return state


# Restores the runtime snapshot from saved or temporary state.
func _restore_runtime_snapshot(state: Dictionary) -> void:
	if state.is_empty():
		return

	# Same dependency order as SaveSystem.load_game(), but entirely in memory.
	SaveSystem.call(
		"_restore_progression_state",
		_dict_value(state.get("progression", {}))
	)
	SaveSystem.call(
		"_restore_economy_state",
		_dict_value(state.get("economy", {}))
	)

	Toolsystem.load_save_state(
		_dict_value(state.get("tools", {}))
	)

	SaveSystem.call(
		"_restore_inventory_state",
		_dict_value(state.get("inventory", {}))
	)
	SaveSystem.call(
		"_restore_inventory_layout",
		_array_value(state.get("inventory_layout", []))
	)
	SaveSystem.call(
		"_restore_hotbar",
		_array_value(state.get("hotbar", []))
	)

	BuildSystem.load_save_state(
		_array_value(state.get("build", []))
	)
	ChestSystem.load_save_state(
		_array_value(state.get("seed_storage", []))
	)

	SaveSystem.call(
		"_restore_clock_state",
		_dict_value(state.get("clock", {}))
	)

	SprinklerSystem.load_save_state(
		_array_value(state.get("sprinklers", []))
	)
	FertilizerInjectorSystem.load_save_state(
		_array_value(
			state.get(
				"fertilizer_injectors",
				[]
			)
		)
	)
	SoilNeutralizerSystem.load_save_state(
		_array_value(
			state.get(
				"soil_neutralizers",
				[]
			)
		)
	)
	PlantProtectionStationSystem.load_save_state(
		_array_value(
			state.get(
				"plant_protection_stations",
				[]
			)
		)
	)

	SaveSystem.call(
		"_restore_biome_state",
		_array_value(state.get("biome", []))
	)
	SaveSystem.call(
		"_restore_weather_state",
		_dict_value(state.get("weather", {}))
	)

	RandomEventSystem.load_save_state(
		_dict_value(state.get("random_events", {}))
	)

	SaveSystem.call(
		"_restore_player_state",
		_dict_value(state.get("player", {}))
	)
	SaveSystem.call(
		"_restore_plants_state",
		_array_value(state.get("plants", []))
	)
	SaveSystem.call(
		"_restore_selection_state",
		_dict_value(state.get("plant_selection", {}))
	)


# ------------------------------------------------------------------
# Tests
# ------------------------------------------------------------------

# Tests the default contract behavior in the regression suite.
func _test_default_contract() -> void:
	_section("NEW GAME DEFAULT CONTRACT")

	EconomySystem.reset_to_defaults()
	ProgressionSystem.reset_to_defaults()
	InventorySystem.reset_to_defaults()
	Toolsystem.reset_durability()
	Toolsystem.set_tool(Toolsystem.Tool.PLANT)
	Clock.reset_to_defaults()
	RandomEventSystem.reset_to_defaults()

	_assert_eq(
		"DEFAULT",
		EconomySystem.get_money(),
		50,
		"Starting money"
	)
	_assert_eq(
		"DEFAULT",
		ProgressionSystem.player_level,
		0,
		"Starting player level"
	)
	_assert_eq(
		"DEFAULT",
		ProgressionSystem.player_xp,
		0,
		"Starting player XP"
	)
	_assert_eq(
		"DEFAULT",
		ProgressionSystem.plant_unlock_tokens,
		0,
		"Starting plant unlock tokens"
	)
	_assert_eq(
		"DEFAULT",
		ProgressionSystem.build_cell_credits,
		0,
		"Starting build credits"
	)
	_assert_true(
		"DEFAULT",
		ProgressionSystem.is_plant_unlocked(
			ProgressionSystem.PLANT_LILY
		),
		"Lily starts unlocked"
	)
	_assert_true(
		"DEFAULT",
		not ProgressionSystem.is_plant_unlocked(
			ProgressionSystem.PLANT_CACTUS
		),
		"Cactus starts locked"
	)
	_assert_eq(
		"DEFAULT",
		InventorySystem.get_amount(
			InventorySystem.ITEM_LILY_SEED
		),
		5,
		"Starting Lily seed amount"
	)
	_assert_eq(
		"DEFAULT",
		Clock.day,
		1,
		"Starting day"
	)
	_assert_eq(
		"DEFAULT",
		Clock.minute_of_day,
		8 * 60,
		"Starting time is 08:00"
	)
	_assert_approx(
		"DEFAULT",
		Clock.day_length_seconds,
		180.0,
		0.0001,
		"Full game day lasts 180 real seconds"
	)
	_assert_approx(
		"DEFAULT",
		RandomEventSystem.get_harvest_income_multiplier(),
		1.0,
		0.0001,
		"Random Event harvest multiplier baseline"
	)

	for terrain_id: StringName in ProgressionSystem.TRACKED_TERRAINS:
		_assert_eq(
			"DEFAULT",
			ProgressionSystem.get_terrain_level(terrain_id),
			1,
			"Terrain %s starts at Level 1" % String(terrain_id)
		)

	for equipment_id: StringName in ProgressionSystem.TRACKED_EQUIPMENT:
		_assert_eq(
			"DEFAULT",
			ProgressionSystem.get_equipment_level(equipment_id),
			1,
			"Equipment %s starts at Level 1" % String(equipment_id)
		)

	# Check the ACTUAL PackedScene rather than only plant.gd's script default.
	# This catches Inspector overrides such as a forgotten Start Stage = 2.
	var plant_scene_variant: Variant = load(
		"res://Scenes/plant.tscn"
	)

	if plant_scene_variant is PackedScene:
		var plant_probe: Node = (
			plant_scene_variant as PackedScene
		).instantiate()

		_assert_eq(
			"DEFAULT",
			int(plant_probe.get("start_stage")),
			0,
			"Plant scene start_stage"
		)

		plant_probe.free()
	else:
		_fail(
			"DEFAULT",
			"Could not load res://Scenes/plant.tscn"
		)


# Tests the economy behavior in the regression suite.
func _test_economy() -> void:
	_section("ECONOMY")

	EconomySystem.set_money(100, "REGRESSION")
	_assert_true(
		"ECONOMY",
		EconomySystem.can_afford(100),
		"Can afford exact balance"
	)
	_assert_true(
		"ECONOMY",
		EconomySystem.spend_money(40, "REGRESSION"),
		"Spend succeeds"
	)
	_assert_eq(
		"ECONOMY",
		EconomySystem.get_money(),
		60,
		"100 - 40 = 60"
	)
	_assert_true(
		"ECONOMY",
		not EconomySystem.spend_money(100, "REGRESSION"),
		"Overspend is rejected"
	)
	_assert_eq(
		"ECONOMY",
		EconomySystem.get_money(),
		60,
		"Rejected spend preserves balance"
	)
	_assert_true(
		"ECONOMY",
		EconomySystem.add_money(25, "REGRESSION"),
		"Add money succeeds"
	)
	_assert_eq(
		"ECONOMY",
		EconomySystem.get_money(),
		85,
		"60 + 25 = 85"
	)


# Tests the progression behavior in the regression suite.
func _test_progression() -> void:
	_section("PROGRESSION / MILESTONES")

	EconomySystem.reset_to_defaults()
	ProgressionSystem.reset_to_defaults()

	var xp_to_level_10: int = 0

	for level: int in range(10):
		xp_to_level_10 += (
			ProgressionSystem.get_player_xp_required_for_next(
				level
			)
		)

	_assert_eq(
		"PROGRESSION",
		xp_to_level_10,
		1900,
		"Configured XP curve reaches Level 10 at 1900 total XP"
	)

	_assert_true(
		"PROGRESSION",
		ProgressionSystem.add_player_xp(
			xp_to_level_10,
			"REGRESSION"
		),
		"XP award accepted"
	)
	_assert_eq(
		"PROGRESSION",
		ProgressionSystem.player_level,
		10,
		"Player reaches Level 10"
	)
	_assert_eq(
		"PROGRESSION",
		ProgressionSystem.player_xp,
		0,
		"No remainder at exact Level 10 threshold"
	)
	_assert_eq(
		"PROGRESSION",
		EconomySystem.get_money(),
		EconomySystem.DEFAULT_MONEY + 100,
		"Starting balance + Level 10 milestone money"
	)
	_assert_eq(
		"PROGRESSION",
		ProgressionSystem.plant_unlock_tokens,
		1,
		"Level 10 unlock token"
	)
	_assert_eq(
		"PROGRESSION",
		ProgressionSystem.build_cell_credits,
		100,
		"Level 10 build credits"
	)


# Tests the inventory behavior in the regression suite.
func _test_inventory() -> void:
	_section("INVENTORY")

	InventorySystem.reset_to_defaults()

	var lily: StringName = InventorySystem.ITEM_LILY_SEED

	_assert_eq(
		"INVENTORY",
		InventorySystem.get_amount(lily),
		5,
		"Default Lily stack"
	)
	_assert_true(
		"INVENTORY",
		InventorySystem.add_item(lily, 3),
		"Add three Lily seeds"
	)
	_assert_eq(
		"INVENTORY",
		InventorySystem.get_amount(lily),
		8,
		"Seed stack becomes 8"
	)
	_assert_true(
		"INVENTORY",
		InventorySystem.remove_item(lily, 2),
		"Remove two Lily seeds"
	)
	_assert_eq(
		"INVENTORY",
		InventorySystem.get_amount(lily),
		6,
		"Seed stack becomes 6"
	)
	_assert_true(
		"INVENTORY",
		not InventorySystem.remove_item(lily, 999),
		"Insufficient stock is rejected"
	)
	_assert_eq(
		"INVENTORY",
		InventorySystem.get_amount(lily),
		6,
		"Rejected removal preserves stock"
	)


# Tests the tools behavior in the regression suite.
func _test_tools() -> void:
	_section("TOOLS / DURABILITY")

	EconomySystem.set_money(100, "REGRESSION")
	Toolsystem.reset_durability()

	var water_tool: int = Toolsystem.Tool.WATER

	_assert_eq(
		"TOOLS",
		Toolsystem.get_durability(water_tool),
		100,
		"Watering Can starts at 100 durability"
	)
	_assert_true(
		"TOOLS",
		Toolsystem.consume_use(water_tool),
		"Watering Can use succeeds"
	)
	_assert_eq(
		"TOOLS",
		Toolsystem.get_durability(water_tool),
		99,
		"Watering Can loses one durability"
	)

	var repair_result: Dictionary = Toolsystem.repair_tool(
		water_tool,
		1
	)

	_assert_true(
		"TOOLS",
		bool(repair_result.get("ok", false)),
		"One-point repair succeeds"
	)
	_assert_eq(
		"TOOLS",
		Toolsystem.get_durability(water_tool),
		100,
		"Repair returns Watering Can to 100"
	)


# Tests the plant data catalog behavior in the regression suite.
func _test_plant_data_catalog() -> void:
	_section("PLANT DATA")

	var plants: Array[PlantData] = (
		PlantSelectionSystem.get_all_plants()
	)

	_assert_true(
		"PLANT DATA",
		plants.size() >= 2,
		"Plant catalog contains the alpha plants"
	)

	for plant_data: PlantData in plants:
		if plant_data == null:
			_fail("PLANT DATA", "Null PlantData resource")
			continue

		var label: String = plant_data.display_name

		_assert_true(
			"PLANT DATA",
			plant_data.seed_item_id != &"",
			"%s has seed_item_id" % label
		)
		_assert_true(
			"PLANT DATA",
			plant_data.planting_cost > 0,
			"%s planting cost is positive" % label
		)
		_assert_true(
			"PLANT DATA",
			plant_data.max_stage >= 1,
			"%s has at least one growth stage" % label
		)
		_assert_true(
			"PLANT DATA",
			plant_data.days_to_next_stage.size()
			>= plant_data.max_stage,
			"%s has enough stage timing entries" % label
		)
		_assert_true(
			"PLANT DATA",
			plant_data.harvest_yield_min >= 0
			and plant_data.harvest_yield_max
			>= plant_data.harvest_yield_min,
			"%s harvest yield range is valid" % label
		)
		_assert_true(
			"PLANT DATA",
			plant_data.seed_buy_price >= 0
			and plant_data.seed_sell_price >= 0,
			"%s shop prices are non-negative" % label
		)
		_assert_true(
			"PLANT DATA",
			not plant_data.allowed_soils.is_empty(),
			"%s has at least one allowed soil" % label
		)


# Tests the build catalog behavior in the regression suite.
func _test_build_catalog() -> void:
	_section("BUILD SYSTEM")

	var catalog: Array[Dictionary] = BuildSystem.get_build_catalog()
	var seen_ids: Dictionary = {}
	var invalid_id_count: int = 0
	var duplicate_id_count: int = 0
	var negative_cost_count: int = 0

	if catalog.is_empty():
		_fail("BUILD", "Build catalog is empty")
		return

	for item: Dictionary in catalog:
		var build_id: String = String(
			item.get("id", "")
		)

		if build_id == "":
			invalid_id_count += 1
			continue

		if seen_ids.has(build_id):
			duplicate_id_count += 1
		else:
			seen_ids[build_id] = true

		if int(item.get("cost", 0)) < 0:
			negative_cost_count += 1

	_assert_eq(
		"BUILD",
		invalid_id_count,
		0,
		"All build items have IDs"
	)
	_assert_eq(
		"BUILD",
		duplicate_id_count,
		0,
		"Build IDs are unique"
	)
	_assert_eq(
		"BUILD",
		negative_cost_count,
		0,
		"Build costs are non-negative"
	)
	_assert_true(
		"BUILD",
		seen_ids.has("sprinkler"),
		"Field Sprinkler exists in build catalog"
	)

	if (
		invalid_id_count == 0
		and duplicate_id_count == 0
		and negative_cost_count == 0
	):
		_pass(
			"BUILD",
			"Validated %d catalog entries"
			% catalog.size()
		)

	var saved_builds: Array = BuildSystem.get_save_state()
	var saved_cells: Dictionary = {}
	var invalid_save_entries: int = 0
	var duplicate_save_cells: int = 0

	for entry_variant: Variant in saved_builds:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			invalid_save_entries += 1
			continue

		var entry: Dictionary = entry_variant
		var key: String = "%d,%d" % [
			int(entry.get("x", 0)),
			int(entry.get("y", 0))
		]

		if saved_cells.has(key):
			duplicate_save_cells += 1
		else:
			saved_cells[key] = true

	_assert_eq(
		"BUILD",
		invalid_save_entries,
		0,
		"Build save state contains only dictionaries"
	)
	_assert_eq(
		"BUILD",
		duplicate_save_cells,
		0,
		"Build save cells are unique"
	)


# Tests the biome invariants behavior in the regression suite.
func _test_biome_invariants() -> void:
	_section("BIOME INVARIANTS")

	var zone_stats_variant: Variant = BiomeSystem.get(
		"_zone_stats"
	)

	if typeof(zone_stats_variant) != TYPE_DICTIONARY:
		_fail("BIOME", "_zone_stats is not a Dictionary")
		return

	var zones: Dictionary = zone_stats_variant

	if zones.is_empty():
		_fail("BIOME", "Biome zones were not built from the map")
		return

	var invalid_zone_records: int = 0
	var invalid_moisture: int = 0
	var invalid_nutrients: int = 0
	var invalid_ph: int = 0
	var invalid_pest: int = 0
	var invalid_disease: int = 0

	var min_moisture: float = 1.0
	var max_moisture: float = 0.0
	var min_nutrients: float = 1.0
	var max_nutrients: float = 0.0
	var min_pest: float = 1.0
	var max_pest: float = 0.0
	var min_disease: float = 1.0
	var max_disease: float = 0.0

	for zone_id_variant: Variant in zones.keys():
		var stats_variant: Variant = zones[zone_id_variant]

		if typeof(stats_variant) != TYPE_DICTIONARY:
			invalid_zone_records += 1
			continue

		var stats: Dictionary = stats_variant
		var moisture: float = float(stats.get("moisture", 0.0))
		var nutrients: float = float(stats.get("nutrients", 0.0))
		var ph: float = float(stats.get("ph", 7.0))
		var pest: float = float(stats.get("pest_pressure", 0.0))
		var disease: float = float(stats.get("disease_pressure", 0.0))

		min_moisture = minf(min_moisture, moisture)
		max_moisture = maxf(max_moisture, moisture)
		min_nutrients = minf(min_nutrients, nutrients)
		max_nutrients = maxf(max_nutrients, nutrients)
		min_pest = minf(min_pest, pest)
		max_pest = maxf(max_pest, pest)
		min_disease = minf(min_disease, disease)
		max_disease = maxf(max_disease, disease)

		if moisture < 0.0 or moisture > 1.0:
			invalid_moisture += 1
		if nutrients < 0.0 or nutrients > 1.0:
			invalid_nutrients += 1
		if ph < 0.0 or ph > 14.0:
			invalid_ph += 1
		if pest < 0.0 or pest > 1.0:
			invalid_pest += 1
		if disease < 0.0 or disease > 1.0:
			invalid_disease += 1

	_assert_eq(
		"BIOME",
		invalid_zone_records,
		0,
		"All zone records are dictionaries"
	)
	_assert_eq(
		"BIOME",
		invalid_moisture,
		0,
		"All moisture values remain within 0..1"
	)
	_assert_eq(
		"BIOME",
		invalid_nutrients,
		0,
		"All nutrient values remain within 0..1"
	)
	_assert_eq(
		"BIOME",
		invalid_ph,
		0,
		"All pH values remain within 0..14"
	)
	_assert_eq(
		"BIOME",
		invalid_pest,
		0,
		"All pest-pressure values remain within 0..1"
	)
	_assert_eq(
		"BIOME",
		invalid_disease,
		0,
		"All disease-pressure values remain within 0..1"
	)

	if (
		invalid_zone_records == 0
		and invalid_moisture == 0
		and invalid_nutrients == 0
		and invalid_ph == 0
		and invalid_pest == 0
		and invalid_disease == 0
	):
		_pass(
			"BIOME",
			"%d zones valid | moisture %.3f..%.3f | nutrients %.3f..%.3f | pest %.3f..%.3f | disease %.3f..%.3f"
			% [
				zones.size(),
				min_moisture,
				max_moisture,
				min_nutrients,
				max_nutrients,
				min_pest,
				max_pest,
				min_disease,
				max_disease
			]
		)


# Tests the clock and weather timing behavior in the regression suite.
func _test_clock_and_weather_timing() -> void:
	_section("CLOCK / WEATHER EPISODES")

	_assert_approx(
		"WEATHER",
		Clock.day_length_seconds,
		180.0,
		0.0001,
		"3-minute full-day timing"
	)

	_assert_eq(
		"WEATHER",
		WeatherSystem.rain_duration_min_hours,
		4,
		"Rain minimum duration"
	)
	_assert_eq(
		"WEATHER",
		WeatherSystem.rain_duration_max_hours,
		8,
		"Rain maximum duration"
	)
	_assert_eq(
		"WEATHER",
		WeatherSystem.coldsnap_duration_min_hours,
		6,
		"Cold Snap minimum duration"
	)
	_assert_eq(
		"WEATHER",
		WeatherSystem.coldsnap_duration_max_hours,
		10,
		"Cold Snap maximum duration"
	)

	var original_weather: Dictionary = (
		WeatherSystem.get_save_state().duplicate(true)
	)

	# CLOUDY has no direct biome moisture side effect, so it is ideal for a
	# deterministic expiry test.
	WeatherSystem.load_save_state(
		{
			"current_weather": WeatherSystem.Weather.CLOUDY,
			"remaining_minutes": 120
		}
	)

	_assert_eq(
		"WEATHER",
		WeatherSystem.current_weather,
		WeatherSystem.Weather.CLOUDY,
		"Synthetic Cloudy episode loads"
	)
	_assert_eq(
		"WEATHER",
		WeatherSystem.weather_remaining_minutes,
		120,
		"Weather remaining time restores"
	)

	WeatherSystem.on_world_tick(
		Clock.day,
		Clock.minute_of_day,
		60
	)

	_assert_eq(
		"WEATHER",
		WeatherSystem.current_weather,
		WeatherSystem.Weather.CLOUDY,
		"Episode remains active before expiry"
	)
	_assert_eq(
		"WEATHER",
		WeatherSystem.weather_remaining_minutes,
		60,
		"Episode timer decreases by one game hour"
	)

	WeatherSystem.on_world_tick(
		Clock.day,
		Clock.minute_of_day,
		60
	)

	_assert_eq(
		"WEATHER",
		WeatherSystem.current_weather,
		WeatherSystem.Weather.CLEAR,
		"Expired weather returns to Clear"
	)
	_assert_eq(
		"WEATHER",
		WeatherSystem.weather_remaining_minutes,
		0,
		"Expired weather timer reaches zero"
	)

	var persisted: Dictionary = {
		"current_weather": WeatherSystem.Weather.RAIN,
		"remaining_minutes": 300
	}

	WeatherSystem.load_save_state(persisted)

	var saved_again: Dictionary = WeatherSystem.get_save_state()

	_assert_eq(
		"WEATHER",
		int(saved_again.get("current_weather", -1)),
		WeatherSystem.Weather.RAIN,
		"Weather type serializes"
	)
	_assert_eq(
		"WEATHER",
		int(saved_again.get("remaining_minutes", -1)),
		300,
		"Weather remaining duration serializes"
	)

	WeatherSystem.load_save_state(
		original_weather
	)

	WeatherSystem.on_world_tick(
		Clock.day,
		Clock.minute_of_day,
		0
	)


# Tests the time speed control behavior in the regression suite.
func _test_time_speed_control() -> void:
	_section("TIME SPEED CONTROL")

	Clock.reset_time_scale()

	_assert_approx(
		"TIME SPEED",
		Clock.get_time_scale(),
		1.0,
		0.0001,
		"Default gameplay speed is 1x"
	)
	_assert_approx(
		"TIME SPEED",
		Clock.get_effective_day_length_seconds(),
		180.0,
		0.0001,
		"1x effective day is 180 real seconds"
	)

	Clock.set_time_scale(3.0)

	_assert_approx(
		"TIME SPEED",
		Clock.get_time_scale(),
		3.0,
		0.0001,
		"3x gameplay speed"
	)
	_assert_approx(
		"TIME SPEED",
		Clock.get_effective_day_length_seconds(),
		60.0,
		0.0001,
		"3x effective day is 60 real seconds"
	)

	Clock.set_time_scale(6.0)

	_assert_approx(
		"TIME SPEED",
		Clock.get_time_scale(),
		6.0,
		0.0001,
		"6x gameplay speed"
	)
	_assert_approx(
		"TIME SPEED",
		Clock.get_effective_day_length_seconds(),
		30.0,
		0.0001,
		"6x effective day is 30 real seconds"
	)

	Clock.reset_time_scale()

	_assert_approx(
		"TIME SPEED",
		Clock.get_time_scale(),
		1.0,
		0.0001,
		"Speed reset returns to 1x"
	)


# Tests the maintenance balance contract behavior in the regression suite.
func _test_maintenance_balance_contract() -> void:
	_section("PLANT CARE BALANCE")

	_assert_approx(
		"CARE",
		BiomeSystem.base_moisture_loss_per_hour,
		0.025,
		0.0001,
		"Base moisture loss"
	)
	_assert_approx(
		"CARE",
		BiomeSystem.base_nutrients_loss_per_hour,
		0.008,
		0.0001,
		"Base nutrient loss"
	)
	_assert_approx(
		"CARE",
		BiomeSystem.base_ph_drift_per_day,
		0.25,
		0.0001,
		"Base pH drift per day"
	)
	_assert_approx(
		"CARE",
		BiomeSystem.ph_drift_target_loamy,
		5.4,
		0.0001,
		"Loamy natural pH stress target"
	)
	_assert_approx(
		"CARE",
		BiomeSystem.ph_drift_target_sandy,
		8.6,
		0.0001,
		"Sandy natural pH stress target"
	)
	_assert_approx(
		"CARE",
		BiomeSystem.water_retention_sandy,
		0.70,
		0.0001,
		"Sandy water retention"
	)
	_assert_approx(
		"CARE",
		BiomeSystem.pressure_adjust_per_day,
		0.60,
		0.0001,
		"Biological pressure response"
	)

	var plant_scene_variant: Variant = load(
		"res://Scenes/plant.tscn"
	)

	if not plant_scene_variant is PackedScene:
		_fail(
			"CARE",
			"Could not load plant.tscn"
		)
		return

	var plant_probe: Node = (
		plant_scene_variant as PackedScene
	).instantiate()

	_assert_approx(
		"CARE",
		float(plant_probe.get("pest_seed_per_hour")),
		0.06,
		0.0001,
		"Pest infection seed rate"
	)
	_assert_approx(
		"CARE",
		float(plant_probe.get("disease_seed_per_hour")),
		0.05,
		0.0001,
		"Disease infection seed rate"
	)
	_assert_approx(
		"CARE",
		float(plant_probe.get("pest_natural_recovery_per_hour")),
		0.004,
		0.0001,
		"Pest natural recovery"
	)
	_assert_approx(
		"CARE",
		float(plant_probe.get("disease_natural_recovery_per_hour")),
		0.003,
		0.0001,
		"Disease natural recovery"
	)

	plant_probe.free()

	var lily: PlantData = PlantSelectionSystem.get_plant_by_id(
		&"lily_seed"
	)
	var cactus: PlantData = PlantSelectionSystem.get_plant_by_id(
		&"cactus_seed"
	)

	if lily != null:
		_assert_approx(
			"CARE",
			lily.health_decay_per_hour,
			0.50,
			0.0001,
			"Lily health decay"
		)
		_assert_approx(
			"CARE",
			lily.health_recover_per_hour,
			0.60,
			0.0001,
			"Lily health recovery"
		)
		_assert_approx(
			"CARE",
			lily.optimal_ph_min,
			6.2,
			0.0001,
			"Lily pH minimum"
		)
		_assert_approx(
			"CARE",
			lily.optimal_ph_max,
			7.2,
			0.0001,
			"Lily pH maximum"
		)

	if cactus != null:
		_assert_approx(
			"CARE",
			cactus.health_decay_per_hour,
			0.45,
			0.0001,
			"Cactus health decay"
		)
		_assert_approx(
			"CARE",
			cactus.health_recover_per_hour,
			0.60,
			0.0001,
			"Cactus health recovery"
		)
		_assert_approx(
			"CARE",
			cactus.optimal_ph_min,
			6.8,
			0.0001,
			"Cactus pH minimum"
		)
		_assert_approx(
			"CARE",
			cactus.optimal_ph_max,
			7.9,
			0.0001,
			"Cactus pH maximum"
		)


# Tests the pause main menu contract behavior in the regression suite.
func _test_pause_main_menu_contract() -> void:
	_section("PAUSE -> MAIN MENU")

	_assert_true(
		"NAVIGATION",
		GameFlowSystem.has_method("return_to_main_menu"),
		"GameFlow exposes return_to_main_menu"
	)
	_assert_true(
		"NAVIGATION",
		PauseMenuSystem.has_method("_on_main_menu_pressed"),
		"Pause Menu exposes Main Menu action"
	)
	_assert_true(
		"NAVIGATION",
		PauseMenuSystem.has_method("_has_gameplay_world"),
		"Pause Menu is guarded to gameplay worlds"
	)


# Tests the health harvest rewards behavior in the regression suite.
func _test_health_harvest_rewards() -> void:
	_section("HEALTH-BASED HARVEST REWARDS")

	var player_variant: Variant = SaveSystem.get("_player")

	if not player_variant is CharacterBody2D:
		_fail(
			"HARVEST HEALTH",
			"Configured Player unavailable"
		)
		return

	var player := player_variant as CharacterBody2D

	if not player.has_method("_calculate_harvest_quality_rewards"):
		_fail(
			"HARVEST HEALTH",
			"Player harvest-quality calculator missing"
		)
		return

	var healthy_variant: Variant = player.call(
		"_calculate_harvest_quality_rewards",
		5,
		100,
		1.0,
		1.0
	)

	if not healthy_variant is Dictionary:
		_fail(
			"HARVEST HEALTH",
			"Healthy reward calculation did not return Dictionary"
		)
		return

	var healthy := healthy_variant as Dictionary

	_assert_eq(
		"HARVEST HEALTH",
		int(healthy.get("seed_gain", -1)),
		5,
		"Full health preserves seed reward"
	)
	_assert_eq(
		"HARVEST HEALTH",
		int(healthy.get("money_gain", -1)),
		100,
		"Full health preserves money reward"
	)

	var stressed_variant: Variant = player.call(
		"_calculate_harvest_quality_rewards",
		5,
		100,
		0.40,
		1.0
	)

	if not stressed_variant is Dictionary:
		_fail(
			"HARVEST HEALTH",
			"Stressed reward calculation did not return Dictionary"
		)
		return

	var stressed := stressed_variant as Dictionary

	_assert_eq(
		"HARVEST HEALTH",
		int(stressed.get("seed_gain", -1)),
		2,
		"40% health reduces 5 seeds to 2"
	)
	_assert_eq(
		"HARVEST HEALTH",
		int(stressed.get("money_gain", -1)),
		64,
		"40% health reduces $100 to $64"
	)

	var critical_variant: Variant = player.call(
		"_calculate_harvest_quality_rewards",
		1,
		100,
		0.10,
		1.0
	)

	if critical_variant is Dictionary:
		var critical := critical_variant as Dictionary

		_assert_eq(
			"HARVEST HEALTH",
			int(critical.get("seed_gain", -1)),
			0,
			"Critical health can produce zero seeds"
		)
		_assert_eq(
			"HARVEST HEALTH",
			int(critical.get("money_gain", -1)),
			46,
			"10% health retains only 46% money"
		)
	else:
		_fail(
			"HARVEST HEALTH",
			"Critical reward calculation did not return Dictionary"
		)


# Tests the automation unlock framework behavior in the regression suite.
func _test_automation_unlock_framework() -> void:
	_section("AUTOMATION UNLOCK FRAMEWORK")

	var original_level: int = ProgressionSystem.player_level

	ProgressionSystem.player_level = 0

	_assert_true(
		"AUTOMATION",
		not ProgressionSystem.is_automation_build_unlocked(
			&"sprinkler"
		),
		"Sprinkler locked below Level 10"
	)
	_assert_eq(
		"AUTOMATION",
		ProgressionSystem.get_automation_unlock_level(
			&"sprinkler"
		),
		10,
		"Sprinkler unlock Level"
	)
	_assert_eq(
		"AUTOMATION",
		ProgressionSystem.get_automation_unlock_level(
			&"fertilizer_injector"
		),
		20,
		"Fertilizer Injector unlock Level"
	)

	_assert_eq(
		"AUTOMATION",
		ProgressionSystem.get_automation_unlock_level(
			&"soil_neutralizer"
		),
		30,
		"Soil Neutralizer unlock Level"
	)

	_assert_eq(
		"AUTOMATION",
		ProgressionSystem.get_automation_unlock_level(
			&"plant_protection_station"
		),
		40,
		"Plant Protection Station unlock Level"
	)

	ProgressionSystem.player_level = 10

	_assert_true(
		"AUTOMATION",
		ProgressionSystem.is_automation_build_unlocked(
			&"sprinkler"
		),
		"Sprinkler unlocked at Level 10"
	)
	_assert_true(
		"AUTOMATION",
		not ProgressionSystem.is_automation_build_unlocked(
			&"fertilizer_injector"
		),
		"Fertilizer Injector remains locked at Level 10"
	)
	_assert_true(
		"AUTOMATION",
		not ProgressionSystem.is_automation_build_unlocked(
			&"soil_neutralizer"
		),
		"Soil Neutralizer remains locked at Level 10"
	)

	ProgressionSystem.player_level = 20

	_assert_true(
		"AUTOMATION",
		ProgressionSystem.is_automation_build_unlocked(
			&"fertilizer_injector"
		),
		"Fertilizer Injector unlocked at Level 20"
	)
	_assert_true(
		"AUTOMATION",
		not ProgressionSystem.is_automation_build_unlocked(
			&"soil_neutralizer"
		),
		"Soil Neutralizer remains locked at Level 20"
	)

	ProgressionSystem.player_level = 30

	_assert_true(
		"AUTOMATION",
		ProgressionSystem.is_automation_build_unlocked(
			&"soil_neutralizer"
		),
		"Soil Neutralizer unlocked at Level 30"
	)
	_assert_true(
		"AUTOMATION",
		not ProgressionSystem.is_automation_build_unlocked(
			&"plant_protection_station"
		),
		"Plant Protection Station remains locked at Level 30"
	)

	ProgressionSystem.player_level = 40

	_assert_true(
		"AUTOMATION",
		ProgressionSystem.is_automation_build_unlocked(
			&"plant_protection_station"
		),
		"Plant Protection Station unlocked at Level 40"
	)

	ProgressionSystem.player_level = original_level


# Tests the sprinkler integration behavior in the regression suite.
func _test_sprinkler_integration() -> void:
	_section("SPRINKLER / SHARED AUTOMATION INTEGRATION")

	_assert_true(
		"SPRINKLER",
		SprinklerSystem is AutomationMachineBase,
		"SprinklerSystem inherits AutomationMachineBase"
	)

	var intervals: Array[int] = (
		SprinklerSystem.get_interval_options()
	)

	_assert_eq(
		"SPRINKLER",
		intervals,
		[60, 180, 360, 720],
		"Allowed watering intervals"
	)

	var level_1: Dictionary = SprinklerSystem.get_level_definition(1)
	var level_2: Dictionary = SprinklerSystem.get_level_definition(2)
	var level_3: Dictionary = SprinklerSystem.get_level_definition(3)

	_assert_eq(
		"SPRINKLER",
		int(level_1.get("radius", 0)),
		2,
		"Level 1 radius"
	)
	_assert_approx(
		"SPRINKLER",
		float(level_1.get("moisture_per_cycle", 0.0)),
		0.12,
		0.0001,
		"Level 1 moisture"
	)
	_assert_eq(
		"SPRINKLER",
		int(level_2.get("radius", 0)),
		3,
		"Level 2 radius"
	)
	_assert_eq(
		"SPRINKLER",
		int(level_2.get("cost_to_reach", 0)),
		150,
		"Level 2 upgrade cost"
	)
	_assert_eq(
		"SPRINKLER",
		int(level_3.get("radius", 0)),
		4,
		"Level 3 radius"
	)
	_assert_eq(
		"SPRINKLER",
		int(level_3.get("cost_to_reach", 0)),
		350,
		"Level 3 upgrade cost"
	)

	# Integration test: automatically find a valid Loamy/Sandy outer edge,
	# place a real sprinkler through BuildSystem, then exercise its APIs.
	var tilemap_variant: Variant = SaveSystem.get("_tilemap")

	if not tilemap_variant is TileMap:
		_warn(
			"SPRINKLER",
			"No configured TileMap; machine integration skipped."
		)
		return

	var tilemap := tilemap_variant as TileMap

	ProgressionSystem.build_cell_credits = 5000
	ProgressionSystem.player_level = maxi(
		ProgressionSystem.player_level,
		10
	)
	BuildSystem.select_build(&"sprinkler")

	var placement_cell: Variant = _find_valid_sprinkler_edge(tilemap)

	if placement_cell == null:
		_warn(
			"SPRINKLER",
			"No free Loamy/Sandy outer-edge cell found; placement integration skipped."
		)
		return

	var cell: Vector2i = placement_cell

	_assert_true(
		"SPRINKLER",
		BuildSystem.is_sprinkler_biome_edge_cell(cell),
		"Chosen cell is a recognised Loamy/Sandy edge"
	)
	var placed: bool = BuildSystem.place_selected_at(cell)

	_assert_true(
		"SPRINKLER",
		placed,
		"BuildSystem places sprinkler on biome edge"
	)

	if not placed:
		return

	# AutomationMachineBase rebuilds machine registries from BuildSystem with
	# call_deferred(), so wait for the shared backend to finish its rebuild.
	await get_tree().process_frame
	await get_tree().process_frame

	_assert_true(
		"SPRINKLER",
		SprinklerSystem.has_sprinkler(cell),
		"Legacy sprinkler API detects placed machine"
	)
	_assert_true(
		"SPRINKLER",
		SprinklerSystem.has_machine(cell),
		"Shared automation backend detects placed sprinkler"
	)

	if not SprinklerSystem.has_machine(cell):
		return

	_assert_eq(
		"SPRINKLER",
		SprinklerSystem.get_machine_level(cell),
		SprinklerSystem.get_sprinkler_level(cell),
		"Generic and legacy level APIs stay equivalent"
	)
	_assert_eq(
		"SPRINKLER",
		SprinklerSystem.get_machine_interval_minutes(cell),
		SprinklerSystem.get_sprinkler_interval_minutes(cell),
		"Generic and legacy interval APIs stay equivalent"
	)

	_assert_eq(
		"SPRINKLER",
		SprinklerSystem.get_sprinkler_level(cell),
		1,
		"New sprinkler starts Level 1"
	)
	_assert_eq(
		"SPRINKLER",
		SprinklerSystem.get_sprinkler_interval_minutes(cell),
		180,
		"New sprinkler starts at 3-hour interval"
	)
	_assert_true(
		"SPRINKLER",
		SprinklerSystem.is_sprinkler_enabled(cell),
		"New sprinkler starts enabled"
	)

	var sprinkler_save_state: Array[Dictionary] = (
		SprinklerSystem.get_save_state()
	)
	var sprinkler_save_entry: Dictionary = {}

	for entry: Dictionary in sprinkler_save_state:
		if (
			int(entry.get("x", 0)) == cell.x
			and int(entry.get("y", 0)) == cell.y
		):
			sprinkler_save_entry = entry
			break

	_assert_true(
		"SPRINKLER",
		sprinkler_save_entry.has(
			"next_watering_total_minutes"
		),
		"Shared backend preserves legacy sprinkler schedule save key"
	)
	_assert_true(
		"SPRINKLER",
		not sprinkler_save_entry.has(
			"next_cycle_total_minutes"
		),
		"Sprinkler save format does not leak generic schedule key"
	)

	var interval_result: Dictionary = (
		SprinklerSystem.set_sprinkler_interval(
			cell,
			360
		)
	)

	_assert_true(
		"SPRINKLER",
		bool(interval_result.get("ok", false)),
		"Interval can be changed to 6 hours"
	)
	_assert_eq(
		"SPRINKLER",
		SprinklerSystem.get_sprinkler_interval_minutes(cell),
		360,
		"6-hour interval persists in runtime state"
	)
	_assert_eq(
		"SPRINKLER",
		SprinklerSystem.get_machine_interval_minutes(cell),
		360,
		"Shared machine scheduler stores the same interval"
	)

	var off_result: Dictionary = (
		SprinklerSystem.set_sprinkler_enabled(
			cell,
			false
		)
	)

	_assert_true(
		"SPRINKLER",
		bool(off_result.get("ok", false)),
		"Sprinkler can be disabled"
	)
	_assert_true(
		"SPRINKLER",
		not SprinklerSystem.is_sprinkler_enabled(cell),
		"Disabled state is readable"
	)

	SprinklerSystem.set_sprinkler_enabled(cell, true)
	SprinklerSystem.set_sprinkler_interval(cell, 180)

	EconomySystem.set_money(1000, "REGRESSION")

	var upgrade_2: Dictionary = (
		SprinklerSystem.upgrade_sprinkler(cell)
	)

	_assert_true(
		"SPRINKLER",
		bool(upgrade_2.get("ok", false)),
		"Level 1 -> 2 upgrade succeeds"
	)
	_assert_eq(
		"SPRINKLER",
		SprinklerSystem.get_sprinkler_level(cell),
		2,
		"Sprinkler reaches Level 2"
	)
	_assert_eq(
		"SPRINKLER",
		EconomySystem.get_money(),
		850,
		"Level 2 upgrade spends $150"
	)

	var upgrade_3: Dictionary = (
		SprinklerSystem.upgrade_sprinkler(cell)
	)

	_assert_true(
		"SPRINKLER",
		bool(upgrade_3.get("ok", false)),
		"Level 2 -> 3 upgrade succeeds"
	)
	_assert_eq(
		"SPRINKLER",
		SprinklerSystem.get_sprinkler_level(cell),
		3,
		"Sprinkler reaches Level 3"
	)
	_assert_eq(
		"SPRINKLER",
		EconomySystem.get_money(),
		500,
		"Level 3 upgrade spends $350"
	)

	# Event integration is tested on the actual machine we just placed.
	var event_state: Dictionary = {
		"event_last_day": {},
		"completed_unique": [],
		"last_any_event_day": -999999,
		"plant_xp_flat_bonus": 0,
		"harvest_income_multiplier": 1.0,
		"active_timed_effects": [
			{
				"effect_id": "sprinkler_breakdown",
				"source_event": "regression",
				"start_day": Clock.day,
				"end_day": Clock.day + 2
			}
		]
	}

	RandomEventSystem.load_save_state(event_state)

	_assert_true(
		"SPRINKLER",
		RandomEventSystem.are_sprinklers_disabled(),
		"Breakdown disables irrigation globally"
	)
	_assert_eq(
		"SPRINKLER",
		SprinklerSystem.get_minutes_until_next_watering(cell),
		-1,
		"Disabled-by-event sprinkler reports no next watering"
	)

	event_state["active_timed_effects"] = [
		{
			"effect_id": "water_shortage",
			"source_event": "regression",
			"start_day": Clock.day,
			"end_day": Clock.day + 2
		}
	]
	RandomEventSystem.load_save_state(event_state)

	_assert_approx(
		"SPRINKLER",
		RandomEventSystem.get_sprinkler_interval_multiplier(),
		2.0,
		0.0001,
		"Water Shortage doubles interval"
	)

	event_state["active_timed_effects"] = [
		{
			"effect_id": "efficient_irrigation",
			"source_event": "regression",
			"start_day": Clock.day,
			"end_day": Clock.day + 2
		}
	]
	RandomEventSystem.load_save_state(event_state)

	_assert_approx(
		"SPRINKLER",
		RandomEventSystem.get_sprinkler_strength_multiplier(),
		1.30,
		0.0001,
		"Efficient Irrigation gives +30% watering strength"
	)

	RandomEventSystem.reset_to_defaults()


# Finds the valid sprinkler edge.
func _find_valid_sprinkler_edge(
	tilemap: TileMap
) -> Variant:
	var rect: Rect2i = tilemap.get_used_rect()

	for y: int in range(
		rect.position.y,
		rect.end.y
	):
		for x: int in range(
			rect.position.x,
			rect.end.x
		):
			var cell := Vector2i(x, y)

			if not BuildSystem.is_sprinkler_biome_edge_cell(cell):
				continue

			var status: Dictionary = (
				BuildSystem.get_place_status(
					cell,
					&"sprinkler"
				)
			)

			if bool(status.get("ok", false)):
				return cell

	return null



# Tests the fertilizer injector integration behavior in the regression suite.
func _test_fertilizer_injector_integration() -> void:
	_section("FERTILIZER INJECTOR / BUILD INTEGRATION")

	_assert_eq(
		"FERTILIZER",
		FertilizerInjectorSystem.get_interval_options(),
		[60, 180, 360, 720],
		"Allowed machine intervals"
	)
	_assert_eq(
		"FERTILIZER",
		FertilizerInjectorSystem.get_trigger_options(),
		[0.35, 0.45, 0.55, 0.65],
		"Allowed nutrient triggers"
	)

	var level_1: Dictionary = (
		FertilizerInjectorSystem.get_level_definition(1)
	)
	var level_2: Dictionary = (
		FertilizerInjectorSystem.get_level_definition(2)
	)
	var level_3: Dictionary = (
		FertilizerInjectorSystem.get_level_definition(3)
	)

	_assert_eq(
		"FERTILIZER",
		int(level_1.get("radius", 0)),
		2,
		"Level 1 radius"
	)
	_assert_approx(
		"FERTILIZER",
		float(level_1.get("effect_amount", 0.0)),
		0.10,
		0.0001,
		"Level 1 nutrient dosage"
	)
	_assert_eq(
		"FERTILIZER",
		int(level_2.get("radius", 0)),
		3,
		"Level 2 radius"
	)
	_assert_eq(
		"FERTILIZER",
		int(level_2.get("cost_to_reach", 0)),
		250,
		"Level 2 upgrade cost"
	)
	_assert_eq(
		"FERTILIZER",
		int(level_3.get("radius", 0)),
		4,
		"Level 3 radius"
	)
	_assert_eq(
		"FERTILIZER",
		int(level_3.get("cost_to_reach", 0)),
		600,
		"Level 3 upgrade cost"
	)

	var tilemap_variant: Variant = SaveSystem.get("_tilemap")

	if not (
		is_instance_valid(tilemap_variant)
		and tilemap_variant is TileMap
	):
		_warn(
			"FERTILIZER",
			"No configured TileMap; integration skipped."
		)
		return

	var tilemap := tilemap_variant as TileMap

	ProgressionSystem.player_level = maxi(
		ProgressionSystem.player_level,
		20
	)
	ProgressionSystem.build_cell_credits = 5000

	var selected: bool = BuildSystem.select_build(
		&"fertilizer_injector"
	)

	_assert_true(
		"FERTILIZER",
		selected,
		"Level 20 player can select Fertilizer Injector"
	)

	if not selected:
		return

	var placement_cell: Variant = _find_valid_sprinkler_edge(
		tilemap
	)

	if placement_cell == null:
		_warn(
			"FERTILIZER",
			"No free automation edge cell found; placement skipped."
		)
		return

	var cell: Vector2i = placement_cell
	var placed: bool = BuildSystem.place_selected_at(cell)

	_assert_true(
		"FERTILIZER",
		placed,
		"BuildSystem places Fertilizer Injector"
	)

	if not placed:
		return

	await get_tree().process_frame
	await get_tree().process_frame

	_assert_true(
		"FERTILIZER",
		FertilizerInjectorSystem.has_machine(cell),
		"Runtime backend detects placed machine"
	)

	if not FertilizerInjectorSystem.has_machine(cell):
		return

	_assert_eq(
		"FERTILIZER",
		FertilizerInjectorSystem.get_machine_level(cell),
		1,
		"New machine starts Level 1"
	)
	_assert_eq(
		"FERTILIZER",
		FertilizerInjectorSystem.get_machine_interval_minutes(cell),
		180,
		"New machine starts at 3-hour interval"
	)
	_assert_approx(
		"FERTILIZER",
		FertilizerInjectorSystem.get_trigger_threshold(cell),
		0.55,
		0.0001,
		"New machine starts at 55% trigger"
	)
	_assert_true(
		"FERTILIZER",
		FertilizerInjectorSystem.is_machine_enabled(cell),
		"New machine starts enabled"
	)

	var trigger_result: Dictionary = (
		FertilizerInjectorSystem.set_trigger_threshold(
			cell,
			0.65
		)
	)

	_assert_true(
		"FERTILIZER",
		bool(trigger_result.get("ok", false)),
		"Trigger can be changed to 65%"
	)
	_assert_approx(
		"FERTILIZER",
		FertilizerInjectorSystem.get_trigger_threshold(cell),
		0.65,
		0.0001,
		"65% trigger persists"
	)

	var interval_result: Dictionary = (
		FertilizerInjectorSystem.set_machine_interval(
			cell,
			360
		)
	)

	_assert_true(
		"FERTILIZER",
		bool(interval_result.get("ok", false)),
		"Interval can be changed to 6 hours"
	)

	var off_result: Dictionary = (
		FertilizerInjectorSystem.set_machine_enabled(
			cell,
			false
		)
	)

	_assert_true(
		"FERTILIZER",
		bool(off_result.get("ok", false)),
		"Machine can be disabled"
	)

	FertilizerInjectorSystem.set_machine_enabled(
		cell,
		true
	)
	FertilizerInjectorSystem.set_machine_interval(
		cell,
		180
	)

	EconomySystem.set_money(2000, "REGRESSION")

	var upgrade_2: Dictionary = (
		FertilizerInjectorSystem.upgrade_machine(cell)
	)

	_assert_true(
		"FERTILIZER",
		bool(upgrade_2.get("ok", false)),
		"Level 1 -> 2 upgrade succeeds"
	)
	_assert_eq(
		"FERTILIZER",
		FertilizerInjectorSystem.get_machine_level(cell),
		2,
		"Machine reaches Level 2"
	)
	_assert_eq(
		"FERTILIZER",
		EconomySystem.get_money(),
		1750,
		"Level 2 upgrade spends $250"
	)

	var upgrade_3: Dictionary = (
		FertilizerInjectorSystem.upgrade_machine(cell)
	)

	_assert_true(
		"FERTILIZER",
		bool(upgrade_3.get("ok", false)),
		"Level 2 -> 3 upgrade succeeds"
	)
	_assert_eq(
		"FERTILIZER",
		FertilizerInjectorSystem.get_machine_level(cell),
		3,
		"Machine reaches Level 3"
	)
	_assert_eq(
		"FERTILIZER",
		EconomySystem.get_money(),
		1150,
		"Level 3 upgrade spends $600"
	)

	var saved: Array[Dictionary] = (
		FertilizerInjectorSystem.get_save_state()
	)
	var found_saved: bool = false

	for entry: Dictionary in saved:
		if (
			int(entry.get("x", 999999)) == cell.x
			and int(entry.get("y", 999999)) == cell.y
		):
			found_saved = true

			_assert_eq(
				"FERTILIZER",
				int(entry.get("level", 0)),
				3,
				"Save state stores machine level"
			)
			_assert_approx(
				"FERTILIZER",
				float(entry.get("trigger_nutrients", 0.0)),
				0.65,
				0.0001,
				"Save state stores nutrient trigger"
			)
			break

	_assert_true(
		"FERTILIZER",
		found_saved,
		"Machine appears in save state"
	)



# Tests the soil neutralizer integration behavior in the regression suite.
func _test_soil_neutralizer_integration() -> void:
	_section("SOIL NEUTRALIZER / BUILD INTEGRATION")

	_assert_eq(
		"NEUTRALIZER",
		SoilNeutralizerSystem.get_interval_options(),
		[60, 180, 360, 720],
		"Allowed machine intervals"
	)
	_assert_eq(
		"NEUTRALIZER",
		SoilNeutralizerSystem.get_mode_options(),
		[
			&"auto",
			&"lime",
			&"acid"
		],
		"Allowed pH-control modes"
	)

	var level_1: Dictionary = SoilNeutralizerSystem.get_level_definition(
		1
	)
	var level_2: Dictionary = SoilNeutralizerSystem.get_level_definition(
		2
	)
	var level_3: Dictionary = SoilNeutralizerSystem.get_level_definition(
		3
	)

	_assert_eq(
		"NEUTRALIZER",
		int(level_1.get("radius", 0)),
		2,
		"Level 1 radius"
	)
	_assert_approx(
		"NEUTRALIZER",
		float(level_1.get("effect_amount", 0.0)),
		0.60,
		0.0001,
		"Level 1 pH dosage"
	)
	_assert_eq(
		"NEUTRALIZER",
		int(level_2.get("radius", 0)),
		3,
		"Level 2 radius"
	)
	_assert_eq(
		"NEUTRALIZER",
		int(level_2.get("cost_to_reach", 0)),
		350,
		"Level 2 upgrade cost"
	)
	_assert_approx(
		"NEUTRALIZER",
		float(level_2.get("effect_amount", 0.0)),
		0.80,
		0.0001,
		"Level 2 pH dosage"
	)
	_assert_eq(
		"NEUTRALIZER",
		int(level_3.get("radius", 0)),
		4,
		"Level 3 radius"
	)
	_assert_eq(
		"NEUTRALIZER",
		int(level_3.get("cost_to_reach", 0)),
		800,
		"Level 3 upgrade cost"
	)
	_assert_approx(
		"NEUTRALIZER",
		float(level_3.get("effect_amount", 0.0)),
		1.00,
		0.0001,
		"Level 3 pH dosage"
	)

	var tilemap_variant: Variant = SaveSystem.get(
		"_tilemap"
	)

	if not (
		is_instance_valid(tilemap_variant)
		and tilemap_variant is TileMap
	):
		_warn(
			"NEUTRALIZER",
			"No configured TileMap; integration skipped."
		)
		return

	var tilemap := tilemap_variant as TileMap

	ProgressionSystem.player_level = maxi(
		ProgressionSystem.player_level,
		30
	)
	ProgressionSystem.build_cell_credits = 5000

	var selected: bool = BuildSystem.select_build(
		&"soil_neutralizer"
	)

	_assert_true(
		"NEUTRALIZER",
		selected,
		"Level 30 player can select Soil Neutralizer"
	)

	if not selected:
		return

	var placement_cell: Variant = _find_valid_sprinkler_edge(
		tilemap
	)

	if placement_cell == null:
		_warn(
			"NEUTRALIZER",
			"No free automation edge cell found; placement skipped."
		)
		return

	var cell: Vector2i = placement_cell
	var placed: bool = BuildSystem.place_selected_at(
		cell
	)

	_assert_true(
		"NEUTRALIZER",
		placed,
		"BuildSystem places Soil Neutralizer"
	)

	if not placed:
		return

	await get_tree().process_frame
	await get_tree().process_frame

	_assert_true(
		"NEUTRALIZER",
		SoilNeutralizerSystem.has_machine(cell),
		"Runtime backend detects placed machine"
	)

	if not SoilNeutralizerSystem.has_machine(cell):
		return

	_assert_eq(
		"NEUTRALIZER",
		SoilNeutralizerSystem.get_machine_level(cell),
		1,
		"New machine starts Level 1"
	)
	_assert_eq(
		"NEUTRALIZER",
		SoilNeutralizerSystem.get_machine_interval_minutes(cell),
		180,
		"New machine starts at 3-hour interval"
	)
	_assert_eq(
		"NEUTRALIZER",
		SoilNeutralizerSystem.get_machine_mode(cell),
		&"auto",
		"New machine starts in AUTO mode"
	)
	_assert_true(
		"NEUTRALIZER",
		SoilNeutralizerSystem.is_machine_enabled(cell),
		"New machine starts enabled"
	)

	var mode_result: Dictionary = SoilNeutralizerSystem.set_machine_mode(
		cell,
		&"lime"
	)

	_assert_true(
		"NEUTRALIZER",
		bool(mode_result.get("ok", false)),
		"Mode can be changed to LIME"
	)
	_assert_eq(
		"NEUTRALIZER",
		SoilNeutralizerSystem.get_machine_mode(cell),
		&"lime",
		"LIME mode persists"
	)

	var interval_result: Dictionary = SoilNeutralizerSystem.set_machine_interval(
		cell,
		360
	)

	_assert_true(
		"NEUTRALIZER",
		bool(interval_result.get("ok", false)),
		"Interval can be changed to 6 hours"
	)

	# Real pH-effect test on the biome edge zone used for placement.
	var ph_before_stress: float = BiomeSystem.get_ph(
		cell
	)

	if ph_before_stress >= 0.0:
		BiomeSystem.add_ph(
			cell,
			-20.0
		)
		var stressed_ph: float = BiomeSystem.get_ph(
			cell
		)

		SoilNeutralizerSystem.call(
			"_run_single_cycle",
			cell
		)

		var corrected_ph: float = BiomeSystem.get_ph(
			cell
		)

		_assert_true(
			"NEUTRALIZER",
			corrected_ph > stressed_ph,
			"LIME cycle raises stressed zone pH"
		)

	EconomySystem.set_money(
		3000,
		"REGRESSION"
	)

	var upgrade_2: Dictionary = SoilNeutralizerSystem.upgrade_machine(
		cell
	)

	_assert_true(
		"NEUTRALIZER",
		bool(upgrade_2.get("ok", false)),
		"Level 1 -> 2 upgrade succeeds"
	)
	_assert_eq(
		"NEUTRALIZER",
		SoilNeutralizerSystem.get_machine_level(cell),
		2,
		"Machine reaches Level 2"
	)
	_assert_eq(
		"NEUTRALIZER",
		EconomySystem.get_money(),
		2650,
		"Level 2 upgrade spends $350"
	)

	var upgrade_3: Dictionary = SoilNeutralizerSystem.upgrade_machine(
		cell
	)

	_assert_true(
		"NEUTRALIZER",
		bool(upgrade_3.get("ok", false)),
		"Level 2 -> 3 upgrade succeeds"
	)
	_assert_eq(
		"NEUTRALIZER",
		SoilNeutralizerSystem.get_machine_level(cell),
		3,
		"Machine reaches Level 3"
	)
	_assert_eq(
		"NEUTRALIZER",
		EconomySystem.get_money(),
		1850,
		"Level 3 upgrade spends $800"
	)

	SoilNeutralizerSystem.set_machine_mode(
		cell,
		&"acid"
	)

	var saved: Array[Dictionary] = SoilNeutralizerSystem.get_save_state()
	var found_saved: bool = false

	for entry: Dictionary in saved:
		if (
			int(entry.get("x", 999999)) == cell.x
			and int(entry.get("y", 999999)) == cell.y
		):
			found_saved = true

			_assert_eq(
				"NEUTRALIZER",
				int(entry.get("level", 0)),
				3,
				"Save state stores machine level"
			)
			_assert_eq(
				"NEUTRALIZER",
				StringName(
					entry.get(
						"mode",
						&""
					)
				),
				&"acid",
				"Save state stores pH-control mode"
			)
			break

	_assert_true(
		"NEUTRALIZER",
		found_saved,
		"Machine appears in save state"
	)

	# Avoid altering later soak balance after this integration check.
	SoilNeutralizerSystem.set_machine_enabled(
		cell,
		false
	)



# Tests the plant protection integration behavior in the regression suite.
func _test_plant_protection_integration() -> void:
	_section("PLANT PROTECTION / BUILD INTEGRATION")

	_assert_eq(
		"PROTECTION",
		PlantProtectionStationSystem.get_interval_options(),
		[60, 180, 360, 720],
		"Allowed machine intervals"
	)
	_assert_eq(
		"PROTECTION",
		PlantProtectionStationSystem.get_mode_options(),
		[
			&"auto",
			&"pest",
			&"fungus",
			&"both"
		],
		"Allowed biological-control modes"
	)
	_assert_eq(
		"PROTECTION",
		PlantProtectionStationSystem.get_trigger_options(),
		[0.10, 0.15, 0.20, 0.30],
		"Allowed biological trigger thresholds"
	)

	var level_1: Dictionary = PlantProtectionStationSystem.get_level_definition(1)
	var level_2: Dictionary = PlantProtectionStationSystem.get_level_definition(2)
	var level_3: Dictionary = PlantProtectionStationSystem.get_level_definition(3)

	_assert_eq(
		"PROTECTION",
		int(level_1.get("radius", 0)),
		2,
		"Level 1 radius"
	)
	_assert_approx(
		"PROTECTION",
		PlantProtectionStationSystem.get_pesticide_amount_for_level(1),
		0.20,
		0.0001,
		"Level 1 pesticide treatment"
	)
	_assert_approx(
		"PROTECTION",
		PlantProtectionStationSystem.get_fungicide_amount_for_level(1),
		0.18,
		0.0001,
		"Level 1 fungicide treatment"
	)
	_assert_eq(
		"PROTECTION",
		int(level_2.get("radius", 0)),
		3,
		"Level 2 radius"
	)
	_assert_eq(
		"PROTECTION",
		int(level_2.get("cost_to_reach", 0)),
		500,
		"Level 2 upgrade cost"
	)
	_assert_eq(
		"PROTECTION",
		int(level_3.get("radius", 0)),
		4,
		"Level 3 radius"
	)
	_assert_eq(
		"PROTECTION",
		int(level_3.get("cost_to_reach", 0)),
		1100,
		"Level 3 upgrade cost"
	)

	var tilemap_variant: Variant = SaveSystem.get("_tilemap")

	if not (
		is_instance_valid(tilemap_variant)
		and tilemap_variant is TileMap
	):
		_warn(
			"PROTECTION",
			"No configured TileMap; integration skipped."
		)
		return

	var tilemap := tilemap_variant as TileMap

	ProgressionSystem.player_level = maxi(
		ProgressionSystem.player_level,
		40
	)
	ProgressionSystem.build_cell_credits = 5000

	var selected: bool = BuildSystem.select_build(
		&"plant_protection_station"
	)

	_assert_true(
		"PROTECTION",
		selected,
		"Level 40 player can select Plant Protection Station"
	)

	if not selected:
		return

	var placement_cell: Variant = _find_valid_sprinkler_edge(
		tilemap
	)

	if placement_cell == null:
		_warn(
			"PROTECTION",
			"No free automation edge cell found; placement skipped."
		)
		return

	var cell: Vector2i = placement_cell
	var placed: bool = BuildSystem.place_selected_at(cell)

	_assert_true(
		"PROTECTION",
		placed,
		"BuildSystem places Plant Protection Station"
	)

	if not placed:
		return

	await get_tree().process_frame
	await get_tree().process_frame

	_assert_true(
		"PROTECTION",
		PlantProtectionStationSystem.has_machine(cell),
		"Runtime backend detects placed machine"
	)

	if not PlantProtectionStationSystem.has_machine(cell):
		return

	_assert_eq(
		"PROTECTION",
		PlantProtectionStationSystem.get_machine_level(cell),
		1,
		"New machine starts Level 1"
	)
	_assert_eq(
		"PROTECTION",
		PlantProtectionStationSystem.get_machine_interval_minutes(cell),
		180,
		"New machine starts at 3-hour interval"
	)
	_assert_eq(
		"PROTECTION",
		PlantProtectionStationSystem.get_machine_mode(cell),
		&"auto",
		"New machine starts in AUTO mode"
	)
	_assert_approx(
		"PROTECTION",
		PlantProtectionStationSystem.get_pest_trigger(cell),
		0.15,
		0.0001,
		"Default pest trigger is 15%"
	)
	_assert_approx(
		"PROTECTION",
		PlantProtectionStationSystem.get_fungus_trigger(cell),
		0.15,
		0.0001,
		"Default fungus trigger is 15%"
	)

	var pest_trigger_result: Dictionary = PlantProtectionStationSystem.set_pest_trigger(
		cell,
		0.20
	)
	var fungus_trigger_result: Dictionary = PlantProtectionStationSystem.set_fungus_trigger(
		cell,
		0.30
	)

	_assert_true(
		"PROTECTION",
		bool(pest_trigger_result.get("ok", false)),
		"Pest trigger can be changed"
	)
	_assert_true(
		"PROTECTION",
		bool(fungus_trigger_result.get("ok", false)),
		"Fungus trigger can be changed"
	)

	var mode_result: Dictionary = PlantProtectionStationSystem.set_machine_mode(
		cell,
		&"both"
	)

	_assert_true(
		"PROTECTION",
		bool(mode_result.get("ok", false)),
		"Mode can be changed to BOTH"
	)

	var interval_result: Dictionary = PlantProtectionStationSystem.set_machine_interval(
		cell,
		360
	)

	_assert_true(
		"PROTECTION",
		bool(interval_result.get("ok", false)),
		"Interval can be changed to 6 hours"
	)

	# Deterministic real-plant treatment test.
	#
	# Automation machines can legally sit on a Sandy visual edge cell that
	# itself has no BiomeSystem zone. The machine operates on nearby connected
	# zones, so the synthetic plant must be placed on an ACTUAL covered
	# biome-zone cell rather than blindly on the machine cell.
	var covered_zones: Dictionary = (
		PlantProtectionStationSystem.collect_covered_zones(
			cell,
			PlantProtectionStationSystem.get_machine_radius(
				cell
			)
		)
	)

	_assert_true(
		"PROTECTION",
		not covered_zones.is_empty(),
		"Placed station reaches at least one biome zone"
	)

	var test_plant_cell: Variant = null

	for zone_variant: Variant in covered_zones.keys():
		var representative_variant: Variant = covered_zones[
			zone_variant
		]

		if not representative_variant is Vector2i:
			continue

		var representative: Vector2i = representative_variant

		if BiomeSystem.get_zone_id(representative) < 0:
			continue

		test_plant_cell = representative
		break

	if test_plant_cell == null:
		_fail(
			"PROTECTION",
			"No valid covered biome cell for treatment test"
		)
	else:
		var packed_variant: Variant = load(
			"res://Scenes/plant.tscn"
		)
		var test_plant: Node2D = null

		if packed_variant is PackedScene:
			var plant_variant: Variant = (
				packed_variant as PackedScene
			).instantiate()

			if plant_variant is Node2D:
				test_plant = plant_variant as Node2D

		if test_plant == null:
			_fail(
				"PROTECTION",
				"Could not instantiate plant.tscn for treatment test"
			)
		else:
			var plant_cell: Vector2i = test_plant_cell
			var lily: PlantData = (
				PlantSelectionSystem.get_plant_by_id(
					&"lily_seed"
				)
			)

			test_plant.set("data", lily)
			test_plant.set(
				"anchor_cell",
				plant_cell
			)
			test_plant.set(
				"occupied_cells",
				[plant_cell]
			)
			test_plant.position = tilemap.map_to_local(
				plant_cell
			)
			_gameplay_instance.add_child(test_plant)

			PlantRegistry.register(
				plant_cell,
				test_plant
			)

			test_plant.set(
				"pest_level",
				0.60
			)
			test_plant.set(
				"disease_level",
				0.60
			)

			var pest_before: float = float(
				test_plant.get("pest_level")
			)
			var fungus_before: float = float(
				test_plant.get("disease_level")
			)

			PlantProtectionStationSystem.call(
				"_run_single_cycle",
				cell
			)

			var pest_after: float = float(
				test_plant.get("pest_level")
			)
			var fungus_after: float = float(
				test_plant.get("disease_level")
			)

			_assert_true(
				"PROTECTION",
				pest_after < pest_before,
				"BOTH cycle reduces plant pest level"
			)
			_assert_true(
				"PROTECTION",
				fungus_after < fungus_before,
				"BOTH cycle reduces plant fungus level"
			)

			PlantRegistry.unregister(
				plant_cell
			)
			test_plant.queue_free()
			await get_tree().process_frame

	EconomySystem.set_money(
		4000,
		"REGRESSION"
	)

	var upgrade_2: Dictionary = PlantProtectionStationSystem.upgrade_machine(
		cell
	)

	_assert_true(
		"PROTECTION",
		bool(upgrade_2.get("ok", false)),
		"Level 1 -> 2 upgrade succeeds"
	)
	_assert_eq(
		"PROTECTION",
		PlantProtectionStationSystem.get_machine_level(cell),
		2,
		"Machine reaches Level 2"
	)
	_assert_eq(
		"PROTECTION",
		EconomySystem.get_money(),
		3500,
		"Level 2 upgrade spends $500"
	)

	var upgrade_3: Dictionary = PlantProtectionStationSystem.upgrade_machine(
		cell
	)

	_assert_true(
		"PROTECTION",
		bool(upgrade_3.get("ok", false)),
		"Level 2 -> 3 upgrade succeeds"
	)
	_assert_eq(
		"PROTECTION",
		PlantProtectionStationSystem.get_machine_level(cell),
		3,
		"Machine reaches Level 3"
	)
	_assert_eq(
		"PROTECTION",
		EconomySystem.get_money(),
		2400,
		"Level 3 upgrade spends $1100"
	)

	PlantProtectionStationSystem.set_machine_mode(
		cell,
		&"fungus"
	)

	var saved: Array[Dictionary] = PlantProtectionStationSystem.get_save_state()
	var found_saved: bool = false

	for entry: Dictionary in saved:
		if (
			int(entry.get("x", 999999)) == cell.x
			and int(entry.get("y", 999999)) == cell.y
		):
			found_saved = true

			_assert_eq(
				"PROTECTION",
				int(entry.get("level", 0)),
				3,
				"Save state stores machine level"
			)
			_assert_eq(
				"PROTECTION",
				StringName(entry.get("mode", &"")),
				&"fungus",
				"Save state stores control mode"
			)
			_assert_approx(
				"PROTECTION",
				float(entry.get("pest_trigger", 0.0)),
				0.20,
				0.0001,
				"Save state stores pest trigger"
			)
			_assert_approx(
				"PROTECTION",
				float(entry.get("fungus_trigger", 0.0)),
				0.30,
				0.0001,
				"Save state stores fungus trigger"
			)
			break

	_assert_true(
		"PROTECTION",
		found_saved,
		"Machine appears in save state"
	)

	# Keep later soak/invariant tests isolated from this machine.
	PlantProtectionStationSystem.set_machine_enabled(
		cell,
		false
	)


# Tests the random event modifiers behavior in the regression suite.
func _test_random_event_modifiers() -> void:
	_section("RANDOM EVENT STATE / MODIFIERS")

	RandomEventSystem.reset_to_defaults()

	var synthetic_state: Dictionary = {
		"event_last_day": {},
		"completed_unique": [
			"research_breakthrough"
		],
		"last_any_event_day": Clock.day - 3,
		"plant_xp_flat_bonus": 2,
		"harvest_income_multiplier": 1.15,
		"active_timed_effects": [
			{
				"effect_id": "perfect_weather",
				"source_event": "regression",
				"start_day": Clock.day,
				"end_day": Clock.day + 3
			},
			{
				"effect_id": "drought",
				"source_event": "regression",
				"start_day": Clock.day,
				"end_day": Clock.day + 3
			},
			{
				"effect_id": "nutrient_rich_delivery",
				"source_event": "regression",
				"start_day": Clock.day,
				"end_day": Clock.day + 3
			},
			{
				"effect_id": "soil_analysis_breakthrough",
				"source_event": "regression",
				"start_day": Clock.day,
				"end_day": Clock.day + 3
			},
			{
				"effect_id": "biocontrol_breakthrough",
				"source_event": "regression",
				"start_day": Clock.day,
				"end_day": Clock.day + 3
			}
		]
	}

	_assert_true(
		"EVENT",
		RandomEventSystem.load_save_state(
			synthetic_state
		),
		"Synthetic event state loads"
	)
	_assert_eq(
		"EVENT",
		RandomEventSystem.get_plant_xp_flat_bonus(),
		2,
		"Permanent Plant XP bonus restores"
	)
	_assert_approx(
		"EVENT",
		RandomEventSystem.get_harvest_income_multiplier(),
		1.15,
		0.0001,
		"Permanent harvest multiplier restores"
	)
	_assert_approx(
		"EVENT",
		RandomEventSystem.get_plant_growth_multiplier(),
		1.25,
		0.0001,
		"Perfect Weather growth multiplier"
	)
	_assert_approx(
		"EVENT",
		RandomEventSystem.get_soil_drying_multiplier(),
		1.50,
		0.0001,
		"Drought drying multiplier"
	)

	_assert_approx(
		"EVENT",
		RandomEventSystem.get_fertilizer_injector_strength_multiplier(),
		1.30,
		0.0001,
		"Nutrient-Rich Delivery gives +30% Fertilizer strength"
	)
	_assert_approx(
		"EVENT",
		FertilizerInjectorSystem.get_effect_amount_for_level(1),
		0.13,
		0.0001,
		"Fertilizer L1 dosage reflects positive event"
	)
	_assert_approx(
		"EVENT",
		RandomEventSystem.get_soil_neutralizer_strength_multiplier(),
		1.30,
		0.0001,
		"Soil Analysis gives +30% Neutralizer strength"
	)
	_assert_approx(
		"EVENT",
		SoilNeutralizerSystem.get_effect_amount_for_level(1),
		0.78,
		0.0001,
		"Neutralizer L1 dosage reflects positive event"
	)
	_assert_approx(
		"EVENT",
		RandomEventSystem.get_plant_protection_strength_multiplier(),
		1.30,
		0.0001,
		"Biocontrol Breakthrough gives +30% Protection strength"
	)
	_assert_approx(
		"EVENT",
		PlantProtectionStationSystem.get_pesticide_amount_for_level(1),
		0.26,
		0.0001,
		"Protection L1 pesticide reflects positive event"
	)
	_assert_approx(
		"EVENT",
		PlantProtectionStationSystem.get_fungicide_amount_for_level(1),
		0.234,
		0.0001,
		"Protection L1 fungicide reflects positive event"
	)

	# Synthetic negative automation effects.
	synthetic_state["active_timed_effects"] = [
		{
			"effect_id": "fertilizer_shortage",
			"source_event": "regression",
			"start_day": Clock.day,
			"end_day": Clock.day + 3
		},
		{
			"effect_id": "reagent_contamination",
			"source_event": "regression",
			"start_day": Clock.day,
			"end_day": Clock.day + 3
		},
		{
			"effect_id": "treatment_resistance",
			"source_event": "regression",
			"start_day": Clock.day,
			"end_day": Clock.day + 3
		}
	]

	_assert_true(
		"EVENT",
		RandomEventSystem.load_save_state(
			synthetic_state
		),
		"Negative automation event state loads"
	)
	_assert_approx(
		"EVENT",
		RandomEventSystem.get_fertilizer_injector_strength_multiplier(),
		0.65,
		0.0001,
		"Fertilizer Shortage reduces strength by 35%"
	)
	_assert_approx(
		"EVENT",
		FertilizerInjectorSystem.get_effect_amount_for_level(1),
		0.065,
		0.0001,
		"Fertilizer L1 dosage reflects negative event"
	)
	_assert_approx(
		"EVENT",
		RandomEventSystem.get_soil_neutralizer_strength_multiplier(),
		0.65,
		0.0001,
		"Reagent Contamination reduces Neutralizer strength by 35%"
	)
	_assert_approx(
		"EVENT",
		SoilNeutralizerSystem.get_effect_amount_for_level(1),
		0.39,
		0.0001,
		"Neutralizer L1 dosage reflects negative event"
	)
	_assert_approx(
		"EVENT",
		RandomEventSystem.get_plant_protection_strength_multiplier(),
		0.65,
		0.0001,
		"Treatment Resistance reduces Protection strength by 35%"
	)
	_assert_approx(
		"EVENT",
		PlantProtectionStationSystem.get_pesticide_amount_for_level(1),
		0.13,
		0.0001,
		"Protection L1 pesticide reflects negative event"
	)
	_assert_approx(
		"EVENT",
		PlantProtectionStationSystem.get_fungicide_amount_for_level(1),
		0.117,
		0.0001,
		"Protection L1 fungicide reflects negative event"
	)

	var saved_again: Dictionary = (
		RandomEventSystem.get_save_state()
	)

	_assert_eq(
		"EVENT",
		int(saved_again.get("plant_xp_flat_bonus", 0)),
		2,
		"Random Event state re-serializes Plant XP bonus"
	)
	_assert_approx(
		"EVENT",
		float(
			saved_again.get(
				"harvest_income_multiplier",
				0.0
			)
		),
		1.15,
		0.0001,
		"Random Event state re-serializes harvest multiplier"
	)

	RandomEventSystem.reset_to_defaults()


# Tests the memory save payload behavior in the regression suite.
func _test_memory_save_payload() -> void:
	_section("SAVE PAYLOAD / JSON SERIALIZATION")

	var payload: Dictionary = _capture_runtime_snapshot()
	var json_text: String = JSON.stringify(
		payload,
		"\t"
	)

	_assert_true(
		"SAVE",
		json_text.length() > 100,
		"Full in-memory payload serializes to JSON"
	)

	var parsed: Variant = JSON.parse_string(json_text)

	_assert_true(
		"SAVE",
		typeof(parsed) == TYPE_DICTIONARY,
		"Serialized payload parses back to Dictionary"
	)

	if typeof(parsed) != TYPE_DICTIONARY:
		return

	var parsed_dict: Dictionary = parsed

	for required_key: String in [
		"player",
		"economy",
		"progression",
		"tools",
		"inventory",
		"clock",
		"weather",
		"random_events",
		"build",
		"sprinklers",
		"fertilizer_injectors",
		"soil_neutralizers",
		"plant_protection_stations",
		"seed_storage",
		"biome",
		"plants"
	]:
		_assert_true(
			"SAVE",
			parsed_dict.has(required_key),
			"Payload contains '%s'" % required_key
		)


# Tests the temp JSON roundtrip behavior in the regression suite.
func _test_temp_json_roundtrip() -> void:
	_section("TEMP FILE ROUNDTRIP")

	var payload: Dictionary = _capture_runtime_snapshot()
	var json_text: String = JSON.stringify(
		payload,
		"\t"
	)

	var file := FileAccess.open(
		TEMP_JSON_PATH,
		FileAccess.WRITE
	)

	if file == null:
		_fail(
			"SAVE FILE",
			"Could not create %s" % TEMP_JSON_PATH
		)
		return

	file.store_string(json_text)
	file.flush()
	file = null

	var read_file := FileAccess.open(
		TEMP_JSON_PATH,
		FileAccess.READ
	)

	if read_file == null:
		_fail(
			"SAVE FILE",
			"Could not reopen %s" % TEMP_JSON_PATH
		)
		_remove_temp_json()
		return

	var read_text: String = read_file.get_as_text()
	read_file = null

	var parsed: Variant = JSON.parse_string(read_text)

	_assert_true(
		"SAVE FILE",
		typeof(parsed) == TYPE_DICTIONARY,
		"Temporary JSON file can be read and parsed"
	)
	_assert_true(
		"SAVE FILE",
		read_text == json_text,
		"Temporary file contents match written JSON (%d bytes)"
		% json_text.length()
	)

	_remove_temp_json()


# Removes the temp JSON.
func _remove_temp_json() -> void:
	var absolute_path: String = ProjectSettings.globalize_path(
		TEMP_JSON_PATH
	)

	if FileAccess.file_exists(TEMP_JSON_PATH):
		DirAccess.remove_absolute(absolute_path)


# Tests the 30 day soak behavior in the regression suite.
func _test_30_day_soak() -> void:
	_section("30-DAY SOAK SIMULATION")

	# Isolate the simulation from event randomness and expensive cosmetic
	# sprinkler bursts. Sprinkler machine logic is already covered above.
	RandomEventSystem.reset_to_defaults()
	RandomEventSystem.daily_event_chance = 0.0
	RandomEventSystem.first_event_day = 999999
	SaveSystem.autosave_enabled = false

	var sprinkler_snapshot: Array = (
		SprinklerSystem.get_save_state().duplicate(true)
	)

	_seed_soak_test_plant()

	for cell: Vector2i in SprinklerSystem.get_sprinkler_cells():
		SprinklerSystem.set_sprinkler_enabled(
			cell,
			false
		)

	var start_day: int = Clock.day
	var start_minute: int = Clock.minute_of_day
	var total_hours: int = 30 * 24

	for _hour_index: int in range(total_hours):
		Clock.call("_advance_minutes", 60)

	_assert_eq(
		"SOAK",
		Clock.day,
		start_day + 30,
		"Clock advances exactly 30 days"
	)
	_assert_eq(
		"SOAK",
		Clock.minute_of_day,
		start_minute,
		"30-day simulation preserves time-of-day"
	)

	_test_biome_invariants()
	_test_live_plant_invariants()

	# A machine disabled for the soak must still retain valid serialized state.
	var sprinkler_after: Array = SprinklerSystem.get_save_state()

	_assert_true(
		"SOAK",
		sprinkler_after.size() == sprinkler_snapshot.size(),
		"Sprinkler count remains stable during soak"
	)


# Seeds the soak test plant.
func _seed_soak_test_plant() -> void:
	var lily: PlantData = PlantSelectionSystem.get_plant_by_id(
		&"lily_seed"
	)

	if lily == null:
		_warn(
			"PLANTS",
			"Lily PlantData unavailable; soak plant coverage skipped."
		)
		return

	var tilemap_variant: Variant = SaveSystem.get("_tilemap")
	var cell_to_zone_variant: Variant = BiomeSystem.get("_cell_to_zone")

	if (
		not tilemap_variant is TileMap
		or typeof(cell_to_zone_variant) != TYPE_DICTIONARY
	):
		_warn(
			"PLANTS",
			"Could not locate TileMap/Biome cells; soak plant coverage skipped."
		)
		return

	var tilemap := tilemap_variant as TileMap
	var cell_to_zone: Dictionary = cell_to_zone_variant
	var chosen_cell: Variant = null

	for cell_variant: Variant in cell_to_zone.keys():
		if typeof(cell_variant) != TYPE_VECTOR2I:
			continue

		var cell: Vector2i = cell_variant
		var soil: String = BiomeSystem.get_soil_type_at_cell(
			cell
		).strip_edges().to_lower()

		if not lily.allowed_soils.has(soil):
			continue

		if PlantRegistry.get_plant(cell) != null:
			continue

		if BuildSystem.has_build_object_at(cell):
			continue

		chosen_cell = cell
		break

	if chosen_cell == null:
		_warn(
			"PLANTS",
			"No free Lily-compatible biome cell found; soak plant coverage skipped."
		)
		return

	var anchor: Vector2i = chosen_cell
	var world_position: Vector2 = tilemap.to_global(
		tilemap.map_to_local(anchor)
	)

	var synthetic_entry: Dictionary = {
		"seed_item_id": String(lily.seed_item_id),
		"anchor_x": anchor.x,
		"anchor_y": anchor.y,
		"occupied_cells": [
			{
				"x": anchor.x,
				"y": anchor.y
			}
		],
		"world_x": world_position.x,
		"world_y": world_position.y,
		"stage": 0,
		"health": lily.max_health,
		"growth_hours_accum": 0.0,
		"pest_level": 0.0,
		"disease_level": 0.0,
		"is_dead": false
	}

	SaveSystem.call(
		"_restore_plants_state",
		[synthetic_entry]
	)

	var restored_plant: Variant = PlantRegistry.get_plant(
		anchor
	)

	_assert_true(
		"PLANTS",
		restored_plant is Node,
		"Synthetic Lily created for 30-day soak"
	)


# Tests the live plant invariants behavior in the regression suite.
func _test_live_plant_invariants() -> void:
	_section("LIVE PLANT INVARIANTS")

	var registry_variant: Variant = PlantRegistry.get(
		"plants_by_cell"
	)

	if typeof(registry_variant) != TYPE_DICTIONARY:
		_fail(
			"PLANTS",
			"PlantRegistry.plants_by_cell is invalid"
		)
		return

	var registry: Dictionary = registry_variant
	var unique_plants: Dictionary = {}

	for plant_variant: Variant in registry.values():
		if plant_variant is Node:
			unique_plants[plant_variant] = true

	if unique_plants.is_empty():
		_warn(
			"PLANTS",
			"No registered plants remained for invariant checks."
		)
		return

	for plant_variant: Variant in unique_plants.keys():
		var plant := plant_variant as Node
		var data_variant: Variant = plant.get("data")

		if not data_variant is PlantData:
			_fail(
				"PLANTS",
				"Living plant has no valid PlantData"
			)
			continue

		var data := data_variant as PlantData
		var name_text: String = data.display_name

		_assert_range(
			"PLANTS",
			float(plant.get("health")),
			0.0,
			data.max_health,
			"%s health" % name_text
		)
		_assert_range(
			"PLANTS",
			float(plant.get("pest_level")),
			0.0,
			1.0,
			"%s pest level" % name_text
		)
		_assert_range(
			"PLANTS",
			float(plant.get("disease_level")),
			0.0,
			1.0,
			"%s disease level" % name_text
		)

		var stage_value: int = int(
			plant.get("stage")
		)

		_assert_true(
			"PLANTS",
			stage_value >= 0
			and stage_value <= data.max_stage,
			"%s stage within 0..%d"
			% [
				name_text,
				data.max_stage
			]
		)

		var dead: bool = bool(plant.get("is_dead"))

		if dead:
			_assert_approx(
				"PLANTS",
				float(plant.get("health")),
				0.0,
				0.0001,
				"%s dead state has zero health"
				% name_text
			)


# ------------------------------------------------------------------
# Balance snapshot
# ------------------------------------------------------------------

# Prints the current balance values for regression diagnostics.
func _print_balance_snapshot() -> void:
	print("")
	print("------------------------------------------------------------")
	print(" BALANCE SNAPSHOT — REVIEW AFTER REGRESSION")
	print("------------------------------------------------------------")
	print(
		"[BALANCE] Clock day_length_seconds=",
		Clock.day_length_seconds,
		" tick_step_minutes=",
		Clock.tick_step_minutes,
		" speed_modes=1x/3x/6x effective_days=",
		Clock.day_length_seconds,
		"/",
		Clock.day_length_seconds / 3.0,
		"/",
		Clock.day_length_seconds / 6.0,
		"s"
	)
	print(
		"[BALANCE] Starting money=",
		EconomySystem.DEFAULT_MONEY,
		" starting_lily_seeds=",
		InventorySystem.DEFAULT_ITEMS.get(
			InventorySystem.ITEM_LILY_SEED,
			0
		)
	)
	print(
		"[BALANCE] Player XP formula: 100 + level*20"
	)
	print(
		"[BALANCE] Milestone L10=",
		ProgressionSystem.get_player_milestone_reward(10)
	)
	print(
		"[BALANCE] Terrain upgrade costs=",
		ProgressionSystem.TERRAIN_UPGRADE_COSTS
	)
	print(
		"[BALANCE] Equipment upgrade costs=",
		ProgressionSystem.EQUIPMENT_UPGRADE_COSTS
	)
	print(
		"[BALANCE] Tool wear=",
		Toolsystem.DURABILITY_COSTS,
		" repair=",
		Toolsystem.REPAIR_COST_BY_LEVEL,
		" replacement=",
		Toolsystem.REPLACEMENT_COST_BY_LEVEL
	)
	print(
		"[BALANCE] Biome moisture defaults loamy=",
		BiomeSystem.default_moisture_loamy,
		" sandy=",
		BiomeSystem.default_moisture_sandy,
		" base_loss/h=",
		BiomeSystem.base_moisture_loss_per_hour
	)
	print(
		"[BALANCE] Weather weights clear/cloud/rain/heat/cold=",
		WeatherSystem.weight_clear,
		"/",
		WeatherSystem.weight_cloudy,
		"/",
		WeatherSystem.weight_rain,
		"/",
		WeatherSystem.weight_heatwave,
		"/",
		WeatherSystem.weight_coldsnap,
		" rain_gain/h=",
		WeatherSystem.rain_moisture_gain_per_hour
	)
	print(
		"[BALANCE] Weather duration hours cloudy=",
		WeatherSystem.cloudy_duration_min_hours,
		"..",
		WeatherSystem.cloudy_duration_max_hours,
		" rain=",
		WeatherSystem.rain_duration_min_hours,
		"..",
		WeatherSystem.rain_duration_max_hours,
		" heat=",
		WeatherSystem.heatwave_duration_min_hours,
		"..",
		WeatherSystem.heatwave_duration_max_hours,
		" cold=",
		WeatherSystem.coldsnap_duration_min_hours,
		"..",
		WeatherSystem.coldsnap_duration_max_hours
	)
	print(
		"[BALANCE] Sprinkler L1=",
		SprinklerSystem.get_level_definition(1),
		" L2=",
		SprinklerSystem.get_level_definition(2),
		" L3=",
		SprinklerSystem.get_level_definition(3),
		" intervals=",
		SprinklerSystem.get_watering_interval_options()
	)
	print(
		"[BALANCE] Events chance/day=",
		RandomEventSystem.daily_event_chance,
		" first_day=",
		RandomEventSystem.first_event_day,
		" min_gap=",
		RandomEventSystem.minimum_days_between_events,
		" same_event_cd=",
		RandomEventSystem.same_event_cooldown_days
	)
	print(
		"[BALANCE] Automation events duration=",
		RandomEventSystem.automation_event_duration_days,
		"d positive_x=",
		RandomEventSystem.automation_positive_strength_multiplier,
		" negative_x=",
		RandomEventSystem.automation_negative_strength_multiplier
	)

	print(
		"[BALANCE] Event money grant=",
		RandomEventSystem.botanical_grant_money,
		" seed donation=",
		RandomEventSystem.seed_donation_total,
		" market boom x",
		RandomEventSystem.market_boom_multiplier,
		" slump x",
		RandomEventSystem.market_slump_multiplier
	)

	for plant_data: PlantData in PlantSelectionSystem.get_all_plants():
		if plant_data == null:
			continue

		print(
			"[BALANCE] Plant ",
			plant_data.display_name,
			" seed=",
			String(plant_data.seed_item_id),
			" buy/sell=",
			plant_data.seed_buy_price,
			"/",
			plant_data.seed_sell_price,
			" yield=",
			plant_data.harvest_yield_min,
			"..",
			plant_data.harvest_yield_max,
			" mastery_xp=",
			plant_data.plant_mastery_xp_per_harvest,
			" stages_days=",
			plant_data.days_to_next_stage,
			" decay/h=",
			plant_data.health_decay_per_hour,
			" recover/h=",
			plant_data.health_recover_per_hour
		)

	var sprinkler_cost: int = -1

	for item: Dictionary in BuildSystem.get_build_catalog():
		if String(item.get("id", "")) == "sprinkler":
			sprinkler_cost = int(
				item.get("cost", -1)
			)
			break

	print(
		"[BALANCE] Build sprinkler credit cost=",
		sprinkler_cost
	)
	print("------------------------------------------------------------")


# ------------------------------------------------------------------
# Helpers / report
# ------------------------------------------------------------------

# Finishes the suite.
func _finish_suite() -> void:
	print("")
	print("============================================================")
	print(" BLUEBERRY REGRESSION RESULT")
	print("============================================================")
	print(" Passed:   ", _passed)
	print(" Failed:   ", _failed)
	print(" Warnings: ", _warnings)

	if _failed == 0:
		print(" RESULT: PASS")
	else:
		print(" RESULT: FAIL")

	print("============================================================")
	print("")

	_running = false

	if quit_after_suite:
		get_tree().quit(
			0 if _failed == 0 else 1
		)


# Starts a named section in the regression output.
func _section(title: String) -> void:
	print("")
	print("[TEST] --- ", title, " ---")


# Records a successful regression check.
func _pass(group: String, message: String) -> void:
	_passed += 1

	if print_pass_lines:
		print(
			"[PASS][",
			group,
			"] ",
			message
		)


# Records a failed regression check.
func _fail(group: String, message: String) -> void:
	_failed += 1
	print(
		"[FAIL][",
		group,
		"] ",
		message
	)


# Records a regression warning.
func _warn(group: String, message: String) -> void:
	_warnings += 1
	print(
		"[WARN][",
		group,
		"] ",
		message
	)


# Checks the true regression condition.
func _assert_true(
	group: String,
	condition: bool,
	message: String
) -> void:
	if condition:
		_pass(group, message)
	else:
		_fail(group, message)


# Checks the eq regression condition.
func _assert_eq(
	group: String,
	actual: Variant,
	expected: Variant,
	message: String
) -> void:
	if actual == expected:
		_pass(
			group,
			"%s | value=%s" % [
				message,
				str(actual)
			]
		)
	else:
		_fail(
			group,
			"%s | expected=%s actual=%s"
			% [
				message,
				str(expected),
				str(actual)
			]
		)


# Checks the approx regression condition.
func _assert_approx(
	group: String,
	actual: float,
	expected: float,
	tolerance: float,
	message: String
) -> void:
	if absf(actual - expected) <= tolerance:
		_pass(
			group,
			"%s | value=%s" % [
				message,
				str(actual)
			]
		)
	else:
		_fail(
			group,
			"%s | expected≈%s actual=%s"
			% [
				message,
				str(expected),
				str(actual)
			]
		)


# Checks the range regression condition.
func _assert_range(
	group: String,
	value: float,
	minimum: float,
	maximum: float,
	message: String
) -> void:
	if value >= minimum and value <= maximum:
		_pass(
			group,
			"%s | value=%s" % [
				message,
				str(value)
			]
		)
	else:
		_fail(
			group,
			"%s | expected %s..%s actual=%s"
			% [
				message,
				str(minimum),
				str(maximum),
				str(value)
			]
		)


# Calls a method and returns its Dictionary result safely.
func _call_dictionary(
	target: Object,
	method_name: String
) -> Dictionary:
	if target == null or not target.has_method(method_name):
		return {}

	var value: Variant = target.call(method_name)

	if typeof(value) != TYPE_DICTIONARY:
		return {}

	return (value as Dictionary).duplicate(true)


# Calls a method and returns its Array result safely.
func _call_array(
	target: Object,
	method_name: String
) -> Array:
	if target == null or not target.has_method(method_name):
		return []

	var value: Variant = target.call(method_name)

	if typeof(value) != TYPE_ARRAY:
		return []

	return (value as Array).duplicate(true)


# Handles dictionary value.
func _dict_value(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return (value as Dictionary).duplicate(true)

	return {}


# Reads an Array value used by the regression checks.
func _array_value(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return (value as Array).duplicate(true)

	return []


# Converts generic array data to a string array.
func _string_array(values: Array) -> Array[String]:
	var result: Array[String] = []

	for value: Variant in values:
		result.append(String(value))

	return result
