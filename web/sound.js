// Local samples, sample accurate hits, and a shared clock for both music phases.
const dbGain = db => Math.pow(10, db / 20);
class BattleSound {
  context = null; bank = null; buffers = new Map(); readyBuffers = new Map(); pending = new Map();
  decoded = new Set(); lastClip = new Map(); active = new Set(); loops = new Map(); counters = {};
  volume = .75; musicVolume = .5; fighting = false; phase = 1; paused = false; muted = false;
  async prepare() {
    this.bank ??= await fetch('audio/bank.json').then(r => {
      if (!r.ok) throw new Error('Не удалось загрузить звуки храма.'); return r.json();
    });
    await Promise.all(Object.keys(this.bank.files).map(id => this.bytes(id)));
    if (this.context) await this.decodeAll();
  }
  bytes(id) {
    if (!this.pending.has(id)) this.pending.set(id, fetch('audio/' + this.bank.files[id].file)
      .then(r => { if (!r.ok) throw new Error('Audio asset unavailable: ' + id); return r.arrayBuffer(); }));
    return this.pending.get(id);
  }
  async buffer(id) {
    if (!this.buffers.has(id)) this.buffers.set(id, this.bytes(id)
      .then(data => this.context.decodeAudioData(data.slice(0)))
      .then(buffer => { this.decoded.add(id); this.readyBuffers.set(id,buffer); return buffer; }));
    return this.buffers.get(id);
  }
  async decodeAll() { await Promise.all(Object.keys(this.bank.files).map(id => this.buffer(id))); this.syncLoops(); }
  unlock() {
    if (!this.context) {
      const Context = window.AudioContext || window.webkitAudioContext; if (!Context) return;
      const c = this.context = new Context({ latencyHint: 'interactive' });
      this.master = c.createGain();
      const compressor = c.createDynamicsCompressor();
      compressor.threshold.value=-9;compressor.knee.value=10;compressor.ratio.value=4;
      compressor.attack.value=.004;compressor.release.value=.18;
      this.analyser=c.createAnalyser();this.analyser.fftSize=2048;
      this.master.connect(compressor).connect(this.analyser).connect(c.destination);
      this.sfx=c.createGain();this.sfx.connect(this.master);
      this.music=c.createGain();this.music.connect(this.master);
      this.ambient=c.createGain();this.ambient.gain.value=.32;this.ambient.connect(this.master);
      this.reverb=c.createConvolver();
      const impulse=c.createBuffer(2,Math.round(c.sampleRate*1.65),c.sampleRate);
      let seed=428;
      for(let ch=0;ch<2;ch++){
        const out=impulse.getChannelData(ch);
        for(let i=0;i<out.length;i++){
          seed=(Math.imul(seed,1664525)+1013904223)|0;
          out[i]=((seed>>>0)/2147483648-1)*Math.pow(1-i/out.length,3.8)*.27;
        }
      }
      this.reverb.buffer=impulse;const wet=c.createGain();wet.gain.value=.19;
      this.reverb.connect(wet).connect(this.master);this.settings(this.volume,this.musicVolume);
      if(this.bank)this.decodeAll().catch(error=>console.warn('Audio decode',error));
    }
    // Synchronous gesture call, also resumes an interrupted iPhone audio session.
    if(this.context.state!=='running')this.context.resume().catch(()=>{});
    this.syncLoops();
  }
  settings(volume,music){
    this.volume=volume;this.musicVolume=music;if(!this.context)return;
    const t=this.context.currentTime;
    this.master.gain.setTargetAtTime(this.muted?0:volume,t,.025);
    this.music.gain.setTargetAtTime(music*.72*(this.paused?.48:1),t,.18);
    this.sfx.gain.setTargetAtTime(this.paused?.25:1,t,.05);
  }
  mute(value){this.muted=value;this.settings(this.volume,this.musicVolume);}
  listener(x,y,z,fx,fy,fz,ux,uy,uz){
    if(!this.context)return;const l=this.context.listener;
    if(l.positionX){
      for(const [key,value] of Object.entries({positionX:x,positionY:y,positionZ:z,
        forwardX:fx,forwardY:fy,forwardZ:fz,upX:ux,upY:uy,upZ:uz}))l[key].value=value;
    }else{l.setPosition(x,y,z);l.setOrientation(fx,fy,fz,ux,uy,uz);}
  }
  play(name,x=0,y=0,z=0,db=-6,pitch=1){
    if(!this.context||!this.bank||this.context.state!=='running')return;
    name=({swing:'knight_swing',roll:'body_contact'})[name]||name;
    const event=this.bank.events[name];if(!event)return;
    const clips=event.clips;let index=Math.floor(Math.random()*clips.length);
    if(clips.length>1&&clips[index]===this.lastClip.get(name))index=(index+1)%clips.length;
    const id=clips[index];this.lastClip.set(name,id);const requestTime=this.context.currentTime;
    const start=buffer=>{
      const c=this.context;if(c.state!=='running'||c.currentTime-requestTime>.12)return;
      if(this.active.size>=28){const oldest=this.active.values().next().value;this.active.delete(oldest);oldest.stop();}
      const source=c.createBufferSource();source.buffer=buffer;
      const range=event.pitch||[1,1];
      source.playbackRate.value=Math.max(.45,Math.min(1.8,pitch*(range[0]+Math.random()*(range[1]-range[0]))));
      const gain=c.createGain();gain.gain.value=dbGain(db+(event.gain_db||0));
      const panner=c.createPanner();panner.panningModel='equalpower';panner.distanceModel='inverse';
      panner.refDistance=5;panner.maxDistance=42;panner.rolloffFactor=.65;
      if(panner.positionX){panner.positionX.value=x;panner.positionY.value=y;panner.positionZ.value=z;}
      else panner.setPosition(x,y,z);
      source.connect(gain).connect(panner);panner.connect(this.sfx);panner.connect(this.reverb);
      source.onended=()=>{this.active.delete(source);source.disconnect();gain.disconnect();panner.disconnect();};
      this.active.add(source);this.counters[name]=(this.counters[name]||0)+1;source.start();
    };
    // Native combat may run several physics ticks before a slow GPU yields.
    // Starting a cached source now avoids a delayed Promise microtask and keeps
    // impacts audible even while that frame is rendering.
    if(this.readyBuffers.has(id))start(this.readyBuffers.get(id));
    else this.buffer(id).then(start).catch(error=>console.warn('Audio event',name,error));
  }
  fight(on){this.fighting=on;this.syncLoops();}
  state(phase,paused){this.phase=phase;this.paused=paused;this.settings(this.volume,this.musicVolume);this.syncLoops();}
  syncLoops(){
    if(!this.context||!this.bank||this.context.state!=='running')return;
    const c=this.context;
    for(const key of ['ambient','music_1','music_2']){
      if(this.loops.has(key))continue;this.loops.set(key,null);
      this.buffer(this.bank.loops[key]).then(buffer=>{
        const source=c.createBufferSource();source.buffer=buffer;source.loop=true;source.loopStart=Math.max(0,buffer.duration-this.bank.files[this.bank.loops[key]].duration_s)>.02?.03453125:0;source.loopEnd=source.loopStart+this.bank.files[this.bank.loops[key]].duration_s;
        const gain=c.createGain();gain.gain.value=0;source.connect(gain).connect(key==='ambient'?this.ambient:this.music);
        this.musicEpoch??=c.currentTime;source.start(0,source.loopStart+(c.currentTime-this.musicEpoch)%(source.loopEnd-source.loopStart));
        this.loops.set(key,{source,gain});this.syncLoops();
      }).catch(error=>{this.loops.delete(key);console.warn('Audio loop',error);});
    }
    for(const [key,loop] of this.loops)if(loop){
      const target=key==='ambient'?1:(this.fighting&&key==='music_'+this.phase?1:0);
      loop.gain.gain.setTargetAtTime(target,c.currentTime,key==='ambient'?.5:.65);
    }
  }
  get diagnostics(){
    let rms=0;if(this.analyser){const a=new Float32Array(this.analyser.fftSize);this.analyser.getFloatTimeDomainData(a);rms=Math.sqrt(a.reduce((s,v)=>s+v*v,0)/a.length);}
    return {state:this.context?.state||'locked',files:this.bank?Object.keys(this.bank.files).length:0,
      decoded:this.decoded.size,active:this.active.size,events:{...this.counters},rms,phase:this.phase,muted:this.muted};
  }
}
window.BlackbladeSound=new BattleSound();
document.addEventListener('visibilitychange',()=>{
  if(document.hidden&&window.BlackbladeSound.context)window.BlackbladeSound.context.suspend().catch(()=>{});
});
