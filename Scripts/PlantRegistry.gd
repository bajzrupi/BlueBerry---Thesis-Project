extends Node

# Cell-to-plant lookup table
var plants_by_cell := {}

# Registre a plant instance for a given occupied cell
func register(cell: Vector2i, plant: Node) -> void:
	plants_by_cell[cell] = plant

# Remove a cell-to-plant mapping
func unregister(cell: Vector2i) -> void:
	if plants_by_cell.has(cell):
		plants_by_cell.erase(cell)

# Lookup plant occupying a given cell
func get_plant(cell: Vector2i) -> Node:
	return plants_by_cell.get(cell, null)
