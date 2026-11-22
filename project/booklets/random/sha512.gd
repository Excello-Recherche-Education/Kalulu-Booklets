class_name Sha512
extends RefCounted
## SHA-512 (FIPS 180-4), which Godot's HashingContext does not offer and
## Python's random number generator needs to turn a string into its seed.
##
## GDScript integers are signed 64-bit and wrap around, which is addition
## modulo 2^64; only the right shifts need care, since >> keeps the sign.

const _K_HIGH: Array[int] = [
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
	0xca273ece, 0xd186b8c7, 0xeada7dd6, 0xf57d4f7f, 0x06f067aa, 0x0a637dc5, 0x113f9804, 0x1b710b35,
	0x28db77f5, 0x32caab7b, 0x3c9ebe0a, 0x431d67c4, 0x4cc5d4be, 0x597f299c, 0x5fcb6fab, 0x6c44198c,
]
const _K_LOW: Array[int] = [
	0xd728ae22, 0x23ef65cd, 0xec4d3b2f, 0x8189dbbc, 0xf348b538, 0xb605d019, 0xaf194f9b, 0xda6d8118,
	0xa3030242, 0x45706fbe, 0x4ee4b28c, 0xd5ffb4e2, 0xf27b896f, 0x3b1696b1, 0x25c71235, 0xcf692694,
	0x9ef14ad2, 0x384f25e3, 0x8b8cd5b5, 0x77ac9c65, 0x592b0275, 0x6ea6e483, 0xbd41fbd4, 0x831153b5,
	0xee66dfab, 0x2db43210, 0x98fb213f, 0xbeef0ee4, 0x3da88fc2, 0x930aa725, 0xe003826f, 0x0a0e6e70,
	0x46d22ffc, 0x5c26c926, 0x5ac42aed, 0x9d95b3df, 0x8baf63de, 0x3c77b2a8, 0x47edaee6, 0x1482353b,
	0x4cf10364, 0xbc423001, 0xd0f89791, 0x0654be30, 0xd6ef5218, 0x5565a910, 0x5771202a, 0x32bbd1b8,
	0xb8d2d0c8, 0x5141ab53, 0xdf8eeb99, 0xe19b48a8, 0xc5c95a63, 0xe3418acb, 0x7763e373, 0xd6b2b8a3,
	0x5defb2fc, 0x43172f60, 0xa1f0ab72, 0x1a6439ec, 0x23631e28, 0xde82bde9, 0xb2c67915, 0xe372532b,
	0xea26619c, 0x21c0c207, 0xcde0eb1e, 0xee6ed178, 0x72176fba, 0xa2c898a6, 0xbef90dae, 0x131c471b,
	0x23047d84, 0x40c72493, 0x15c9bebc, 0x9c100d4c, 0xcb3e42b6, 0xfc657e2a, 0x3ad6faec, 0x4a475817,
]
const _H_HIGH: Array[int] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
const _H_LOW: Array[int] = [0xf3bcc908, 0x84caa73b, 0xfe94f82b, 0x5f1d36f1, 0xade682d1, 0x2b3e6c1f, 0xfb41bd6b, 0x137e2179]

static var _k: PackedInt64Array = PackedInt64Array()


## The 64-byte digest of ``message``.
static func digest(message: PackedByteArray) -> PackedByteArray:
	if _k.is_empty():
		_k = _join(_K_HIGH, _K_LOW)
	var hash := _join(_H_HIGH, _H_LOW)
	var padded := message.duplicate()
	padded.append(0x80)
	while padded.size() % 128 != 112:
		padded.append(0)
	# The length in bits as 128 bits, big-endian; a message is never 2^61 bytes.
	for index in 8:
		padded.append(0)
	var bits := message.size() * 8
	for shift in range(56, -1, -8):
		padded.append((bits >> shift) & 0xff)

	var words := PackedInt64Array()
	words.resize(80)
	for block in range(0, padded.size(), 128):
		for index in 16:
			var value := 0
			for byte in 8:
				value = (value << 8) | padded[block + index * 8 + byte]
			words[index] = value
		for index in range(16, 80):
			var w15 := words[index - 15]
			var w2 := words[index - 2]
			var s0 := _rotr(w15, 1) ^ _rotr(w15, 8) ^ _shr(w15, 7)
			var s1 := _rotr(w2, 19) ^ _rotr(w2, 61) ^ _shr(w2, 6)
			words[index] = words[index - 16] + s0 + words[index - 7] + s1
		var a := hash[0]
		var b := hash[1]
		var c := hash[2]
		var d := hash[3]
		var e := hash[4]
		var f := hash[5]
		var g := hash[6]
		var h := hash[7]
		for index in 80:
			var sum1 := _rotr(e, 14) ^ _rotr(e, 18) ^ _rotr(e, 41)
			var choose := (e & f) ^ (~e & g)
			var temp1 := h + sum1 + choose + _k[index] + words[index]
			var sum0 := _rotr(a, 28) ^ _rotr(a, 34) ^ _rotr(a, 39)
			var majority := (a & b) ^ (a & c) ^ (b & c)
			var temp2 := sum0 + majority
			h = g
			g = f
			f = e
			e = d + temp1
			d = c
			c = b
			b = a
			a = temp1 + temp2
		hash[0] += a
		hash[1] += b
		hash[2] += c
		hash[3] += d
		hash[4] += e
		hash[5] += f
		hash[6] += g
		hash[7] += h

	var out := PackedByteArray()
	for value in hash:
		for shift in range(56, -1, -8):
			out.append((value >> shift) & 0xff)
	return out


static func _join(high: Array[int], low: Array[int]) -> PackedInt64Array:
	var joined := PackedInt64Array()
	for index in high.size():
		joined.append((high[index] << 32) | low[index])
	return joined


## Logical right shift, 0 < count < 64.
static func _shr(value: int, count: int) -> int:
	return (value >> count) & ((1 << (64 - count)) - 1)


static func _rotr(value: int, count: int) -> int:
	return _shr(value, count) | (value << (64 - count))
