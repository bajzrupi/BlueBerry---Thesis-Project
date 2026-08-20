extends CanvasLayer

# Modal milestone reward screen with celebratory spark bursts.
# Ordinary player level increases are intentionally HUD-only.

const FADE_IN_SECONDS: float = 0.18
const FADE_OUT_SECONDS: float = 0.16
const FIREWORK_INTERVAL_SECONDS: float = 0.72
const FIREWORK_SPARKS_PER_BURST: int = 18
const FIREWORK_MIN_DISTANCE: float = 54.0
const FIREWORK_MAX_DISTANCE: float = 118.0
const FIREWORK_MIN_DURATION: float = 0.55
const FIREWORK_MAX_DURATION: float = 0.95

const FIREWORK_COLORS: Array[Color] = [
	Color(1.00, 0.82, 0.20, 1.00),
	Color(1.00, 0.40, 0.36, 1.00),
	Color(0.42, 0.82, 1.00, 1.00),
	Color(0.50, 1.00, 0.58, 1.00),
	Color(0.86, 0.54, 1.00, 1.00)
]

@export_category("Debug Logging")
@export var debug_log: bool = false

var _queue: Array[Dictionary] = []
var _busy: bool = false

var _pending_level: int = -1
var _pending_milestone: Dictionary = {}
var _flush_scheduled: bool = false
var _last_milestone_level: int = -1

var _modal_lock_active: bool = false
var _previous_tree_paused: bool = false
var _previous_mouse_mode: int = Input.MOUSE_MODE_HIDDEN
var _current_event_type: String = ""

var _rng := RandomNumberGenerator.new()

var _screen_root: Control
var _blocker: ColorRect
var _panel: PanelContainer
var _title_label: Label
var _level_label: Label
var _detail_label: Label
var _reward_separator: HSeparator
var _reward_box: VBoxContainer
var _money_reward_label: Label
var _token_reward_label: Label
var _build_reward_label: Label
var _ok_button: Button

var _fireworks_root: Node2D
var _firework_timer: Timer


# Initializes this system when the node becomes ready.
func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS

	_rng.randomize()

	_create_fireworks()
	_create_ui()
	_connect_progression_signals()


	if debug_log:
		print(
			"[ProgressionNotification] ready milestone_only=true fireworks=true"
		)


# Keep the cursor visible for the entire modal lifetime.
# test_level normally hides the gameplay cursor, so the modal owns the mouse
# mode while its input lock is active.
func _process(_delta: float) -> void:
	if (
		_modal_lock_active
		and Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE
	):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


# While the reward screen is open, only mouse movement and the OK button are allowed.
func _input(event: InputEvent) -> void:
	if not _modal_lock_active:
		return

	if event is InputEventMouseMotion:
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton

		if (
			_ok_button != null
			and _ok_button.visible
			and _ok_button.get_global_rect().has_point(
				mouse_event.position
			)
		):
			return

		get_viewport().set_input_as_handled()
		return

	# Keyboard, joypad, touch and other gameplay input are blocked.
	get_viewport().set_input_as_handled()


# Connects the progression signals signals and callbacks.
func _connect_progression_signals() -> void:
	if not ProgressionSystem.player_level_changed.is_connected(
		_on_player_level_changed
	):
		ProgressionSystem.player_level_changed.connect(
			_on_player_level_changed
		)

	if not ProgressionSystem.player_milestone_reached.is_connected(
		_on_player_milestone_reached
	):
		ProgressionSystem.player_milestone_reached.connect(
			_on_player_milestone_reached
		)


# Ordinary player level increases are shown by the progression HUD only.
# Modal notifications are reserved for milestone rewards.
func _on_player_level_changed(
	_previous_level: int,
	_new_level: int
) -> void:
	_pending_level = -1


# Handles the player milestone reached signal or callback.
func _on_player_milestone_reached(
	level_value: int,
	money_reward: int,
	plant_unlock_tokens: int,
	build_cell_credits: int
) -> void:
	_pending_level = -1
	_pending_milestone = {
		"type": "milestone",
		"level": level_value,
		"money": money_reward,
		"plant_unlock_tokens": plant_unlock_tokens,
		"build_cell_credits": build_cell_credits
	}
	_last_milestone_level = level_value

	_schedule_pending_flush()


# Schedules the pending flush.
func _schedule_pending_flush() -> void:
	if _flush_scheduled:
		return

	_flush_scheduled = true
	call_deferred("_flush_pending_events")


# Handles flush pending events.
func _flush_pending_events() -> void:
	_flush_scheduled = false

	if not _pending_milestone.is_empty():
		_enqueue_notification(
			_pending_milestone.duplicate(true)
		)
		_pending_milestone.clear()
		_pending_level = -1
		return

	_pending_level = -1


# Handles enqueue notification.
func _enqueue_notification(event: Dictionary) -> void:
	_queue.append(event)

	if not _busy:
		_show_next_notification()


# Shows the next notification.
func _show_next_notification() -> void:
	if _queue.is_empty():
		_busy = false
		_release_modal_lock()
		return

	_busy = true

	var event: Dictionary = _queue.pop_front()
	_current_event_type = String(
		event.get("type", "level")
	)

	if _current_event_type == "milestone":
		_configure_milestone(event)
	else:
		_configure_level_up(event)

	_acquire_modal_lock()

	_screen_root.visible = true
	_screen_root.modulate = Color(
		1.0,
		1.0,
		1.0,
		0.0
	)
	_fireworks_root.visible = true
	_ok_button.disabled = false

	var tween: Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(
		_screen_root,
		"modulate:a",
		1.0,
		FADE_IN_SECONDS
	)

	_spawn_opening_fireworks()

	if _current_event_type == "milestone":
		_firework_timer.start()
	else:
		_firework_timer.stop()

	if debug_log:
		print(
			"[ProgressionNotification] modal opened type=",
			_current_event_type
		)


# Handles configure level up.
func _configure_level_up(event: Dictionary) -> void:
	var level_value: int = int(event.get("level", 0))
	var next_milestone: int = (
		_next_milestone_after(level_value)
	)

	_title_label.text = "LEVEL UP!"
	_level_label.text = "PLAYER LEVEL %d" % level_value
	_detail_label.text = (
		"Next milestone: Level %d" % next_milestone
	)

	_reward_separator.visible = false
	_reward_box.visible = false

	if debug_log:
		print(
			"[ProgressionNotification] LEVEL UP level=",
			level_value,
			" next_milestone=",
			next_milestone
		)


# Handles configure milestone.
func _configure_milestone(event: Dictionary) -> void:
	var level_value: int = int(event.get("level", 0))
	var money_reward: int = int(
		event.get("money", 0)
	)
	var unlock_tokens: int = int(
		event.get("plant_unlock_tokens", 0)
	)
	var build_credits: int = int(
		event.get("build_cell_credits", 0)
	)
	var next_milestone: int = (
		_next_milestone_after(level_value)
	)

	_title_label.text = "MILESTONE REACHED!"
	_level_label.text = "PLAYER LEVEL %d" % level_value
	_detail_label.text = (
		"Next milestone: Level %d" % next_milestone
	)

	_money_reward_label.text = "+$%d" % money_reward
	_token_reward_label.text = (
		"+%d Plant Unlock Token%s"
		% [
			unlock_tokens,
			"" if unlock_tokens == 1 else "s"
		]
	)
	_build_reward_label.text = (
		"+%d Build Credits" % build_credits
	)

	_reward_separator.visible = true
	_reward_box.visible = true

	if debug_log:
		print(
			"[ProgressionNotification] MILESTONE level=",
			level_value,
			" money=",
			money_reward,
			" plant_unlock_tokens=",
			unlock_tokens,
			" build_cell_credits=",
			build_credits,
			" next_milestone=",
			next_milestone
		)


# Handles next milestone after.
func _next_milestone_after(level_value: int) -> int:
	var interval: int = (
		ProgressionSystem.PLAYER_MILESTONE_INTERVAL
	)
	return (
		(int(level_value / interval) + 1)
		* interval
	)


# Acquires the modal lock.
func _acquire_modal_lock() -> void:
	if _modal_lock_active:
		return

	_previous_tree_paused = get_tree().paused
	_previous_mouse_mode = Input.get_mouse_mode()

	_modal_lock_active = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# One deferred reinforcement avoids a same-frame gameplay mouse-mode write
	# from winning immediately after the popup opens.
	call_deferred("_ensure_modal_mouse_visible")

	get_viewport().gui_release_focus()

	if debug_log:
		print(
			"[ProgressionNotification] input lock ON previous_paused=",
			_previous_tree_paused,
			" previous_mouse_mode=",
			_previous_mouse_mode
		)


# Ensures the modal mouse visible exists and is ready to use.
func _ensure_modal_mouse_visible() -> void:
	if not _modal_lock_active:
		return

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


# Releases the modal lock.
func _release_modal_lock() -> void:
	if not _modal_lock_active:
		return

	_modal_lock_active = false
	get_tree().paused = _previous_tree_paused
	Input.set_mouse_mode(_previous_mouse_mode)

	if debug_log:
		print(
			"[ProgressionNotification] input lock OFF restored_paused=",
			_previous_tree_paused,
			" restored_mouse_mode=",
			_previous_mouse_mode
		)


# Handles the ok pressed signal or callback.
func _on_ok_pressed() -> void:
	if not _busy or not _modal_lock_active:
		return

	_ok_button.disabled = true
	_firework_timer.stop()

	var tween: Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(
		_screen_root,
		"modulate:a",
		0.0,
		FADE_OUT_SECONDS
	)
	tween.finished.connect(_on_modal_faded_out)

	if debug_log:
		print(
			"[ProgressionNotification] OK pressed type=",
			_current_event_type
		)


# Handles the modal faded out signal or callback.
func _on_modal_faded_out() -> void:
	_screen_root.visible = false
	_screen_root.modulate = Color.WHITE
	_fireworks_root.visible = false
	_clear_fireworks()

	_current_event_type = ""
	_busy = false

	if not _queue.is_empty():
		call_deferred("_show_next_notification")
		return

	_release_modal_lock()


# Creates the UI.
func _create_ui() -> void:
	_screen_root = Control.new()
	_screen_root.name = "ProgressionNotificationRoot"
	_screen_root.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	_screen_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_root.visible = false
	_screen_root.z_index = 2
	add_child(_screen_root)

	_blocker = ColorRect.new()
	_blocker.name = "ModalBlocker"
	_blocker.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	_blocker.color = Color(
		0.02,
		0.025,
		0.03,
		0.70
	)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_blocker.gui_input.connect(_on_blocker_gui_input)
	_screen_root.add_child(_blocker)

	_panel = PanelContainer.new()
	_panel.name = "NotificationPanel"
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -245.0
	_panel.offset_right = 245.0
	_panel.offset_top = -176.0
	_panel.offset_bottom = 176.0
	_panel.custom_minimum_size = Vector2(
		490.0,
		352.0
	)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.z_index = 2
	_screen_root.add_child(_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(
		0.075,
		0.085,
		0.095,
		0.97
	)
	panel_style.border_color = Color(
		0.74,
		0.61,
		0.27,
		1.0
	)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	_panel.add_theme_stylebox_override(
		"panel",
		panel_style
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override(
		"margin_left",
		28
	)
	margin.add_theme_constant_override(
		"margin_right",
		28
	)
	margin.add_theme_constant_override(
		"margin_top",
		22
	)
	margin.add_theme_constant_override(
		"margin_bottom",
		22
	)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(
		"separation",
		8
	)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	_title_label = Label.new()
	_title_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_title_label.add_theme_font_size_override(
		"font_size",
		24
	)
	_title_label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	column.add_child(_title_label)

	_level_label = Label.new()
	_level_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_level_label.add_theme_font_size_override(
		"font_size",
		34
	)
	_level_label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	column.add_child(_level_label)

	_detail_label = Label.new()
	_detail_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_detail_label.add_theme_font_size_override(
		"font_size",
		14
	)
	_detail_label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	column.add_child(_detail_label)

	_reward_separator = HSeparator.new()
	_reward_separator.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	column.add_child(_reward_separator)

	_reward_box = VBoxContainer.new()
	_reward_box.add_theme_constant_override(
		"separation",
		4
	)
	_reward_box.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	column.add_child(_reward_box)

	_money_reward_label = _create_reward_label()
	_reward_box.add_child(_money_reward_label)

	_token_reward_label = _create_reward_label()
	_reward_box.add_child(_token_reward_label)

	_build_reward_label = _create_reward_label()
	_reward_box.add_child(_build_reward_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(
		0.0,
		8.0
	)
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	_ok_button = Button.new()
	_ok_button.text = "OK"
	_ok_button.custom_minimum_size = Vector2(
		150.0,
		44.0
	)
	_ok_button.size_flags_horizontal = (
		Control.SIZE_SHRINK_CENTER
	)
	_ok_button.focus_mode = Control.FOCUS_NONE
	_ok_button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
	)
	_ok_button.pressed.connect(_on_ok_pressed)
	column.add_child(_ok_button)


# Creates the reward label.
func _create_reward_label() -> Label:
	var label := Label.new()
	label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	label.add_theme_font_size_override(
		"font_size",
		17
	)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# Handles the blocker GUI input signal or callback.
func _on_blocker_gui_input(event: InputEvent) -> void:
	if not _modal_lock_active:
		return

	if (
		event is InputEventMouseButton
		or event is InputEventScreenTouch
		or event is InputEventScreenDrag
	):
		_blocker.accept_event()


# Creates the fireworks.
func _create_fireworks() -> void:
	_fireworks_root = Node2D.new()
	_fireworks_root.name = "ProgressionFireworks"
	_fireworks_root.z_index = 1
	_fireworks_root.visible = false
	add_child(_fireworks_root)

	_firework_timer = Timer.new()
	_firework_timer.name = "FireworkTimer"
	_firework_timer.wait_time = FIREWORK_INTERVAL_SECONDS
	_firework_timer.one_shot = false
	_firework_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_firework_timer.timeout.connect(_on_firework_timer_timeout)
	add_child(_firework_timer)


# Spawns the opening fireworks feedback or runtime content.
func _spawn_opening_fireworks() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var center := viewport_size * 0.5

	_spawn_firework_burst(
		center + Vector2(-265.0, -112.0)
	)
	_spawn_firework_burst(
		center + Vector2(265.0, -112.0)
	)

	if _current_event_type == "milestone":
		_spawn_firework_burst(
			center + Vector2(0.0, -192.0)
		)


# Handles the firework timer timeout signal or callback.
func _on_firework_timer_timeout() -> void:
	if (
		not _modal_lock_active
		or _current_event_type != "milestone"
	):
		return

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var center := viewport_size * 0.5
	var side: float = -1.0 if _rng.randi_range(0, 1) == 0 else 1.0

	var origin := center + Vector2(
		side * _rng.randf_range(220.0, 330.0),
		_rng.randf_range(-175.0, 55.0)
	)

	_spawn_firework_burst(origin)


# Spawns the firework burst feedback or runtime content.
func _spawn_firework_burst(origin: Vector2) -> void:
	for index: int in range(FIREWORK_SPARKS_PER_BURST):
		var angle: float = (
			TAU
			* float(index)
			/ float(FIREWORK_SPARKS_PER_BURST)
			+ _rng.randf_range(-0.10, 0.10)
		)
		var distance: float = _rng.randf_range(
			FIREWORK_MIN_DISTANCE,
			FIREWORK_MAX_DISTANCE
		)
		var duration: float = _rng.randf_range(
			FIREWORK_MIN_DURATION,
			FIREWORK_MAX_DURATION
		)
		var target := origin + Vector2(
			cos(angle),
			sin(angle)
		) * distance

		var spark := Polygon2D.new()
		spark.polygon = PackedVector2Array([
			Vector2(-3.0, 0.0),
			Vector2(0.0, -3.0),
			Vector2(3.0, 0.0),
			Vector2(0.0, 3.0)
		])
		spark.color = FIREWORK_COLORS[
			_rng.randi_range(
				0,
				FIREWORK_COLORS.size() - 1
			)
		]
		spark.position = origin
		spark.scale = Vector2(
			_rng.randf_range(0.75, 1.30),
			_rng.randf_range(0.75, 1.30)
		)

		_fireworks_root.add_child(spark)

		var tween: Tween = create_tween()
		tween.set_pause_mode(
			Tween.TWEEN_PAUSE_PROCESS
		)
		tween.set_parallel(true)
		tween.tween_property(
			spark,
			"position",
			target,
			duration
		).set_trans(
			Tween.TRANS_QUAD
		).set_ease(
			Tween.EASE_OUT
		)
		tween.tween_property(
			spark,
			"rotation",
			_rng.randf_range(-3.5, 3.5),
			duration
		)
		tween.tween_property(
			spark,
			"scale",
			Vector2(0.18, 0.18),
			duration
		)
		tween.tween_property(
			spark,
			"modulate:a",
			0.0,
			duration
		).set_delay(
			duration * 0.38
		)
		tween.finished.connect(
			spark.queue_free
		)


# Clears the fireworks.
func _clear_fireworks() -> void:
	for child: Node in _fireworks_root.get_children():
		child.queue_free()
