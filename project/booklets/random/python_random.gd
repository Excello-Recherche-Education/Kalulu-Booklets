class_name PythonRandom
extends RefCounted
## Python's ``random.Random``, number for number: the Mersenne Twister
## (MT19937) as CPython seeds and uses it.
##
## The grids lay their syllables and words out with ``random.Random(seed)``,
## seeded from a string, and the booklets the PO reviewed are those
## arrangements. Godot's own generator is PCG32: the same seed would give other
## numbers, so every grid would come out different. This one gives Python's.
##
## Only what the generator uses is here: string seeds, ``random()``,
## ``getrandbits()`` up to 32 bits, and ``choice()`` (through ``_randbelow``,
## by rejection, as CPython 3.2 and later do).

const _N := 624
const _M := 397
const _MATRIX_A := 0x9908b0df
const _UPPER := 0x80000000
const _LOWER := 0x7fffffff
const _MASK := 0xffffffff

var _state := PackedInt64Array()
var _index := _N


## Seeded as ``random.Random(seed)`` with a str seed: its UTF-8 bytes followed
## by their SHA-512 digest, read as one big-endian integer.
func _init(seed: String) -> void:
	var bytes := seed.to_utf8_buffer()
	bytes.append_array(Sha512.digest(bytes))
	_seed_bytes(bytes)


## A float in [0, 1), with 53 random bits, as ``random.random()``.
func random() -> float:
	var high := _next() >> 5
	var low := _next() >> 6
	return (high * 67108864.0 + low) * (1.0 / 9007199254740992.0)


## ``bits`` random bits, 0 <= bits <= 32, as ``random.getrandbits()``.
func getrandbits(bits: int) -> int:
	assert(bits >= 0 and bits <= 32, "getrandbits: only up to 32 bits are ported")
	if bits == 0:
		return 0
	return _next() >> (32 - bits)


## An item of ``items``, as ``random.choice()``.
func choice(items: Array) -> Variant:
	assert(not items.is_empty(), "choice: cannot choose from an empty sequence")
	return items[randbelow(items.size())]


## A random integer in [0, n), n > 0, as ``Random._randbelow()``.
func randbelow(n: int) -> int:
	var bits := _bit_length(n)
	var value := getrandbits(bits)
	while value >= n:
		value = getrandbits(bits)
	return value


func _seed_bytes(bytes: PackedByteArray) -> void:
	# CPython splits the integer into 32-bit words, least significant first.
	var start := 0
	while start < bytes.size() and bytes[start] == 0:
		start += 1
	var key := PackedInt64Array()
	var end := bytes.size()
	while end > start:
		var word := 0
		for at in range(maxi(start, end - 4), end):
			word = (word << 8) | bytes[at]
		key.append(word)
		end -= 4
	if key.is_empty():
		key.append(0)
	_init_by_array(key)


func _init_genrand(value: int) -> void:
	_state.resize(_N)
	_state[0] = value & _MASK
	for at in range(1, _N):
		var previous := _state[at - 1]
		_state[at] = (1812433253 * (previous ^ (previous >> 30)) + at) & _MASK
	_index = _N


func _init_by_array(key: PackedInt64Array) -> void:
	_init_genrand(19650218)
	var i := 1
	var j := 0
	for _step in maxi(_N, key.size()):
		var previous := _state[i - 1]
		_state[i] = ((_state[i] ^ ((previous ^ (previous >> 30)) * 1664525)) + key[j] + j) & _MASK
		i += 1
		j += 1
		if i >= _N:
			_state[0] = _state[_N - 1]
			i = 1
		if j >= key.size():
			j = 0
	for _step in _N - 1:
		var previous := _state[i - 1]
		_state[i] = ((_state[i] ^ ((previous ^ (previous >> 30)) * 1566083941)) - i) & _MASK
		i += 1
		if i >= _N:
			_state[0] = _state[_N - 1]
			i = 1
	_state[0] = 0x80000000
	_index = _N


func _next() -> int:
	if _index >= _N:
		for at in _N:
			var y := (_state[at] & _UPPER) | (_state[(at + 1) % _N] & _LOWER)
			var value := _state[(at + _M) % _N] ^ (y >> 1)
			if y & 1:
				value ^= _MATRIX_A
			_state[at] = value
		_index = 0
	var y := _state[_index]
	_index += 1
	y ^= y >> 11
	y ^= (y << 7) & 0x9d2c5680
	y ^= (y << 15) & 0xefc60000
	y ^= y >> 18
	return y & _MASK


static func _bit_length(value: int) -> int:
	var bits := 0
	while value > 0:
		bits += 1
		value >>= 1
	return bits
