#!/usr/bin/env python3
"""Add a compact, recorded-texture CC0 beast voice to the existing battle bank.

Run after build_battle_audio.py, using numpy/scipy and ffmpeg. All downloads and
intermediates stay in this checkout. Supplied source recordings are not bundled;
only edited, layered derivatives are included in the public game.
"""
from pathlib import Path
import hashlib, json, math, os, subprocess, wave
import numpy as np
from scipy import signal

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT/'.runtime/beast-voice'
OUT = ROOT/'assets/audio/battle'
SR = 32000
SYNTH = 'Original procedural synthesis and arrangement (CC0-1.0)'
SOURCES = {
    'dog-growl': {
        'title': 'my dog growling.wav', 'author': 'akiuee',
        'page': 'https://freesound.org/people/akiuee/sounds/337167/',
        'url': 'https://cdn.freesound.org/previews/337/337167_4868216-hq.mp3',
        'sha256': '3ea5a1fc1aad11202b93b412dd1b29a61f82e7bfb1e99a51496b4c433e67d604',
    },
    'lion-roar': {
        'title': 'S01-09_Short lion roars.wav', 'author': 'craigsmith',
        'page': 'https://freesound.org/people/craigsmith/sounds/675443/',
        'url': 'https://cdn.freesound.org/previews/675/675443_2524442-hq.mp3',
        'sha256': '3544ac6209113f892c2b2fe5406567c16dfa7eca636d99a0bbc0d8bc4e9e56c2',
    },
    'werewolf-breath': {
        'title': 'Werewolf breathing and sniffing', 'author': 'kd_jack',
        'page': 'https://freesound.org/people/kd_jack/sounds/261464/',
        'url': 'https://cdn.freesound.org/previews/261/261464_1560047-hq.mp3',
        'sha256': '60a8ff3ec5ebeb7d9e35453b4948905a8593f3a5d1951eb127bfb7133fbb45f8',
    },
}
EVENTS = {
    'beast_breath': {'durations': [.76, .86, .98], 'priority': 0, 'cooldown_s': 2.8, 'gain_db': 2, 'pitch': [.97, 1.04]},
    'beast_growl': {'durations': [1.16, 1.28, 1.38], 'priority': 1, 'cooldown_s': 2.4, 'gain_db': 0, 'pitch': [.95, 1.04]},
    'beast_attack': {'durations': [.48, .56, .64], 'priority': 2, 'cooldown_s': .28, 'gain_db': 1, 'pitch': [.96, 1.06]},
    'beast_pain': {'durations': [.43, .51, .59], 'priority': 3, 'cooldown_s': .30, 'gain_db': 0, 'pitch': [.97, 1.06]},
    'beast_roar': {'durations': [1.96, 2.18], 'priority': 4, 'cooldown_s': 2.0, 'gain_db': 1, 'pitch': [.97, 1.02]},
    'beast_death': {'durations': [2.40], 'priority': 5, 'cooldown_s': 0.0, 'gain_db': 1, 'pitch': [.98, 1.01]},
}
CACHE = {}
USED = set()

def run(args, data=None):
    env = dict(os.environ, TMPDIR=str(WORK), PYTHONDONTWRITEBYTECODE='1')
    p = subprocess.run(args, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    if p.returncode: raise RuntimeError(p.stderr.decode(errors='replace'))
    return p.stdout

def db(x): return 20*math.log10(max(float(x), 1e-12))
def hp(x, hz): return signal.sosfilt(signal.butter(3, hz, btype='highpass', fs=SR, output='sos'), x)
def lp(x, hz): return signal.sosfilt(signal.butter(4, hz, fs=SR, output='sos'), x)
def band(x, lo, hi): return lp(hp(x, lo), hi)
def rms(x): return np.sqrt(np.mean(x*x))

def fade(x, attack=.016, release=.08):
    x = x.copy(); a = min(len(x)//3, int(attack*SR)); b = min(len(x)//2, int(release*SR))
    if a: x[:a] *= np.sin(np.linspace(0, np.pi/2, a))**2
    if b: x[-b:] *= np.cos(np.linspace(0, np.pi/2, b))**2
    return x

def source(key):
    if key not in CACHE:
        spec = SOURCES[key]; path = WORK/'source'/(key+'.mp3'); path.parent.mkdir(parents=True, exist_ok=True)
        if not path.is_file(): run(['curl', '-fsSL', '--retry', '2', '--max-time', '80', spec['url'], '-o', str(path)])
        assert hashlib.sha256(path.read_bytes()).hexdigest() == spec['sha256'], key+' source changed'
        CACHE[key] = np.frombuffer(run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-i', str(path), '-ac', '1', '-ar', str(SR), '-f', 'f32le', 'pipe:1']), dtype='<f4').astype(float)
    USED.add(key); return CACHE[key]

def texture(key, start, duration, rate=1.0, end_rate=None):
    raw = source(key); count = int(round(duration*SR))
    rates = np.linspace(rate, rate if end_rate is None else end_rate, count)
    positions = start*SR+np.cumsum(rates)
    x = np.interp(positions, np.arange(len(raw)), raw, left=0, right=0)
    x = hp(x, 65); x = lp(x, 5900)
    # Work from recorded irregular phonation. No synthetic layer replaces it.
    x /= max(rms(x), .012)
    return fade(x*.16, .014, .07)

def throat(duration, seed, f0=64):
    rng = np.random.default_rng(seed); t = np.arange(round(duration*SR))/SR
    jitter = lp(rng.normal(size=len(t)), 26); jitter /= max(np.max(abs(jitter)), 1e-9)
    f = f0*(1-.18*t/duration)*(1+.025*jitter+.025*np.sin(2*np.pi*5.3*t))
    phase = np.cumsum(f)*2*np.pi/SR
    # Low chest resonance supplements recorded harmonics and is deliberately quiet.
    x = sum(np.sin(phase*k+.19*k)*(.38/k**1.1) for k in range(1, 9))
    return x*signal.windows.tukey(len(x), .25)*.09

def make(event, i, duration):
    t = np.arange(round(duration*SR))/SR; phase = t/duration
    if event == 'beast_breath':
        x = texture('werewolf-breath', [1.04,4.60,7.48][i], duration, [.88,.80,.84][i])
        x += texture('dog-growl', [1.12,6.08,10.65][i], duration, .71)*.09
        x = band(x, 150, 4100)
        envelope = np.sin(np.pi*phase)**.65
        x *= envelope
    elif event == 'beast_growl':
        x = texture('dog-growl', [3.05,4.62,9.50][i], duration, [.65,.69,.63][i])
        x += texture('lion-roar', .05 if i!=1 else 1.40, duration, .62, .53)*.23
        x += throat(duration, 510+i, 61+i*3)
        x *= (1-np.exp(-t*24))*np.clip(1-phase*.25,0,1)
    elif event == 'beast_attack':
        x = texture('lion-roar', [.13,1.43,.24][i], duration, [.83,.76,.92][i], .67)
        x += texture('dog-growl', [3.08,9.73,12.25][i], duration, .78)*.48
        x += texture('werewolf-breath', [13.85,21.05,23.63][i], duration, .82)*.13
        x += throat(duration, 540+i, 78+i*3)
        x *= np.exp(-phase*1.1)*(1-np.exp(-t*85))
    elif event == 'beast_pain':
        x = texture('lion-roar', [.22,1.51,.32][i], duration, [.96,.87,1.02][i], [.82,.74,.88][i])
        x += texture('dog-growl', [3.12,9.85,12.30][i], duration, .90)*.30
        x += throat(duration, 560+i, 91+i*4)*.45
        x *= np.exp(-phase*1.15)*(1-np.exp(-t*100))
    elif event == 'beast_roar':
        x = texture('lion-roar', .03 if i==0 else .14, duration, [.90,.85][i], [.68,.63][i])*.86
        x += texture('dog-growl', [3.0,9.55][i], duration, [.61,.57][i])*.44
        x += texture('werewolf-breath', [17.70,23.45][i], duration, .75)*.12
        x += throat(duration, 580+i, 65+i*4)
        x *= (1-np.exp(-t*32))*(1-.22*phase)
    else:
        x = texture('lion-roar', 1.30, duration, .78, .35)*.70
        x += texture('dog-growl', 9.45, duration, .72, .40)*.36
        x += texture('werewolf-breath', 23.50, duration, .77, .61)*.18
        x += throat(duration, 599, 59)*.75
        x *= (1-np.exp(-t*48))*np.exp(-phase*2.2)
    # Retain recognisable throat and breath detail on small phone speakers.
    x = hp(x, 55)+band(x, 280, 2400)*.45
    x = lp(x, 6100)
    x = fade(x, .025 if event=='beast_breath' else .010, .13 if duration>1 else .075)
    x -= x.mean()
    peak_db = -8 if event=='beast_breath' else (-4 if event in ['beast_roar','beast_pain'] else -4.5)
    x /= max(np.max(abs(x)),1e-9)
    x = np.tanh(x*1.20)/np.tanh(1.20)
    x *= 10**(peak_db/20)
    return fade(x, .007, .035)

def metadata(path, x):
    over = signal.resample_poly(x, 4, 1)
    return {'file':path.name,'loop':False,'duration_s':round(len(x)/SR,6),'sample_rate':SR,'channels':1,
            'encoding':'pcm_s16le','bytes':path.stat().st_size,'peak_dbfs':round(db(np.max(abs(x))),3),
            'rms_dbfs':round(db(rms(x)),3),'dc_dbfs':round(db(abs(x.mean())),3),
            'true_peak_4x_dbfs':round(db(np.max(abs(over))),3),
            'presence_220_3600_dbfs':round(db(rms(band(x,220,3600))),3),
            'sources':[SYNTH]+[SOURCES[k]['title']+' by '+SOURCES[k]['author']+' (CC0-1.0): '+SOURCES[k]['page'] for k in sorted(USED)]}

def main():
    WORK.mkdir(parents=True, exist_ok=True)
    bank_path=OUT/'bank.json'; bank=json.loads(bank_path.read_text()); prior={k:dict(v) for k,v in bank['files'].items() if not k.startswith('beast_')}
    report=[];demo=[]
    for event,spec in EVENTS.items():
        clips=[]
        for i,duration in enumerate(spec['durations']):
            USED.clear();key=event+'_%02d'%(i+1);path=OUT/(key+'.wav');x=make(event,i,duration)
            pcm=np.round(np.clip(x,-1,1)*32767).astype('<i2')
            with wave.open(str(path),'wb') as out:
                out.setnchannels(1);out.setsampwidth(2);out.setframerate(SR);out.writeframes(pcm.tobytes())
            x=pcm.astype(float)/32768;entry=metadata(path,x)
            assert np.isfinite(x).all() and entry['true_peak_4x_dbfs'] < -3.0
            assert entry['presence_220_3600_dbfs'] > -33, (key,entry)
            assert abs(x[0])<.001 and abs(x[-1])<.001
            bank['files'][key]=entry;clips.append(key);report.append({'id':key,**entry})
            if i==0:demo += [x,np.zeros(round(SR*.38))]
        bank['events'][event]={'clips':clips,'gain_db':spec['gain_db'],'pitch':spec['pitch'],'group':'beast_voice','priority':spec['priority'],'cooldown_s':spec['cooldown_s']}
    assert all(bank['files'][key]==value for key,value in prior.items())
    bank_path.write_text(json.dumps(bank,indent=2)+'\n')
    total=sum(r['bytes'] for r in report);assert total<2*1024*1024
    review=ROOT/'web/review/beast-voice.mp3';review.parent.mkdir(exist_ok=True)
    run(['ffmpeg','-hide_banner','-loglevel','error','-y','-f','f32le','-ar',str(SR),'-ac','1','-i','pipe:0','-c:a','libmp3lame','-b:a','96k','-map_metadata','-1',str(review)],np.concatenate(demo).astype('<f4').tobytes())
    license_path=ROOT/'LICENSES/Battle-Audio-Sources.txt';license_text=license_path.read_bytes().decode('utf-8')
    license_text=license_text.replace('Air movement, creature growls, resonators, ambience, and the 80 BPM','Air movement, original synthetic creature growls, resonators, ambience, and the 80 BPM')
    marker='\nADDITIONAL BEAST VOCAL BANK — RECORDED TEXTURES (2026-10-24)\n'
    license_text=license_text.split(marker)[0]+marker
    license_text+='All three primary upload pages identify their recordings as Creative Commons 0 (CC0 1.0).\nLicense: https://creativecommons.org/publicdomain/zero/1.0/\nPublished high-quality MP3 previews were downloaded, not the login-only original WAV/AIFF.\nDerivatives use trims, pitch/time changes, filtering, recorded layers and original low throat harmonics.\nNo extracted game audio and no dialogue. Original processing/synthesis is dedicated to CC0 1.0.\n\n'
    for key,spec in SOURCES.items():
        license_text+=spec['title']+' — '+spec['author']+'\nPrimary page: '+spec['page']+'\nDownloaded preview: '+spec['url']+'\nSHA-256: '+spec['sha256']+'\nLicense stated by uploader: CC0 1.0\n\n'
    license_text+='PROVENANCE BY ADDITIONAL FINAL FILE:\n'
    for entry in report:license_text+=entry['file']+'\n'+''.join('  '+s+'\n' for s in entry['sources'])
    license_path.write_bytes(license_text.encode('utf-8'))
    result={'new_files':len(report),'new_bytes':total,'bank_files':len(bank['files']),'bank_events':len(bank['events']),'new_events':list(EVENTS),'demo_bytes':review.stat().st_size,'files':report}
    (ROOT/'artifacts/beast_voice_bank.json').write_text(json.dumps(result,indent=2))
    print(json.dumps({k:v for k,v in result.items() if k!='files'},indent=2))
    for r in report:print(r['id'],'duration',r['duration_s'],'RMS',r['rms_dbfs'],'true peak',r['true_peak_4x_dbfs'],'presence',r['presence_220_3600_dbfs'])

if __name__=='__main__':main()
