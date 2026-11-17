class_name SectionChip
extends Button
## One section on the structure timeline. Drag it onto another chip to move
## it there; press it to pick it for lock, regenerate, duplicate or remove.

signal moved(from_index: int, to_index: int)

## Position in the play order.
var index := 0


func _get_drag_data(_at_position: Vector2) -> Variant:
	var preview := Button.new()
	preview.text = text
	preview.theme_type_variation = theme_type_variation
	set_drag_preview(preview)
	return {"section_chip": index}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("section_chip") and int(data["section_chip"]) != index


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	moved.emit(int(data["section_chip"]), index)
