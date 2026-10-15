class_name View
extends RefCounted
## Conversions between simulation space (game units, x east, y north) and the rendered world (metres, y up,
## -z north). One game unit renders as 1 cm.

const S := 0.01
const MAP_HALF_M := SimMap.HALF * S

static func to3(p: Vector2, h := 0.0) -> Vector3:
	return Vector3(p.x * S, h * S, -p.y * S)

static func to2(v: Vector3) -> Vector2:
	return Vector2(v.x / S, -v.z / S)

## Rendered facing (rotation about y) for a simulation facing angle (0 = east, counter-clockwise).
static func yaw(sim_angle: float) -> float:
	return sim_angle - PI * 0.5

## The node itself, or null once it has been freed. Effect lists hold nodes that other code may free first (a timed
## fade, a unit view going away); assigning a freed node to a typed variable is a script error that aborts the whole
## update (in a fight with Froster that error and its printout cost about 10 ms every frame).
static func live(o: Variant) -> Variant:
	return o if is_instance_valid(o) else null
