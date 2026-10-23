class_name KnightMoves
extends RefCounted
## Animation, damage, movement and permitted follow-ups share this exact timeline.
const MOVES={
 "light1":{"wind":.30,"hits":[.31,.49],"length":.96,"dodge":.62,"chain":.66,"damage":220.0,"stance":14.0,"cost":20.0,"travel":.38,"drive":[.15,.48],"side":1.0},
 "light2":{"wind":.34,"hits":[.35,.54],"length":1.04,"dodge":.68,"chain":.72,"damage":235.0,"stance":16.0,"cost":21.0,"travel":.42,"drive":[.18,.53],"side":-1.0},
 "light3":{"wind":.42,"hits":[.43,.65],"length":1.22,"dodge":.88,"chain":1.22,"damage":280.0,"stance":22.0,"cost":24.0,"travel":.50,"drive":[.23,.64],"side":1.0},
 "heavy":{"wind":.64,"hits":[.66,.87],"length":1.42,"dodge":1.07,"chain":1.18,"damage":400.0,"stance":32.0,"cost":34.0,"travel":.52,"drive":[.42,.86],"side":1.0},
 "counter":{"wind":.40,"hits":[.42,.64],"length":1.24,"dodge":.96,"chain":1.10,"damage":390.0,"stance":44.0,"cost":28.0,"travel":.32,"drive":[.20,.63],"side":-1.0},
 "roll_attack":{"wind":.21,"hits":[.22,.38],"length":.82,"dodge":.58,"chain":.64,"damage":205.0,"stance":12.0,"cost":18.0,"travel":.30,"drive":[.10,.37],"side":-1.0},
 "jump_attack":{"wind":.32,"hits":[.34,.54],"length":1.12,"dodge":.82,"chain":1.02,"damage":380.0,"stance":38.0,"cost":32.0,"travel":.14,"drive":[.20,.53],"side":1.0}
}

static func key(action:String,combo:=0) -> String:
	return "light%d"%(clampi(combo,0,2)+1) if action=="light" else ("heavy" if action=="charged" else action)

static func data(action:String,combo:=0) -> Dictionary:
	return MOVES[key(action,combo)]

static func is_attack(action:String) -> bool:
	return action in ["light","light1","light2","light3","heavy","charged","counter","roll_attack","jump_attack"]

static func active(action:String,combo:int,time:float) -> bool:
	var m:Dictionary=data(action,combo)
	return time>=float(m.hits[0]) and time<float(m.hits[1])
