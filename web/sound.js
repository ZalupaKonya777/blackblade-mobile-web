// Local audio with a playback session and gesture-owned output on iPhone.
// WebKit's default Web Audio session is ambient, which obeys Ring/Silent even
// when the context says "running". Request playback before opening the output.
const dbGain = db => Math.pow(10, db / 20);
class BattleSound {
  context = null; bank = null; buffers = new Map(); readyBuffers = new Map(); pending = new Map();
  decoded = new Set(); lastClip = new Map(); active = new Set(); loops = new Map(); counters = {};
  volume = .75; musicVolume = .5; fighting = false; phase = 1; paused = false; muted = false;
  needsGesture = true; unlocked = false; sessionType = 'unavailable'; lastError = '';
  mediaOutput = null; mediaDestination = null; mediaPlaying = false; outputRoute = 'web-audio';
  warmups = 0; rebuilds = 0; lastCreated = 0; lastProbe = -Infinity; frozen = false;
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
  buffer(id) {
    if (this.readyBuffers.has(id)) return Promise.resolve(this.readyBuffers.get(id));
    if (!this.buffers.has(id)) {
      const context = this.context;
      const pending = this.bytes(id).then(data => context.decodeAudioData(data.slice(0)))
        .then(buffer => { this.decoded.add(id); this.readyBuffers.set(id, buffer); return buffer; })
        .catch(error => { if (this.buffers.get(id) === pending) this.buffers.delete(id); throw error; });
      this.buffers.set(id, pending);
    }
    return this.buffers.get(id);
  }
  async decodeAll() {
    await Promise.all(Object.keys(this.bank.files).map(id => this.buffer(id)));
    this.syncLoops(); this.notify();
  }
  playbackSession() {
    try {
      if (navigator.audioSession) {
        navigator.audioSession.type = 'playback';
        this.sessionType = navigator.audioSession.type;
        if (!this.sessionObserved) {
          this.sessionObserved = true;
          navigator.audioSession.addEventListener?.('statechange', () => {
            if (navigator.audioSession.state === 'interrupted') this.needsGesture = true;
            else if (!document.hidden && this.unlocked && !this.muted) this.resumeOutput();
            this.notify();
          });
        }
        return this.sessionType === 'playback';
      }
    } catch (error) { this.lastError = 'audio-session: ' + error.name; }
    this.sessionType = 'unavailable'; return false;
  }
  createOutput() {
    const Context = window.AudioContext || window.webkitAudioContext;
    if (!Context) { this.lastError = 'Web Audio unavailable'; this.notify(); return; }
    const c = this.context = new Context({ latencyHint: 'interactive' });
    this.lastCreated = performance.now(); this.musicEpoch = c.currentTime; this.outputRoute = 'web-audio';
    this.master = c.createGain();
    const compressor = c.createDynamicsCompressor();
    compressor.threshold.value = -9; compressor.knee.value = 10; compressor.ratio.value = 4;
    compressor.attack.value = .004; compressor.release.value = .18;
    this.analyser = c.createAnalyser(); this.analyser.fftSize = 2048;
    this.master.connect(compressor).connect(this.analyser).connect(c.destination);
    this.sfx = c.createGain(); this.sfx.connect(this.master);
    this.music = c.createGain(); this.music.connect(this.master);
    this.ambient = c.createGain(); this.ambient.gain.value = .32; this.ambient.connect(this.master);
    this.reverb = c.createConvolver();
    const impulse = c.createBuffer(2, Math.round(c.sampleRate * 1.65), c.sampleRate);
    let seed = 428;
    for (let ch = 0; ch < 2; ch++) {
      const out = impulse.getChannelData(ch);
      for (let i = 0; i < out.length; i++) {
        seed = (Math.imul(seed, 1664525) + 1013904223) | 0;
        out[i] = ((seed >>> 0) / 2147483648 - 1) * Math.pow(1 - i / out.length, 3.8) * .27;
      }
    }
    this.reverb.buffer = impulse; const wet = c.createGain(); wet.gain.value = .19;
    this.reverb.connect(wet).connect(this.master); this.settings(this.volume, this.musicVolume);
    c.addEventListener('statechange', () => {
      if (c !== this.context) return;
      if (c.state !== 'running' && !document.hidden) this.needsGesture = true;
      this.notify();
    });
    this.lastClock = c.currentTime; this.stillClock = 0; this.frozen = false;
    if (!this.watchdog) this.watchdog = setInterval(() => {
      const current = this.context;
      if (!current || document.hidden || this.muted || !this.unlocked) return;
      if (current.state === 'running' && current.currentTime <= this.lastClock) this.stillClock++;
      else this.stillClock = 0;
      this.lastClock = current.currentTime;
      if (this.stillClock >= 3) { this.frozen = true; this.needsGesture = true; }
      this.notify();
    }, 1000);
    if (this.bank) this.decodeAll().catch(error => { this.lastError = 'decode: ' + error.name; this.notify(); });
  }
  useMediaOutput() {
    if (this.mediaOutput || !this.context) return;
    // This is a genuine media OUTPUT, not a silent element and not a media
    // source fed back into a Web Audio destination. The full controlled mix
    // goes through a live media track to the element's playback endpoint.
    // Modern Safari uses the direct low-latency playback AudioSession path;
    // this path is for older browsers and an explicit output repair.
    const c = this.context; const audio = new Audio();
    audio.hidden = true; audio.tabIndex = -1; audio.dataset.gameAudioOutput = '';
    audio.setAttribute('aria-hidden', 'true'); audio.setAttribute('playsinline', '');
    audio.setAttribute('webkit-playsinline', ''); document.body.appendChild(audio);
    try {
      const destination = c.createMediaStreamDestination();
      audio.srcObject = destination.stream;
      this.analyser.disconnect(); this.analyser.connect(destination);
      this.mediaOutput = audio; this.mediaDestination = destination; this.outputRoute = 'media-stream';
      audio.addEventListener('pause', () => {
        if (audio !== this.mediaOutput || !audio.paused) return;
        this.mediaPlaying = false;
        // iOS can stop the media endpoint while the Web Audio clock keeps
        // advancing. Expose that interruption instead of trusting the clock.
        if (!document.hidden && !this.muted && this.volume > .0001) this.needsGesture = true;
        this.notify();
      });
      audio.addEventListener('error', () => {
        if (audio !== this.mediaOutput) return;
        this.mediaPlaying = false; this.needsGesture = true; this.lastError = 'media-output';
        this.directOutputFallback(); this.notify();
      });
    } catch (error) {
      this.lastError = 'media-route: ' + error.name;
      audio.srcObject = null; audio.remove(); this.directOutputFallback();
    }
  }
  directOutputFallback() {
    if (!this.context) return;
    this.analyser.disconnect(); this.analyser.connect(this.context.destination);
    this.outputRoute = 'web-audio-fallback';
  }

  playMediaOutput() {
    const audio = this.mediaOutput;
    if (!audio || document.hidden || this.muted || this.volume <= .0001) return Promise.resolve();
    if (!audio.paused && this.mediaPlaying) return Promise.resolve();
    if (this.mediaPlayRequest?.audio === audio) return this.mediaPlayRequest.promise;
    // play() is called directly from the gesture, never after an await.
    const request = { audio, promise: null };
    const started = audio.play();
    request.promise = Promise.resolve(started).then(() => {
      if (audio !== this.mediaOutput || this.mediaPlayRequest !== request) return;
      this.mediaPlaying = !audio.paused;
      if (this.mediaPlaying && this.mediaDestination && this.outputRoute !== 'media-stream') { this.analyser.disconnect(); this.analyser.connect(this.mediaDestination); this.outputRoute = 'media-stream'; }
      this.needsGesture = this.context?.state !== 'running' || this.frozen || !this.mediaPlaying;
      if (this.lastError.startsWith('media-play:')) this.lastError = '';
      this.syncLoops(); this.notify();
    }).catch(error => {
      if (audio !== this.mediaOutput || this.mediaPlayRequest !== request) return;
      this.mediaPlaying = false;
      // pause(), source replacement and page background intentionally abort play.
      if (error.name !== 'AbortError' && !document.hidden && !this.muted && this.volume > .0001) {
        this.needsGesture = true; this.lastError = 'media-play: ' + error.name; this.directOutputFallback();
      }
      this.syncLoops(); this.notify();
    }).finally(() => { if (this.mediaPlayRequest === request) this.mediaPlayRequest = null; });
    this.mediaPlayRequest = request; return request.promise;
  }

  warmOutput() {
    const c = this.context; if (!c) return;
    // Creating/resuming a context alone does not open every iOS output route.
    // An actual one-frame source is started in the same trusted gesture.
    const source = c.createBufferSource(); source.buffer = c.createBuffer(1, 1, c.sampleRate);
    source.connect(c.destination); source.onended = () => source.disconnect(); source.start(0);
    this.warmups++;
  }
  resumeOutput() {
    const c = this.context; if (!c || document.hidden) return;
    this.playbackSession(); this.playMediaOutput();
    const resumed = c.state !== 'running' ? c.resume() : Promise.resolve();
    resumed.then(() => {
      if (c !== this.context) return;
      this.needsGesture = c.state !== 'running' || this.frozen || (this.outputRoute === 'media-stream' && !this.mediaPlaying);
      this.syncLoops(); this.notify();
    }).catch(error => { this.needsGesture = true; this.lastError = 'resume: ' + error.name; this.notify(); });
  }
  unlock(options = {}) {
    if (this.muted && !options.test && !options.repair) return;
    const hasPlayback = this.playbackSession();
    if (this.context?.state === 'closed' || ((options.repair || this.frozen) && this.context && performance.now() - this.lastCreated > 1200)) this.resetOutput();
    if (!this.context) this.createOutput();
    if (!this.context) return;
    this.unlocked = true;
    if (!hasPlayback || options.repair) this.useMediaOutput();
    this.warmOutput(); this.resumeOutput(); this.syncLoops();
    if (options.test) {
      if (this.mediaOutput && !this.mediaPlaying) this.playMediaOutput().then(() => this.testOutput());
      else this.testOutput();
    }
  }
  resetOutput() {
    const old = this.context;
    for (const source of this.active) { try { source.stop(); } catch {} }
    this.active.clear();
    for (const loop of this.loops.values()) if (loop) { try { loop.source.stop(); } catch {} }
    this.loops.clear(); this.buffers.clear();
    if (this.mediaOutput) { this.mediaOutput.pause(); this.mediaOutput.srcObject = null; this.mediaOutput.remove(); }
    if (this.mediaDestination) for (const track of this.mediaDestination.stream.getTracks()) track.stop();
    this.mediaOutput = null; this.mediaDestination = null; this.mediaPlaying = false; this.mediaPlayRequest = null;
    this.context = null; this.frozen = false; this.needsGesture = true; this.rebuilds++;
    old?.close().catch(() => {});
  }
  testOutput() {
    const c = this.context; if (!c || performance.now() - this.lastProbe < 150) return;
    this.lastProbe = performance.now(); this.probes = (this.probes || 0) + 1;
    window.dispatchEvent(new CustomEvent('blackbladeaudioprobe'));
    for (const [offset, frequency] of [[.04, 523.25], [.21, 783.99]]) {
      const tone = c.createOscillator(); const gain = c.createGain(); const at = c.currentTime + offset;
      tone.type = 'sine'; tone.frequency.value = frequency;
      gain.gain.setValueAtTime(0, at); gain.gain.linearRampToValueAtTime(.16, at + .015);
      gain.gain.exponentialRampToValueAtTime(.0001, at + .16);
      tone.connect(gain).connect(this.master); tone.start(at); tone.stop(at + .18);
      tone.onended = () => { tone.disconnect(); gain.disconnect(); };
    }
    this.notify();
  }
  background() {
    this.mediaPlayRequest = null; this.mediaOutput?.pause(); this.mediaPlaying = false;
    if (this.context && this.context.state !== 'closed') this.context.suspend().catch(() => {});
    this.needsGesture = true; this.notify();
  }
  foreground() {
    if (this.unlocked && !this.muted) this.resumeOutput();
  }
  settings(volume, music) {
    const previousVolume = this.volume;
    this.volume = volume; this.musicVolume = music; if (!this.context) return;
    const t = this.context.currentTime;
    this.master.gain.setTargetAtTime(this.muted ? 0 : volume, t, .025);
    this.music.gain.setTargetAtTime(music * .72 * (this.paused ? .48 : 1), t, .18);
    this.sfx.gain.setTargetAtTime(this.paused ? .25 : 1, t, .05);
    if (volume <= .0001) { this.mediaPlayRequest = null; this.mediaOutput?.pause(); this.mediaPlaying = false; }
    else if (previousVolume <= .0001 && this.unlocked && !this.muted) this.playMediaOutput();
    this.notify();
  }
  mute(value) {
    this.muted = value;
    if (value) { this.mediaPlayRequest = null; this.mediaOutput?.pause(); this.mediaPlaying = false; }
    else this.resumeOutput();
    this.settings(this.volume, this.musicVolume); this.syncLoops(); this.notify();
  }
  listener(x, y, z, fx, fy, fz, ux, uy, uz) {
    if (!this.context) return; const l = this.context.listener;
    if (l.positionX) {
      for (const [key, value] of Object.entries({positionX:x,positionY:y,positionZ:z,
        forwardX:fx,forwardY:fy,forwardZ:fz,upX:ux,upY:uy,upZ:uz})) l[key].value = value;
    } else { l.setPosition(x,y,z); l.setOrientation(fx,fy,fz,ux,uy,uz); }
  }
  play(name,x=0,y=0,z=0,db=-6,pitch=1) {
    if (!this.context || !this.bank || this.context.state !== 'running') return;
    name = ({swing:'knight_swing',roll:'body_contact'})[name] || name;
    const event = this.bank.events[name]; if (!event) return;
    const clips = event.clips; let index = Math.floor(Math.random() * clips.length);
    if (clips.length > 1 && clips[index] === this.lastClip.get(name)) index = (index + 1) % clips.length;
    const id = clips[index]; this.lastClip.set(name,id); const requestTime = this.context.currentTime;
    const start = buffer => {
      const c = this.context; if (c.state !== 'running' || c.currentTime - requestTime > .12) return;
      if (this.active.size >= 28) { const oldest = this.active.values().next().value; this.active.delete(oldest); oldest.stop(); }
      const source = c.createBufferSource(); source.buffer = buffer;
      const range = event.pitch || [1,1];
      source.playbackRate.value = Math.max(.45,Math.min(1.8,pitch*(range[0]+Math.random()*(range[1]-range[0]))));
      const gain = c.createGain(); gain.gain.value = dbGain(db+(event.gain_db||0));
      const panner = c.createPanner(); panner.panningModel = 'equalpower'; panner.distanceModel = 'inverse';
      panner.refDistance=5; panner.maxDistance=42; panner.rolloffFactor=.65;
      if(panner.positionX){panner.positionX.value=x;panner.positionY.value=y;panner.positionZ.value=z;} else panner.setPosition(x,y,z);
      source.connect(gain).connect(panner); panner.connect(this.sfx); panner.connect(this.reverb);
      source.onended = () => { this.active.delete(source); source.disconnect(); gain.disconnect(); panner.disconnect(); };
      this.active.add(source); this.counters[name]=(this.counters[name]||0)+1; source.start();
    };
    if(this.readyBuffers.has(id))start(this.readyBuffers.get(id));
    else this.buffer(id).then(start).catch(error=>console.warn('Audio event',name,error));
  }
  fight(on) { this.fighting=on; this.syncLoops(); }
  state(phase,paused) { this.phase=phase; this.paused=paused; this.settings(this.volume,this.musicVolume); this.syncLoops(); }
  syncLoops() {
    if(!this.context||!this.bank||this.context.state!=='running')return;
    const c=this.context;
    for(const key of ['ambient','music_1','music_2']) {
      if(this.loops.has(key))continue; this.loops.set(key,null);
      this.buffer(this.bank.loops[key]).then(buffer=> {
        if(c!==this.context)return;
        const source=c.createBufferSource(); source.buffer=buffer; source.loop=true;
        source.loopStart=Math.max(0,buffer.duration-this.bank.files[this.bank.loops[key]].duration_s)>.02?.03453125:0;
        source.loopEnd=source.loopStart+this.bank.files[this.bank.loops[key]].duration_s;
        const gain=c.createGain(); gain.gain.value=0; source.connect(gain).connect(key==='ambient'?this.ambient:this.music);
        source.start(0,source.loopStart+(c.currentTime-this.musicEpoch)%(source.loopEnd-source.loopStart));
        this.loops.set(key,{source,gain}); this.syncLoops();
      }).catch(error=>{if(c===this.context)this.loops.delete(key);console.warn('Audio loop',error);});
    }
    for(const [key,loop] of this.loops)if(loop) {
      const target=key==='ambient'?1:(this.fighting&&key==='music_'+this.phase?1:0);
      loop.gain.gain.setTargetAtTime(target,c.currentTime,key==='ambient'?.18:.65);
    }
  }
  notify() {
    const key=[this.context?.state,this.muted,this.volume===0,this.needsGesture,this.frozen,this.mediaPlaying].join(':');
    if(key===this.noticeKey)return;this.noticeKey=key;
    window.dispatchEvent(new CustomEvent('blackbladeaudiochange'));
  }
  get diagnostics() {
    let rms=0;
    if(this.analyser){const a=new Float32Array(this.analyser.fftSize);this.analyser.getFloatTimeDomainData(a);rms=Math.sqrt(a.reduce((s,v)=>s+v*v,0)/a.length);}
    return {state:this.context?.state||'locked',files:this.bank?Object.keys(this.bank.files).length:0,
      decoded:this.decoded.size,active:this.active.size,events:{...this.counters},rms,phase:this.phase,muted:this.muted,
      needsGesture:this.needsGesture,sessionType:this.sessionType,mediaPlaying:this.mediaPlaying,
      mediaTime:this.mediaOutput?.currentTime||0,outputRoute:this.outputRoute,standalone:!!(navigator.standalone||window.matchMedia?.('(display-mode: standalone)').matches),warmups:this.warmups,rebuilds:this.rebuilds,probes:this.probes||0,lastError:this.lastError,frozen:this.frozen};
  }
}
window.BlackbladeSound=new BattleSound();
document.addEventListener('visibilitychange',()=>document.hidden?window.BlackbladeSound.background():window.BlackbladeSound.foreground());
window.addEventListener('pagehide',()=>window.BlackbladeSound.background());
window.addEventListener('pageshow',()=>window.BlackbladeSound.foreground());
