extends Node
## WebAudio supplies reliable spatial sound on the mobile web export.
var streams:={}
var bank:Dictionary={}
var pool:Array=[]
var index:=0
var music:Array=[]
var ambience:AudioStreamPlayer
var web_audio:JavaScriptObject
var listener_t:=0.0
var fighting:=false

func _ready() -> void:
	G.audio=self;process_mode=Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web"):
		web_audio=JavaScriptBridge.get_interface("BlackbladeSound")
	else:
		bank=JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/battle/bank.json"))
		for id in bank.files:streams[id]=load("res://assets/audio/battle/"+bank.files[id].file)
		for i in 24:
			var p:=AudioStreamPlayer3D.new();p.max_distance=42;p.unit_size=5;p.attenuation_filter_cutoff_hz=12000
			add_child(p);pool.append(p)
		for id in ["music_1","music_2"]:
			var p:=AudioStreamPlayer.new();p.stream=streams[bank.loops[id]];p.stream.loop=true;p.volume_db=-80
			add_child(p);music.append(p);p.play()
		ambience=AudioStreamPlayer.new();ambience.stream=streams[bank.loops.ambient];ambience.stream.loop=true
		ambience.volume_db=-10;add_child(ambience);ambience.play()
	G.changed.connect(settings_changed);settings_changed()

func settings_changed() -> void:
	if web_audio:web_audio.settings(float(G.settings.volume),float(G.settings.music))
	else:AudioServer.set_bus_volume_db(0,linear_to_db(maxf(.0001,float(G.settings.volume))))

func _process(dt:float) -> void:
	listener_t+=dt
	if listener_t<.05:return
	listener_t=0
	if web_audio and G.camera:
		var cam:Camera3D=G.camera.cam;var pos:=cam.global_position;var f:Vector3=-cam.global_basis.z;var u:Vector3=cam.global_basis.y
		web_audio.listener(pos.x,pos.y,pos.z,f.x,f.y,f.z,u.x,u.y,u.z)
		web_audio.state(int(G.boss.phase) if G.boss else 1,get_tree().paused)
	elif not music.is_empty():
		for i in 2:
			var audible:=fighting and G.boss and int(G.boss.phase)==i+1
			var target:=linear_to_db(maxf(.0001,float(G.settings.music)))-3 if audible else -80.0
			music[i].volume_db=lerpf(music[i].volume_db,target,.12)

func play(name:String,pos:Vector3,db:float=-6,pitch:float=1) -> void:
	if web_audio:
		web_audio.play(name,pos.x,pos.y,pos.z,db,pitch);return
	if name=="swing":name="knight_swing"
	if not bank.events.has(name):return
	var event:Dictionary=bank.events[name];var clips:Array=event.clips
	var p:AudioStreamPlayer3D=pool[index];index=(index+1)%pool.size()
	p.stream=streams[clips.pick_random()];p.global_position=pos;p.volume_db=db+float(event.gain_db)
	p.pitch_scale=pitch*randf_range(float(event.pitch[0]),float(event.pitch[1]));p.play()

func fight(on:bool) -> void:
	fighting=on
	if web_audio:web_audio.fight(on)
