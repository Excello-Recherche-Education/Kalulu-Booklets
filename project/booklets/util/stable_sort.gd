class_name StableSort
extends RefCounted
## Python's ``sorted(items, key=...)``, which keeps equal items in their order.
##
## ``Array.sort_custom`` is not stable, and where the order of equal items is
## printed, as it is in a booklet, the port must sort as Python does. Keys
## compare as Python's do: arrays item by item (tuples), false before true,
## numbers by value, strings by code point.


## A sorted copy of ``items``; ``key`` gives each item's key (the item itself
## when it is not given).
static func sorted(items: Array, key: Callable = Callable()) -> Array:
	var decorated: Array = []
	for index in items.size():
		var item: Variant = items[index]
		decorated.append([key.call(item) if key.is_valid() else item, index, item])
	decorated.sort_custom(func(a: Array, b: Array) -> bool:
		var order := compare(a[0], b[0])
		return order < 0 or (order == 0 and a[1] < b[1]))
	return decorated.map(func(entry: Array) -> Variant: return entry[2])


## -1, 0 or 1, as Python orders ``a`` and ``b``.
static func compare(a: Variant, b: Variant) -> int:
	if a is Array and b is Array:
		for index in mini(a.size(), b.size()):
			var order := compare(a[index], b[index])
			if order != 0:
				return order
		return signi(a.size() - b.size())
	if a is bool:
		a = int(a)
	if b is bool:
		b = int(b)
	if typeof(a) != typeof(b) and not ((a is int or a is float) and (b is int or b is float)):
		push_error("StableSort: cannot compare %s with %s" % [type_string(typeof(a)), type_string(typeof(b))])
		return 0
	if a < b:
		return -1
	if b < a:
		return 1
	return 0
