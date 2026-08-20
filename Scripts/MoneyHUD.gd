extends CanvasLayer

# Compact screen-space money display.
@export_category("Money HUD")

# Controls the CanvasLayer drawing order.
@export var hud_layer: int = 6

# Positions the panel from the top-left corner.
@export var screen_offset: Vector2 = Vector2(16.0, 16.0)

# Controls the minimum panel size.
@export var panel_minimum_size: Vector2 = Vector2(150.0, 42.0)

# Optional coin texture assigned from the Inspector.
@export var coin_icon: Texture2D

# Controls the displayed coin icon size.
@export var icon_size: Vector2 = Vector2(26.0, 26.0)

# Optional currency symbol displayed before the amount.
@export var currency_symbol: String = ""

# Enables a brief visual pulse after money changes.
@export var animate_changes: bool = true


@export_category("Debug Logging")

# Enables money HUD initialization and update logs.
@export var debug_log: bool = false


# Stores the generated panel.
var _panel: PanelContainer

# Displays the current money amount.
var _amount_label: Label

# Stores the active update animation.
var _pulse_tween: Tween


# Builds the HUD and connects economy signals.
func _ready() -> void:
	layer = hud_layer

	_build_ui()
	_connect_economy_signals()
	_refresh_money()

	if debug_log:
		print(
			"[MoneyHUD] ready layer=",
			layer,
			" offset=",
			screen_offset,
			" money=",
			EconomySystem.get_money()
		)


# Creates the complete money panel.
func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "MoneyPanel"
	_panel.position = screen_offset
	_panel.custom_minimum_size = panel_minimum_size
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override(
		"panel",
		_create_panel_style()
	)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 6)
	_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.name = "MoneyRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	row.add_child(_create_coin_visual())

	_amount_label = Label.new()
	_amount_label.name = "Amount"
	_amount_label.text = "0"
	_amount_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_amount_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_amount_label.add_theme_font_size_override("font_size", 18)
	_amount_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.88, 0.34, 1.0)
	)
	_amount_label.add_theme_color_override(
		"font_outline_color",
		Color(0.12, 0.08, 0.02, 1.0)
	)
	_amount_label.add_theme_constant_override("outline_size", 3)
	row.add_child(_amount_label)


# Creates either the configured texture icon or a fallback symbol.
func _create_coin_visual() -> Control:
	if coin_icon != null:
		var icon := TextureRect.new()
		icon.name = "CoinIcon"
		icon.texture = coin_icon
		icon.custom_minimum_size = icon_size
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return icon

	var fallback := Label.new()
	fallback.name = "CoinFallback"
	fallback.text = "●"
	fallback.custom_minimum_size = icon_size
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fallback.add_theme_font_size_override("font_size", 24)
	fallback.add_theme_color_override(
		"font_color",
		Color(1.0, 0.76, 0.12, 1.0)
	)
	fallback.add_theme_color_override(
		"font_outline_color",
		Color(0.38, 0.21, 0.02, 1.0)
	)
	fallback.add_theme_constant_override("outline_size", 3)
	return fallback


# Creates the money panel background style.
func _create_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.055, 0.04, 0.9)
	style.border_color = Color(0.88, 0.64, 0.16, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_left = 7
	style.corner_radius_bottom_right = 7
	return style


# Connects the money HUD to the economy singleton.
func _connect_economy_signals() -> void:
	if not EconomySystem.money_changed.is_connected(
		_on_money_changed
	):
		EconomySystem.money_changed.connect(
			_on_money_changed
		)

	if not EconomySystem.economy_reset.is_connected(
		_on_economy_reset
	):
		EconomySystem.economy_reset.connect(
			_on_economy_reset
		)


# Refreshes the visible balance.
func _refresh_money() -> void:
	var amount := EconomySystem.get_money()
	var formatted_amount := _format_amount(amount)

	if currency_symbol.is_empty():
		_amount_label.text = formatted_amount
	else:
		_amount_label.text = (
			currency_symbol + formatted_amount
		)


# Formats large balances with thousands separators.
func _format_amount(amount: int) -> String:
	var digits := str(maxi(amount, 0))
	var formatted := ""
	var digit_count := 0

	for index in range(digits.length() - 1, -1, -1):
		if digit_count > 0 and digit_count % 3 == 0:
			formatted = "," + formatted

		formatted = digits.substr(index, 1) + formatted
		digit_count += 1

	return formatted


# Plays a brief pulse after a balance update.
func _play_change_pulse(delta: int) -> void:
	if not animate_changes or delta == 0:
		return

	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()

	var pulse_color := Color(1.0, 1.0, 1.0, 1.0)

	if delta > 0:
		pulse_color = Color(1.18, 1.15, 0.72, 1.0)
	else:
		pulse_color = Color(1.18, 0.72, 0.72, 1.0)

	_panel.modulate = pulse_color
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(
		_panel,
		"modulate",
		Color.WHITE,
		0.22
	)


# Handles a money balance change.
func _on_money_changed(
	previous_amount: int,
	new_amount: int,
	delta: int,
	reason: String
) -> void:
	_refresh_money()
	_play_change_pulse(delta)

	if debug_log:
		print(
			"[MoneyHUD] update old=",
			previous_amount,
			" new=",
			new_amount,
			" delta=",
			delta,
			" reason=",
			reason
		)


# Handles a complete economy reset.
func _on_economy_reset(current_amount: int) -> void:
	_refresh_money()

	if debug_log:
		print(
			"[MoneyHUD] economy reset money=",
			current_amount
		)
