extends GutTest
## Syllables and words repeated for want of more (BookletContent.arranged):
## shuffled, never beside or under themselves (the PO's rule, 2026-11-17).
## Ported from the Python generator's tests/test_repeats.py.

const Tiny := preload("res://tests/helpers/tiny_pack.gd")

## [distinct items, columns, count]
const SHAPES := [[2, 2, 8], [3, 3, 12], [3, 6, 12], [4, 3, 12], [4, 4, 16], [5, 3, 15], [7, 6, 24], [12, 6, 36]]


func after_all() -> void:
	Tiny.forget_all()


## [texts, rows]
static func _grid(items: Array, count: int, columns: int, seed: String = "seed") -> Array:
	var styled: Array[BookletContent.Styled] = []
	for text: String in items:
		styled.append(BookletContent.Styled.new(text))
	var texts := BookletContent.arranged(styled, count, columns, seed).map(func(item: BookletContent.Styled) -> String:
		return item.text)
	var rows: Array = []
	for start in range(0, count, columns):
		rows.append(texts.slice(start, start + columns))
	return [texts, rows]


static func _letters(count: int) -> Array:
	return Array("abcdefghijkl".substr(0, count).split(""))


func test_a_repeat_is_never_beside_itself_nor_under_itself() -> void:
	for shape: Array in SHAPES:
		var grid := _grid(_letters(shape[0]), shape[2], shape[1])
		var texts: Array = grid[0]
		for row: Array in grid[1]:
			for index in range(1, row.size()):
				assert_ne(row[index], row[index - 1], "%s: beside itself" % [shape])
		for index in range(shape[1], shape[2]):
			assert_ne(texts[index], texts[index - shape[1]], "%s: under itself" % [shape])


func test_every_item_comes_up_as_often_as_another() -> void:
	for shape: Array in SHAPES:
		var times := {}
		for text: String in _grid(_letters(shape[0]), shape[2], shape[1])[0]:
			times[text] = times.get(text, 0) + 1
		assert_eq(times.size(), shape[0], "%s" % [shape])
		assert_lte(times.values().max() - times.values().min(), 1, "%s" % [shape])


func test_the_first_round_keeps_its_order() -> void:
	assert_eq(_grid(_letters(4), 12, 3)[0].slice(0, 4), ["a", "b", "c", "d"])


func test_as_many_rows_as_items_put_each_once_in_every_column() -> void:
	var rows: Array = _grid(_letters(4), 16, 4)[1]
	for column in 4:
		var cells := rows.map(func(row: Array) -> String: return row[column])
		cells.sort()
		assert_eq(cells, ["a", "b", "c", "d"])


func test_the_same_pack_prints_the_same_grid() -> void:
	assert_eq(_grid(_letters(5), 30, 6), _grid(_letters(5), 30, 6))


func test_enough_items_are_not_repeated() -> void:
	assert_eq(_grid(_letters(6), 6, 3)[0], ["a", "b", "c", "d", "e", "f"])


func test_an_adapted_grid_is_arranged_for_its_own_columns() -> void:
	var pack_folder := Tiny.make()
	if pack_folder.is_empty():
		pending("kalulu-languages/ is not checked out")
		return
	# Three syllables in 6 columns, printed in 3 by an adapted version: in the
	# pack's arrangement each would sit under itself.
	Tiny.add_chapter(pack_folder, 3, [3, 4, 5], {"SyllableCount": 12, "SyllableColumns": 6})
	var chapter: BookletContent.ChapterContent = BookletContent.booklet(Tiny.read(pack_folder), 1).chapters.filter(
			func(content: BookletContent.ChapterContent) -> bool: return content.chapter.lesson == 3)[0]
	var in_three := chapter.syllables_in(3).map(func(item: BookletContent.Styled) -> String: return item.text)
	assert_eq(in_three.size(), 12)
	for index in range(3, 12):
		assert_ne(in_three[index], in_three[index - 3])
	assert_same(chapter.syllables_in(6), chapter.syllables)


func test_a_syllable_picked_twice_is_one_item_of_a_round() -> void:
	# "la le la le al al", then rounds of three: each comes up as often.
	var texts: Array = _grid(["la", "le", "la", "le", "al", "al"], 18, 6)[0]
	var times := {}
	for text: String in texts:
		times[text] = times.get(text, 0) + 1
	assert_eq(times, {"la": 6, "le": 6, "al": 6})
	for index in range(6, 18):
		assert_ne(texts[index], texts[index - 6])
