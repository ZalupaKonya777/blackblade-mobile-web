class_name BeastMoves
extends RefCounted
## One timing source for the controller, blade animation and rehearsal tools.
## The nine established attacks keep their identities and strike windows.

const ATTACKS={
 "sweep":{"length":1.48,"hits":[[.61,.86,340.0]],"reach":4.0,"weight":9,"cooldown":3.0,"recover":.48,"track":.42,"turn":2.5,"step":.34},
 "combo":{"length":2.88,"hits":[[.61,.86,300.0],[1.35,1.60,320.0],[2.11,2.34,410.0]],"reach":4.7,"weight":7,"cooldown":8.0,"recover":.65,"track":.40,"turn":2.4,"step":.62},
 "drag":{"length":1.70,"hits":[[.65,.96,350.0]],"reach":4.5,"weight":6,"cooldown":5.0,"recover":.60,"low":true,"track":.43,"turn":2.3,"step":.48},
 "overhead":{"length":2.05,"hits":[[1.00,1.19,520.0]],"reach":4.4,"weight":7,"cooldown":6.0,"recover":.90,"track":.70,"turn":2.2,"step":.45},
 "lunge":{"length":1.65,"hits":[[.65,.93,440.0]],"reach":15.0,"min_range":4.6,"weight":9,"cooldown":5.0,"recover":.70,"track":.38,"turn":2.5,"drive":[.43,.93],"parry":true},
 "leap":{"length":2.75,"hits":[[1.42,1.65,500.0]],"reach":17.0,"min_range":4.8,"weight":8,"cooldown":9.0,"recover":.80,"track":.24,"turn":2.6,"flight":[.28,1.58,3.2],"parry":true},
 "air_blades":{"length":3.20,"hits":[],"reach":26.0,"min_range":5.5,"weight":7,"cooldown":11.0,"recover":.65,"phase":2,"track":.24,"turn":2.5,"flight":[.28,2.85,3.8],"shots":[.74,1.44,2.14]},
 "spin":{"length":2.05,"hits":[[.55,.80,340.0],[1.20,1.42,370.0]],"reach":5.0,"weight":6,"cooldown":8.0,"recover":.80,"phase":2,"track":.34,"turn":2.5,"step":.30,"parry":true},
 "death_storm":{"length":3.35,"hits":[],"reach":6.2,"weight":8,"cooldown":14.0,"recover":1.05,"phase":2,"track":.65,"turn":1.8,"pulses":[1.55,1.90,2.25,2.60]}
}

static func active(id:String,time:float,early:float=0.0) -> bool:
	if not ATTACKS.has(id):return false
	for h in ATTACKS[id].hits:
		if time>=h[0]-early and time<h[1]:return true
	return false

static func smooth_motion(f:float) -> float:
	var u:=clampf(f,0,1)
	return u*u*u*(10.0+u*(-15.0+u*6.0))

static func drive_progress(f:float) -> float:
	# Accelerating launch, sustained drive, then a short braking contact.
	var u:=clampf(f,0,1)
	return smooth_motion(u)
