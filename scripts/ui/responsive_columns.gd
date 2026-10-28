@tool
class_name ResponsiveColumns
extends Container
## Lays its children out in as many columns as fit, from one on a phone to
## [member max_columns] on a desktop. Children keep their order: with fewer
## columns than children, neighbours share a column, top to bottom.

@export_range(120, 1200) var min_column_width := 340:
	set(value):
		min_column_width = value
		queue_sort()
@export_range(1, 6) var max_columns := 3:
	set(value):
		max_columns = value
		queue_sort()
@export var separation := 16:
	set(value):
		separation = value
		queue_sort()
## Relative widths per column count, for example {3: [1.0, 1.2, 1.0]}.
@export var column_weights: Dictionary = {}


func get_column_count(width: float = -1.0) -> int:
	var w := size.x if width < 0.0 else width
	var fit := int((w + separation) / float(min_column_width + separation))
	return clampi(fit, 1, mini(max_columns, maxi(_visible_children().size(), 1)))


func _get_minimum_size() -> Vector2:
	var columns := _assign(get_column_count())
	var height := 0.0
	for column in columns:
		var h := 0.0
		for child: Control in column:
			h += child.get_combined_minimum_size().y
		h += separation * maxi(column.size() - 1, 0)
		height = maxf(height, h)
	return Vector2(minf(min_column_width, size.x if size.x > 0.0 else min_column_width), height)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_layout()
	elif what == NOTIFICATION_RESIZED:
		update_minimum_size()


func _visible_children() -> Array[Control]:
	var out: Array[Control] = []
	for child in get_children():
		if child is Control and child.visible and not child.top_level:
			out.append(child)
	return out


func _assign(count: int) -> Array:
	var children := _visible_children()
	var columns: Array = []
	for i in count:
		columns.append([])
	for i in children.size():
		columns[mini(i * count / maxi(children.size(), 1), count - 1)].append(children[i])
	return columns


func _layout() -> void:
	var count := get_column_count()
	var columns := _assign(count)
	var weights: Array = column_weights.get(count, [])
	var total_weight := 0.0
	for i in count:
		total_weight += float(weights[i]) if i < weights.size() else 1.0
	var free := size.x - separation * (count - 1)
	var x := 0.0
	for i in count:
		var w := free * (float(weights[i]) if i < weights.size() else 1.0) / total_weight
		var y := 0.0
		var column: Array = columns[i]
		for child: Control in column:
			var h := child.get_combined_minimum_size().y
			if column.size() == 1:
				h = maxf(h, size.y)
			elif child == column[column.size() - 1] and child.size_flags_vertical & SIZE_EXPAND:
				h = maxf(h, size.y - y)
			fit_child_in_rect(child, Rect2(x, y, w, h))
			y += h + separation
		x += w + separation
