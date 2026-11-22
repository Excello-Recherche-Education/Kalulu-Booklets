extends GutTest
## PythonRandom against Python's random.Random, and Sha512 against hashlib
## (both fixtures written by tools/godot_fixtures.py at 338cae2, the last
## commit with the Python generator).


func _fixture(name: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/%s" % name))


func test_sha512_matches_hashlib() -> void:
	for case: Dictionary in _fixture("sha512.json"):
		var message: String = case["message"]
		assert_eq(Sha512.digest(message.to_utf8_buffer()).hex_encode(), case["digest"],
				"SHA-512 of %d bytes" % message.to_utf8_buffer().size())


func test_random_matches_python() -> void:
	for case: Dictionary in _fixture("python_random.json")["cases"]:
		var rng := PythonRandom.new(case["seed"])
		# random() * 2^53 is an exact integer: compared as one, no float parsing
		# can blur the last bit.
		var floats: Array = []
		for _index in 8:
			floats.append(int(rng.random() * 9007199254740992.0))
		assert_eq(floats, case["random"].map(func(value: float) -> int: return int(value)),
				"random() for seed %s" % case["seed"])


func test_getrandbits_matches_python() -> void:
	for case: Dictionary in _fixture("python_random.json")["cases"]:
		var rng := PythonRandom.new(case["seed"])
		for _index in 8:
			rng.random()
		var bits: Array = []
		for count: int in [1, 5, 31, 32, 0, 17]:
			bits.append(rng.getrandbits(count))
		assert_eq(bits, case["getrandbits"].map(func(value: float) -> int: return int(value)),
				"getrandbits() for seed %s" % case["seed"])


func test_choice_matches_python() -> void:
	var fixture: Dictionary = _fixture("python_random.json")
	var sizes: Array = fixture["choice_sizes"]
	for case: Dictionary in fixture["cases"]:
		var rng := PythonRandom.new(case["seed"])
		for _index in 8:
			rng.random()
		for count: int in [1, 5, 31, 32, 0, 17]:
			rng.getrandbits(count)
		var chosen: Array = []
		for _round in 3:
			for size: float in sizes:
				chosen.append(rng.choice(range(int(size))))
		var mixed: Array = []
		for size: float in sizes:
			mixed.append(rng.random() < 0.7)
			mixed.append(rng.choice(range(int(size))))
		assert_eq(chosen, case["choice"].map(func(value: float) -> int: return int(value)),
				"choice() for seed %s" % case["seed"])
		assert_eq(str(mixed), str(case["mixed"].map(func(value: Variant) -> Variant:
				return int(value) if value is float else value)),
				"random() and choice() interleaved for seed %s" % case["seed"])
