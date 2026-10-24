class_name BeastMoves
extends RefCounted
## One timing source for the controller, blade animation and rehearsal tools.
## Strike windows stay readable; finish marks the end of committed follow-through.

const ATTACKS={
 "sweep":{"length":1.48,"finish":1.08,"hits":[[.61,.86,340.0]],"reach":4.3,"weight":9,"cooldown":2.6,"recover":.24,"track":.42,"turn":2.5,"step":.42},
 "combo":{"length":2.88,"finish":2.57,"hits":[[.61,.86,300.0],[1.35,1.60,320.0],[2.11,2.34,410.0]],"reach":4.7,"weight":6,"cooldown":7.0,"recover":.38,"track":.40,"turn":2.4,"step":.72},
 "drag":{"length":1.70,"finish":1.22,"hits":[[.65,.96,350.0]],"reach":4.5,"weight":6,"cooldown":4.2,"recover":.30,"low":true,"track":.43,"turn":2.3,"step":.54},
 "overhead":{"length":2.05,"finish":1.70,"hits":[[1.00,1.19,520.0]],"reach":4.4,"weight":7,"cooldown":5.5,"recover":.55,"track":.70,"turn":2.2,"step":.45},
 "lunge":{"length":1.65,"finish":1.18,"hits":[[.65,.93,440.0]],"reach":15.0,"min_range":4.6,"weight":9,"cooldown":4.6,"recover":.38,"track":.38,"turn":2.5,"drive":[.43,.93],"parry":true},
 "leap":{"length":2.75,"finish":2.12,"hits":[[1.42,1.65,500.0]],"reach":17.0,"min_range":4.8,"weight":8,"cooldown":8.0,"recover":.52,"track":.24,"turn":2.6,"flight":[.28,1.58,3.2],"parry":true},
 "air_blades":{"length":3.20,"finish":3.04,"hits":[],"reach":26.0,"min_range":5.5,"weight":7,"cooldown":10.0,"recover":.46,"phase":2,"track":.24,"turn":2.5,"flight":[.28,2.85,3.8],"shots":[.74,1.44,2.14]},
 "spin":{"length":2.05,"finish":1.69,"hits":[[.55,.80,340.0],[1.20,1.42,370.0]],"reach":5.0,"weight":6,"cooldown":7.2,"recover":.36,"phase":2,"track":.34,"turn":2.5,"step":.36,"parry":true},
 "death_storm":{"length":3.35,"finish":3.00,"hits":[],"reach":6.2,"weight":8,"cooldown":13.0,"recover":.65,"phase":2,"track":.65,"turn":1.8,"pulses":[1.55,1.90,2.25,2.60]},
 "backhand":{"length":1.16,"finish":.88,"hits":[[.43,.63,285.0]],"reach":4.0,"weight":7,"cooldown":3.2,"recover":.25,"track":.28,"turn":2.8,"step":.30,"wide":true},
 "paw_strike":{"length":1.24,"finish":.94,"hits":[[.45,.64,230.0]],"reach":3.2,"weight":5,"cooldown":5.0,"recover":.32,"track":.27,"turn":2.8,"step":.26,"hit_source":"paw","wide":true},
 "evade_cut":{"length":1.43,"finish":1.09,"hits":[[.52,.74,285.0]],"reach":3.7,"weight":5,"cooldown":5.4,"recover":.28,"track":.25,"turn":2.6,"retreat":[.27,.83,1.05,.65],"wide":true}
}

static func finish(id:String) -> float:
	return float(ATTACKS[id].get("finish",ATTACKS[id].length))

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
