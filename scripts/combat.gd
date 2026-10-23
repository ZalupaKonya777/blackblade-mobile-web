class_name CombatMath
extends RefCounted

static func point_segment(p: Vector3,a: Vector3,b: Vector3) -> Vector3:
	var d:=b-a
	return a+d*clampf((p-a).dot(d)/maxf(d.length_squared(),0.00001),0,1)

static func segment_distance(a: Vector3,b: Vector3,c: Vector3,d: Vector3) -> float:
	var u:=b-a;var v:=d-c;var w:=a-c
	var aa:=u.dot(u);var bb:=u.dot(v);var cc:=v.dot(v);var dd:=u.dot(w);var ee:=v.dot(w)
	var den:=aa*cc-bb*bb
	var s:=clampf((bb*ee-cc*dd)/maxf(den,.000001),0,1)
	var t:=clampf((bb*s+ee)/maxf(cc,.000001),0,1)
	s=clampf((bb*t-dd)/maxf(aa,.000001),0,1)
	return (w+u*s-v*t).length()

static func blade_hits(old: Array, current: Array, target: Node3D, radius := .10) -> bool:
	var segs: Array=target.hurt_segments()
	for h in segs:
		if segment_distance(current[0],current[1],h[0],h[1])<=radius+h[2]:return true
		for i in 6:
			var f:=float(i)/5
			if segment_distance(old[0].lerp(old[1],f),current[0].lerp(current[1],f),h[0],h[1])<=radius+h[2]:return true
	return false
