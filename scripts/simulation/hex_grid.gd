class_name HexGrid
extends RefCounted
## Axial (q, r) hex grid. Source of truth helpers for territory, borders,
## and resource areas. Flat-top orientation in the XZ plane.
## `s = -q - r` is the implied cube coordinate.

const Q_OFFSET: int = 512
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

## Distance from hex center to a vertex, in world units.
var hex_size: float = 0.0625
var origin: Vector3 = Vector3.ZERO


static func pack(hex: Vector2i) -> int:
	return ((hex.x + Q_OFFSET) << 16) | (hex.y + Q_OFFSET)


static func unpack(key: int) -> Vector2i:
	return Vector2i((key >> 16) - Q_OFFSET, (key & 0xFFFF) - Q_OFFSET)


func world_to_axial(pos: Vector3) -> Vector2i:
	var x: float = (pos.x - origin.x) / hex_size
	var z: float = (pos.z - origin.z) / hex_size
	var q: float = (2.0 / 3.0) * x
	var r: float = (-1.0 / 3.0) * x + (sqrt(3.0) / 3.0) * z
	return axial_round(q, r)


func axial_to_world(hex: Vector2i) -> Vector3:
	var q: float = float(hex.x)
	var r: float = float(hex.y)
	var x: float = hex_size * (1.5 * q)
	var z: float = hex_size * ((sqrt(3.0) * 0.5) * q + sqrt(3.0) * r)
	return origin + Vector3(x, 0.0, z)


func axial_round(fq: float, fr: float) -> Vector2i:
	var fs: float = -fq - fr
	var q: float = round(fq)
	var r: float = round(fr)
	var s: float = round(fs)
	var dq: float = abs(q - fq)
	var dr: float = abs(r - fr)
	var ds: float = abs(s - fs)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(int(q), int(r))


func neighbors(hex: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dir: Vector2i in DIRS:
		out.append(hex + dir)
	return out


func distance(a: Vector2i, b: Vector2i) -> int:
	var dq: int = a.x - b.x
	var dr: int = a.y - b.y
	return (absi(dq) + absi(dq + dr) + absi(dr)) / 2


func hexes_in_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for q: int in range(-radius, radius + 1):
		var r1: int = maxi(-radius, -q - radius)
		var r2: int = mini(radius, -q + radius)
		for r: int in range(r1, r2 + 1):
			out.append(center + Vector2i(q, r))
	return out


func corners(hex: Vector2i) -> PackedVector3Array:
	var center: Vector3 = axial_to_world(hex)
	var pts := PackedVector3Array()
	for i: int in 6:
		var angle: float = deg_to_rad(60.0 * float(i))
		pts.append(center + Vector3(hex_size * cos(angle), 0.0, hex_size * sin(angle)))
	return pts
