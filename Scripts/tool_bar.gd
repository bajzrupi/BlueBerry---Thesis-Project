extends CanvasLayer

# Toolbar UI state and dynamic button list

@onready var box: HBoxContainer = $Panel/HBoxContainer
var _group := ButtonGroup.new()
var _buttons: Array[Button] = []


# Build toolbar buttons and sync selection state
func _ready() -> void:
	_build_buttons()
	Toolsystem.tool_changed.connect(_on_tool_changed)
	_on_tool_changed(Toolsystem.current_tool)


# Rebuild toolbar button list from current tool order
func _build_buttons() -> void:
	for c in box.get_children():
		c.queue_free()
	_buttons.clear()

	for i in range(Toolsystem.order.size()):
		var tool_id: int = Toolsystem.order[i]
		var b := Button.new()
		b.text = "%d  %s" % [i + 1, Toolsystem.get_tool_name(tool_id)]
		b.toggle_mode = true
		b.button_group = _group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_button_pressed.bind(i))
		box.add_child(b)
		_buttons.append(b)


# Set tool when a toolbar button is pressed
func _on_button_pressed(index: int) -> void:
	Toolsystem.set_tool_by_index(index)


# Update pressed button when tool selection changes
func _on_tool_changed(tool_id: int) -> void:
	var idx := Toolsystem.order.find(tool_id)
	if idx >= 0 and idx < _buttons.size():
		_buttons[idx].button_pressed = true


# Handle scroll-wheel and number key tool switching
func _unhandled_input(event: InputEvent) -> void:
# Tool cycling input
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			Toolsystem.prev_tool()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			Toolsystem.next_tool()

# Direct tool selection input
	if event is InputEventKey and event.pressed and not event.echo:
		var k = event.keycode
		if k >= KEY_1 and k <= KEY_9:
			var idx := int(k - KEY_1)
			Toolsystem.set_tool_by_index(idx)
