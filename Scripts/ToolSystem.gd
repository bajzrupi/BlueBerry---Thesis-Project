extends Node
class_name ToolSystem

signal tool_changed(tool_id: int)

enum Tool { PLANT, WATER, FERTILIZE, LIME, ACID, PESTICIDE, FUNGICIDE, SHOVEL }


# Tool selection state and toolbar ordering
@export var order: Array[int] = [
	Tool.PLANT,
	Tool.WATER,
	Tool.FERTILIZE,
	Tool.LIME,
	Tool.ACID,
	Tool.PESTICIDE,
	Tool.FUNGICIDE,
	Tool.SHOVEL
]

var current_tool: int = Tool.PLANT


# Set active tool and notify listeners
func set_tool(tool_id: int) -> void:
	if tool_id == current_tool:
		return
	current_tool = tool_id
	print("[Tool] switched to:", get_tool_name(current_tool), " (id=", current_tool, ")")
	tool_changed.emit(current_tool)


# Select tool by toolbar index
func set_tool_by_index(idx: int) -> void:
	if idx < 0 or idx >= order.size():
		return
	set_tool(order[idx])


# Cycle to next tool in order
func next_tool() -> void:
	var i := order.find(current_tool)
	if i == -1:
		set_tool(order[0])
		return
	set_tool(order[(i + 1) % order.size()])


# Cycle to previous tool in order
func prev_tool() -> void:
	var i := order.find(current_tool)
	if i == -1:
		set_tool(order[0])
		return
	set_tool(order[(i - 1 + order.size()) % order.size()])


# Convert tool enum value to display name
func get_tool_name(tool_id: int) -> String:
	match tool_id:
		Tool.PLANT: return "Plant"
		Tool.WATER: return "Water"
		Tool.FERTILIZE: return "Fertilize"
		Tool.LIME: return "Lime (+pH)"
		Tool.ACID: return "Acid (-pH)"
		Tool.PESTICIDE: return "Pesticide"
		Tool.FUNGICIDE: return "Fungicide"
		Tool.SHOVEL: return "Shovel (Remove)"
	return "?"
