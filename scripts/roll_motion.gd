class_name RollMotion
extends RefCounted
## Authored shoulder roll. Time is normalized; distance comes from the same
## continuous curve at every physics rate, rather than a frame-dependent impulse.

const TIMES = [0.0, .075, .17, .29, .43, .57, .72, .86, 1.0]
const TRAVEL = [0.0, .030, .158, .370, .620, .810, .940, .989, 1.0]
const SPIN = [0.0, .12, .68, 1.80, 3.10, 4.40, 5.62, 6.16, TAU]
const HIP = [.95, .78, .64, .60, .56, .55, .62, .80, .95]
const TUCK = [0.0, .38, .88, 1.0, 1.0, .90, .62, .20, 0.0]
const BANK = [0.0, -.06, -.22, -.30, -.18, .08, .13, .05, 0.0]

static func _slope(values: Array, i: int) -> float:
	if i == 0 or i == TIMES.size()-1: return 0.0
	var a: float = (values[i]-values[i-1])/(TIMES[i]-TIMES[i-1])
	var b: float = (values[i+1]-values[i])/(TIMES[i+1]-TIMES[i])
	if a*b <= 0.0: return 0.0
	return 2.0*a*b/(a+b)

static func curve(values: Array, phase: float) -> float:
	var f := clampf(phase, 0.0, 1.0)
	for i in range(1, TIMES.size()):
		if f > TIMES[i]: continue
		var span: float = TIMES[i]-TIMES[i-1]
		var u: float = (f-TIMES[i-1])/span
		var u2 := u*u
		var u3 := u2*u
		return (2*u3-3*u2+1)*values[i-1]+(u3-2*u2+u)*span*_slope(values,i-1)+(-2*u3+3*u2)*values[i]+(u3-u2)*span*_slope(values,i)
	return float(values.back())

static func travel(phase: float) -> float:
	return curve(TRAVEL, phase)

static func sample(phase: float) -> Dictionary:
	return {"spin":curve(SPIN,phase), "height":curve(HIP,phase), "tuck":curve(TUCK,phase), "bank":curve(BANK,phase)}
