extends Node

# Coordinates transitions between the startup Main Menu and the gameplay scene.
# The gameplay scene calls on_world_ready() after its world-bound systems have
# finished configuring.

signal game_launch_failed(reason: String)

enum LaunchMode {
	NONE,
	NEW_GAME,
	CONTINUE
}

const GAME_SCENE_PATH: String = "res://Scenes/test_level.tscn"
const MAIN_MENU_SCENE_PATH: String = "res://Scenes/MainMenu.tscn"

@export_category("Debug Logging")
@export var debug_log: bool = false

var _pending_launch_mode: int = LaunchMode.NONE
var _scene_change_in_progress: bool = false


# Initializes this system when the node becomes ready.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	if debug_log:
		print("[GameFlow] ready")


# Called by the startup Main Menu.
func prepare_main_menu() -> void:
	# Main Menu is a clean navigation state. Clear any gameplay launch /
	# transition flags so returning from an active Garden can immediately
	# launch another Garden or start a New Game.
	_pending_launch_mode = LaunchMode.NONE
	_scene_change_in_progress = false

	Clock.set_paused(true)

	if Clock.has_method("reset_time_scale"):
		Clock.reset_time_scale()

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if debug_log:
		print(
			"[GameFlow] main menu prepared saves=",
			SaveSystem.get_existing_slots(),
			" preferred_continue=",
			SaveSystem.get_preferred_continue_slot()
		)


# Starts a completely fresh gameplay session in the chosen Garden slot.
# An existing save in that slot is deleted only after Character Select has
# already been confirmed by the player.
func start_new_game(slot: int) -> bool:
	if _scene_change_in_progress:
		return false

	if not SaveSystem.is_valid_slot(slot):
		return _fail_launch("INVALID_SLOT_%d" % slot)

	if not SaveSystem.set_active_slot(slot):
		return _fail_launch("ACTIVE_SLOT_FAILED")

	if SaveSystem.has_save(slot):
		if not SaveSystem.delete_save(slot, true):
			return _fail_launch("SAVE_DELETE_FAILED")

	_reset_new_game_runtime_state()

	_pending_launch_mode = LaunchMode.NEW_GAME
	Clock.set_paused(false)

	if debug_log:
		print(
			"[GameFlow] NEW GAME slot=",
			slot,
			" character=",
			CharacterSystem.get_current_character_id()
		)

	return _change_to_game_scene()


# Starts gameplay from a specific Garden slot. Passing -1 uses the most
# recently active Garden that still has a save.
func continue_game(slot: int = -1) -> bool:
	if _scene_change_in_progress:
		return false

	var resolved_slot: int = slot

	if resolved_slot == -1:
		resolved_slot = SaveSystem.get_preferred_continue_slot()

	if not SaveSystem.is_valid_slot(resolved_slot):
		return _fail_launch("NO_SAVE")

	if not SaveSystem.has_save(resolved_slot):
		return _fail_launch("NO_SAVE_IN_SLOT_%d" % resolved_slot)

	if not SaveSystem.set_active_slot(resolved_slot):
		return _fail_launch("ACTIVE_SLOT_FAILED")

	_pending_launch_mode = LaunchMode.CONTINUE
	Clock.set_paused(false)

	if debug_log:
		print(
			"[GameFlow] CONTINUE requested slot=",
			resolved_slot
		)

	return _change_to_game_scene()


# Called from test_level.gd at the end of _ready().
func on_world_ready() -> void:
	match _pending_launch_mode:
		LaunchMode.NONE:
			if debug_log:
				print(
					"[GameFlow] world ready mode=direct slot=",
					SaveSystem.get_active_slot()
				)
		LaunchMode.NEW_GAME:
			_pending_launch_mode = LaunchMode.NONE
			_scene_change_in_progress = false

			if debug_log:
				print(
					"[GameFlow] world ready mode=new_game slot=",
					SaveSystem.get_active_slot(),
					" character=",
					CharacterSystem.get_current_character_id()
				)
		LaunchMode.CONTINUE:
			# Defer one more step so every sibling/overlay has completed startup
			# before SaveSystem restores the selected Garden.
			call_deferred("_finish_continue_load")


# Finishes the continue load.
func _finish_continue_load() -> void:
	var loaded: bool = SaveSystem.load_game()

	_pending_launch_mode = LaunchMode.NONE
	_scene_change_in_progress = false

	if not loaded:
		_fail_launch("CONTINUE_LOAD_FAILED")
		return

	if debug_log:
		print(
			"[GameFlow] CONTINUE completed slot=",
			SaveSystem.get_active_slot(),
			" character=",
			CharacterSystem.get_current_character_id()
		)


# Returns from an active Garden to the startup Main Menu.
# Saving is intentionally handled by the Pause Menu before this call; this
# transition itself never silently overwrites the player's Garden save.
func return_to_main_menu() -> bool:
	if _scene_change_in_progress:
		return false

	_pending_launch_mode = LaunchMode.NONE
	_scene_change_in_progress = true

	# Scene changes must not remain trapped behind the paused SceneTree.
	get_tree().paused = false

	if Clock.has_method("reset_time_scale"):
		Clock.reset_time_scale()

	Clock.set_paused(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	var error: Error = get_tree().change_scene_to_file(
		MAIN_MENU_SCENE_PATH
	)

	if error != OK:
		_scene_change_in_progress = false
		Clock.set_paused(false)

		return _fail_launch(
			"MAIN_MENU_SCENE_CHANGE_ERROR_%s" % error
		)

	# change_scene_to_file() schedules the replacement safely; the new
	# MainMenu._ready() will call prepare_main_menu() and fully normalize state.
	return true


# Restores persistent Autoload state to a true New Game baseline.
# World-specific state comes from the freshly instanced gameplay scene.
func _reset_new_game_runtime_state() -> void:
	get_tree().paused = false

	EconomySystem.reset_to_defaults()
	ProgressionSystem.reset_to_defaults()

	# Progression reset refreshes the available plant list first.
	InventorySystem.reset_to_defaults()
	PlantSelectionSystem.deselect_plant()
	InventoryLayoutSystem.reset_to_defaults()
	HotbarSystem.reset_to_defaults()

	Toolsystem.reset_durability()
	Toolsystem.set_tool(Toolsystem.Tool.PLANT)

	Clock.reset_to_defaults()
	WeatherSystem.roll_daily_weather()

	if debug_log:
		print(
			"[GameFlow] new game state reset slot=",
			SaveSystem.get_active_slot(),
			" money=",
			EconomySystem.get_money(),
			" player_level=",
			ProgressionSystem.player_level,
			" inventory=",
			InventorySystem.get_all_items(),
			" day=",
			Clock.day,
			" time=",
			Clock.format_time()
		)


# Changes the to game scene.
func _change_to_game_scene() -> bool:
	_scene_change_in_progress = true

	var error: Error = get_tree().change_scene_to_file(
		GAME_SCENE_PATH
	)

	if error != OK:
		_scene_change_in_progress = false
		_pending_launch_mode = LaunchMode.NONE

		return _fail_launch(
			"SCENE_CHANGE_ERROR_%s" % error
		)

	return true


# Reports a failed game-launch attempt.
func _fail_launch(reason: String) -> bool:
	push_warning(
		"[GameFlow] launch failed reason=%s" % reason
	)
	game_launch_failed.emit(reason)
	return false
