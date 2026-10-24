class_name KnightMotion
extends RefCounted
## Authored kinetic chain: rear foot -> pelvis -> chest -> arms -> blade.
## Hand/weapon vectors live in the CHEST frame; IK cannot cancel the body turn.
## Damage and controller timing remain in KnightMoves.
const READY_HAND=Vector3(-.29,-.14,.15)
const DEFAULT={
 "height":[.94,.90,.89,.90,.91,.94,.94],
 "lean":[.08,.07,.04,.20,.24,.10,.08],
 "bank":[0,-.025,-.045,.045,.055,.008,0],
 "root_x":[0,-.030,-.050,.045,.065,.010,0],
 "root_z":[0,-.025,-.045,.055,.065,.012,0],
 "hand_x":[-.29,-.32,-.34,-.08,.035,-.24,-.29],
 "hand_y":[-.14,-.01,.045,-.06,-.13,-.10,-.14],
 "hand_z":[.15,.13,.10,.38,.34,.20,.15],
 "free_x":[.24,.27,.28,.25,.23,.24,.24],
 "free_y":[-.13,.015,.045,-.02,-.13,-.13,-.13],
 "free_z":[.18,.27,.30,-.01,-.13,.14,.18],
 "blade_yaw":[-.14,-.55,-.70,.30,.70,-.11,-.14],
 "blade_pitch":[-.76,.10,.16,-.06,-.28,-.70,-.76],
 "wrist_roll":[0,-.12,-.18,.06,.18,.02,0],
 "rear_yaw":[0,-.08,-.12,.26,.36,.05,0],
 "lead_yaw":[0,.015,.04,.14,.19,.02,0],
 "rear_heel":[0,.025,.06,.30,.24,.025,0],
 "lead_heel":[0,0,0,.025,.035,0,0]
}
const PROFILES={
 "light1":{
  "pelvis_yaw":[0,-.14,-.37,.36,.45,.055,0],
  "chest_yaw":[0,-.28,-.74,.53,.79,.10,0],
  "step":.31,"step_side":.025,"lead":"l"},
 "light2":{
  "pelvis_yaw":[0,.16,.39,-.37,-.47,-.05,0],
  "chest_yaw":[0,.31,.77,-.55,-.82,-.10,0],
  "bank":[0,.02,.045,-.035,-.06,-.01,0],
  "root_x":[0,.035,.05,-.045,-.065,-.008,0],
  "hand_x":[-.29,-.06,.065,-.31,-.36,-.29,-.29],
  "hand_y":[-.14,.045,.095,-.03,-.12,-.11,-.14],
  "hand_z":[.15,.25,.30,.36,.24,.17,.15],
  "blade_yaw":[-.14,.44,.65,-.28,-.69,-.11,-.14],
  "blade_pitch":[-.76,.25,.34,.05,-.17,-.70,-.76],
  "wrist_roll":[0,.10,.16,-.04,-.20,-.025,0],
  "free_z":[.18,.01,-.08,.22,.31,.19,.18],
  "rear_yaw":[0,.07,.10,-.27,-.34,-.045,0],
  "lead_yaw":[0,-.02,-.04,-.15,-.20,-.02,0],
  "step":.32,"step_side":.03,"lead":"r"},
 "light4":{
  "pelvis_yaw":[0,-.17,-.44,.43,.52,.065,0],
  "chest_yaw":[0,-.34,-.79,.62,.91,.12,0],
  "height":[.94,.90,.88,.85,.86,.93,.94],
  "lean":[.08,-.015,-.07,.27,.35,.11,.08],
  "hand_x":[-.29,-.30,-.29,-.10,.015,-.24,-.29],
  "hand_y":[-.14,.18,.30,.015,-.16,-.10,-.14],
  "hand_z":[.15,.10,.045,.44,.34,.20,.15],
  "blade_yaw":[-.14,-.48,-.67,.22,.66,-.11,-.14],
  "blade_pitch":[-.76,.42,.64,-.13,-.58,-.72,-.76],
  "root_z":[0,-.035,-.055,.085,.10,.02,0],
  "rear_heel":[0,.025,.07,.37,.27,.02,0],
  "step":.37,"step_side":.025,"lead":"l"},
 "light3":{
  "pelvis_yaw":[0,.10,.18,-.06,-.10,-.02,0],
  "chest_yaw":[0,.18,.27,-.10,-.16,-.02,0],
  "lean":[.08,-.03,-.05,.28,.30,.11,.08],
  "hand_x":[-.29,-.20,-.17,-.12,-.11,-.24,-.29],
  "hand_y":[-.14,-.02,.015,-.025,-.04,-.10,-.14],
  "hand_z":[.15,.04,-.02,.51,.47,.20,.15],
  "blade_yaw":[-.14,.08,.035,.015,.025,-.11,-.14],
  "blade_pitch":[-.76,.05,.025,-.015,-.025,-.68,-.76],
  "root_z":[0,-.045,-.065,.105,.12,.02,0],
  "rear_heel":[0,.025,.05,.35,.26,.025,0],
  "free_z":[.18,.25,.27,-.08,-.14,.14,.18],
  "step":.43,"step_side":.025,"lead":"l"},
 "heavy":{
  "pelvis_yaw":[0,-.13,-.28,.30,.38,.05,0],
  "chest_yaw":[0,-.19,-.34,.16,.29,.035,0],
  "height":[.94,.89,.87,.84,.86,.93,.94],
  "lean":[.08,-.09,-.17,.28,.42,.13,.08],
  "bank":[0,-.015,-.025,.015,.035,.005,0],
  "root_x":[0,-.025,-.035,.025,.045,.005,0],
  "root_z":[0,-.045,-.065,.09,.11,.018,0],
  "hand_x":[-.29,-.21,-.12,-.12,-.045,-.25,-.29],
  "hand_y":[-.14,.24,.43,.075,-.13,-.09,-.14],
  "hand_z":[.15,.08,.025,.46,.37,.20,.15],
  "blade_yaw":[-.14,-.12,-.04,.04,.08,-.11,-.14],
  "blade_pitch":[-.76,.87,1.16,-.24,-.94,-.73,-.76],
  "wrist_roll":[0,-.07,-.13,.015,.06,.01,0],
  "rear_heel":[0,.025,.055,.39,.31,.015,0],
  "step":.39,"step_side":.04,"lead":"l"},
 "heavy2":{
  "pelvis_yaw":[0,.19,.45,-.42,-.54,-.07,0],
  "chest_yaw":[0,.30,.78,-.65,-.89,-.11,0],
  "height":[.94,.90,.87,.86,.90,.94,.94],
  "lean":[.08,.05,.02,.23,.26,.10,.08],
  "bank":[0,.03,.07,-.07,-.08,-.01,0],
  "root_x":[0,.03,.055,-.04,-.06,-.008,0],
  "hand_x":[-.29,-.04,.08,-.25,-.38,-.27,-.29],
  "hand_y":[-.14,.10,.16,.02,-.09,-.11,-.14],
  "hand_z":[.15,.20,.25,.44,.27,.18,.15],
  "blade_yaw":[-.14,.48,.70,-.36,-.78,-.12,-.14],
  "blade_pitch":[-.76,.15,.22,-.06,-.30,-.71,-.76],
  "wrist_roll":[0,.12,.19,-.08,-.23,-.02,0],
  "rear_yaw":[0,.08,.13,-.28,-.36,-.05,0],
  "lead_yaw":[0,-.025,-.05,-.17,-.22,-.025,0],
  "rear_heel":[0,.025,.06,.35,.28,.025,0],
  "step":.34,"step_side":.04,"lead":"r"},
 "running_attack":{
  "pelvis_yaw":[0,-.10,-.19,.18,.24,.035,0],
  "chest_yaw":[0,-.18,-.31,.24,.35,.045,0],
  "height":[.94,.91,.89,.88,.91,.94,.94],
  "lean":[.08,.18,.25,.34,.26,.11,.08],
  "hand_x":[-.29,-.26,-.22,-.11,-.05,-.24,-.29],
  "hand_y":[-.14,-.01,.05,-.02,-.05,-.10,-.14],
  "hand_z":[.15,.05,.0,.50,.47,.20,.15],
  "blade_yaw":[-.14,-.14,-.10,.02,.06,-.11,-.14],
  "blade_pitch":[-.76,.03,.045,.01,-.03,-.68,-.76],
  "root_z":[0,-.015,-.025,.095,.10,.02,0],
  "step":.45,"step_side":.03,"lead":"l"},
 "backstep_attack":{
  "pelvis_yaw":[0,.13,.29,-.27,-.34,-.04,0],
  "chest_yaw":[0,.24,.48,-.43,-.61,-.07,0],
  "height":[.94,.89,.87,.91,.93,.94,.94],
  "lean":[.08,.13,.19,.28,.22,.10,.08],
  "hand_x":[-.29,-.08,.02,-.27,-.35,-.27,-.29],
  "hand_y":[-.14,-.18,-.23,.12,.22,-.10,-.14],
  "hand_z":[.15,.20,.28,.43,.32,.18,.15],
  "blade_yaw":[-.14,.34,.54,-.26,-.57,-.11,-.14],
  "blade_pitch":[-.76,-.30,-.28,.38,.52,-.70,-.76],
  "root_x":[0,.02,.04,-.03,-.05,-.005,0],
  "step":.38,"step_side":.025,"lead":"r"},
 "counter":{
  "pelvis_yaw":[0,.13,.34,-.36,-.42,-.05,0],
  "chest_yaw":[0,.29,.66,-.48,-.70,-.07,0],
  "root_x":[0,.025,.04,-.035,-.05,-.005,0],
  "bank":[0,.02,.035,-.035,-.045,-.005,0],
  "hand_x":[-.29,-.08,.045,-.20,-.32,-.27,-.29],
  "hand_y":[-.14,.15,.28,.015,-.14,-.11,-.14],
  "hand_z":[.15,.22,.27,.43,.30,.18,.15],
  "blade_yaw":[-.14,.30,.43,-.19,-.50,-.12,-.14],
  "blade_pitch":[-.76,.49,.70,-.16,-.63,-.73,-.76],
  "step":.25,"step_side":.035,"lead":"r"},
 "roll_attack":{
  "pelvis_yaw":[0,.12,.26,-.28,-.35,-.04,0],
  "chest_yaw":[0,.21,.47,-.44,-.64,-.07,0],
  "height":[.94,.87,.85,.86,.90,.94,.94],
  "lean":[.08,.22,.27,.28,.20,.09,.08],
  "root_x":[0,.015,.025,-.025,-.045,-.005,0],
  "hand_x":[-.29,-.13,.015,-.28,-.36,-.27,-.29],
  "hand_y":[-.14,-.18,-.20,-.09,-.12,-.12,-.14],
  "hand_z":[.15,.26,.33,.41,.30,.18,.15],
  "blade_yaw":[-.14,.45,.68,-.28,-.65,-.12,-.14],
  "blade_pitch":[-.76,-.16,-.08,.12,-.05,-.69,-.76],
  "step":.25,"step_side":.02,"lead":"r"},
 "jump_attack":{
  "pelvis_yaw":[0,-.12,-.24,.25,.32,.04,0],
  "chest_yaw":[0,-.16,-.31,.17,.26,.035,0],
  "height":[.94,.88,.85,.81,.86,.93,.94],
  "lean":[.08,-.06,-.14,.35,.43,.13,.08],
  "root_z":[0,-.015,-.02,.05,.075,.01,0],
  "hand_x":[-.29,-.20,-.11,-.12,-.05,-.25,-.29],
  "hand_y":[-.14,.27,.44,.11,-.13,-.10,-.14],
  "hand_z":[.15,.09,.025,.44,.35,.20,.15],
  "blade_yaw":[-.14,-.10,-.025,.015,.08,-.11,-.14],
  "blade_pitch":[-.76,.89,1.18,-.19,-.96,-.73,-.76],
  "step":.23,"step_side":.025,"lead":"l"}
}
static var _tracks:Dictionary={}

static func _compile(id:String) -> Dictionary:
	var move:Dictionary=KnightMoves.MOVES[id];var profile:Dictionary=PROFILES[id]
	var wind:float=move.wind;var h0:float=move.hits[0];var h1:float=move.hits[1];var length:float=move.length
	var times:=[0.0,wind*.42,wind*.96,lerpf(h0,h1,.60),h1+.075,length-.105,length]
	var hip_times:=[0.0,wind*.28,wind*.73,lerpf(h0,h1,.30),h1+.04,length-.13,length]
	var hand_times:=[0.0,wind*.46,wind,lerpf(h0,h1,.74),h1+.10,length-.08,length]
	var blade_times:=[0.0,wind*.50,wind*1.015,lerpf(h0,h1,.90),h1+.11,length-.075,length]
	var tracks:={}
	for key in DEFAULT:
		var values:Array=profile.get(key,DEFAULT[key]);var points:=[]
		var channel_times:Array=times
		if key.begins_with("hand_") or key.begins_with("free_"):channel_times=hand_times
		elif key.begins_with("blade_") or key=="wrist_roll":channel_times=blade_times
		elif key in ["root_x","root_z","height","rear_yaw","rear_heel"]:channel_times=hip_times
		for i in values.size():points.append([channel_times[i],values[i]])
		tracks[key]=points
	for key in ["pelvis_yaw","chest_yaw"]:
		var points:=[];var values:Array=profile[key]
		for i in values.size():points.append([(hip_times if key=="pelvis_yaw" else times)[i],values[i]])
		tracks[key]=points
	_tracks[id]=tracks
	return tracks

static func sample(id:String,time:float) -> Dictionary:
	var tracks:Dictionary=_tracks.get(id,{})
	if tracks.is_empty():tracks=_compile(id)
	var result:={}
	for key in tracks:result[key]=BeastMotion.curve(tracks[key],time)
	var profile:Dictionary=PROFILES[id];var move:Dictionary=KnightMoves.MOVES[id]
	result.hand=Vector3(result.hand_x,result.hand_y,result.hand_z)
	result.free=Vector3(result.free_x,result.free_y,result.free_z)
	result.sword=Vector3(sin(result.blade_yaw)*cos(result.blade_pitch),sin(result.blade_pitch),cos(result.blade_yaw)*cos(result.blade_pitch))
	result.twist=result.chest_yaw
	result.lead=profile.lead;result.step=profile.step;result.step_side=profile.step_side
	result.step_load=smoothstep(float(move.wind)*.10,float(move.wind)*.90,time)
	result.settle=smoothstep(float(move.hits[1])+.12,float(move.length),time)
	result.head_yaw=float(result.chest_yaw)*.13
	return result
