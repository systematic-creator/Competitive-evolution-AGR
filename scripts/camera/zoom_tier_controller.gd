class_name ZoomTierController
extends RefCounted
## Maps camera distance (meters) onto the four semantic zoom tiers.

const ORBIT_ENTER: float = 1.2
const REGION_ENTER: float = 0.9
const RTS_ENTER: float = 0.55
const RTS_MIN: float = 0.20


static func tier_for_distance(distance: float) -> GameState.ZoomTier:
	if distance >= REGION_ENTER:
		return GameState.ZoomTier.ORBIT
	if distance >= RTS_ENTER:
		return GameState.ZoomTier.REGION
	return GameState.ZoomTier.RTS


static func transition_progress(distance: float) -> float:
	return clampf(inverse_lerp(ORBIT_ENTER, REGION_ENTER, distance), 0.0, 1.0)
