extends GutTest


func test_equal_keys_keep_their_order() -> void:
	var items: Array = []
	for index in 200:
		items.append({"key": index % 3, "order": index})
	var result := StableSort.sorted(items, func(item: Dictionary) -> int: return item["key"])
	for index in range(1, result.size()):
		var before: Dictionary = result[index - 1]
		var after: Dictionary = result[index]
		assert_true(before["key"] < after["key"] or (before["key"] == after["key"] and before["order"] < after["order"]))


func test_keys_compare_as_python_tuples() -> void:
	# content._candidates: (not item.booklet_only, item.id).
	var items := [[false, 3], [true, 1], [false, 1], [true, 2]]
	var result := StableSort.sorted(items, func(item: Array) -> Array: return [not item[0], item[1]])
	assert_eq(result, [[true, 1], [true, 2], [false, 1], [false, 3]])


func test_strings_compare_by_code_point() -> void:
	assert_eq(StableSort.sorted(["b", "a", "é", "Z", "e"]), ["Z", "a", "b", "e", "é"])


func test_shorter_tuple_first() -> void:
	assert_eq(StableSort.compare([1, 2], [1, 2, 0]), -1)
	assert_eq(StableSort.compare([2], [1, 9]), 1)
	assert_eq(StableSort.compare([1.5, "a"], [1.5, "a"]), 0)
