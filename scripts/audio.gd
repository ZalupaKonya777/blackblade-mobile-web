extends Node

var streams:={}
var pool:Array=[]
var index:=0
var music:AudioStreamPlayer
var ambience:AudioStreamPlayer
var current_music:=""

func _ready() -> void:
	G.audio=self
	for name in ["swing","roll","step","hit","guard","parry","slam","flask","roar","death","win","menu","projectile","music","ambient","armor_takeoff","body_contact","boot_land"]:
		streams[name]=load("res://assets/audio/"+name+".ogg")
	for i in 18:
		var p:=AudioStreamPlayer3D.new();p.max_distance=45;p.unit_size=5;p.attenuation_model=AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE;add_child(p);pool.append(p)
	music=AudioStreamPlayer.new();music.volume_db=-12;add_child(music)
	ambience=AudioStreamPlayer.new();ambience.stream=streams.ambient;(ambience.stream as AudioStreamOggVorbis).loop=true;ambience.volume_db=-14;add_child(ambience);ambience.play()
	G.changed.connect(settings_changed);settings_changed()

func settings_changed() -> void:
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(.0001,float(G.settings.volume))))
	music.volume_db=linear_to_db(maxf(.0001,float(G.settings.music)))-9

func play(name:String,pos:Vector3,db:float=-6,pitch:float=1) -> void:
	if not streams.has(name):return
	var p:AudioStreamPlayer3D=pool[index];index=(index+1)%pool.size();p.stream=streams[name];p.global_position=pos;p.volume_db=db;p.pitch_scale=pitch*randf_range(.97,1.03);p.play()

func fight(on:bool) -> void:
	if on:
		music.stream=streams.music;(music.stream as AudioStreamOggVorbis).loop=true;music.play()
	else:music.stop()
