"""Reproducible Godot 4.3 single-thread Web export and bounded static assets.

No filesystem path outside this checkout is mutated. Original desktop sources
are never read by the build. --skip-export only rebuilds the HTML shell.
"""
from pathlib import Path
import argparse, gzip, hashlib, json, os, shutil, subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--skip-export', action='store_true')
args = parser.parse_args()
raw = ROOT / 'build/web'
raw.mkdir(parents=True, exist_ok=True)
runtime = ROOT / '.runtime'
(runtime / 'tmp').mkdir(parents=True, exist_ok=True)
env = dict(os.environ, XDG_DATA_HOME=str(runtime/'data'), XDG_CONFIG_HOME=str(runtime/'config'),
           XDG_CACHE_HOME=str(runtime/'cache'), TMPDIR=str(runtime/'tmp'), GODOT_SILENCE_ROOT_WARNING='1')
if not args.skip_export:
    # Keep generated editor state local while reusing already installed templates.
    external = Path(os.environ.get('GODOT_EXPORT_TEMPLATES',
                    str(Path(os.environ.get('XDG_DATA_HOME',str(Path.home()/'.local/share')))/'godot/export_templates')))
    local = runtime/'data/godot/export_templates/4.3.stable'
    local.mkdir(parents=True,exist_ok=True)
    for name in ['web_nothreads_debug.zip','web_nothreads_release.zip']:
        original = external/'4.3.stable'/name
        if not (local/name).exists() and original.is_file(): shutil.copy2(original,local/name)
    log = ROOT/'artifacts/web_export.log'
    log.parent.mkdir(exist_ok=True)
    with log.open('w') as out:
        subprocess.run(['godot','--headless','--path',str(ROOT),'--export-release','Web Mobile',str(raw/'game.html')],
                       cwd=ROOT, env=env, stdout=out, stderr=subprocess.STDOUT, check=True)
    text = log.read_text()
    if 'SCRIPT ERROR' in text or 'Parse Error' in text:
        raise RuntimeError('Web export contains a script error; see artifacts/web_export.log')
for name in ['game.wasm','game.pck','game.js']:
    if not (raw/name).is_file(): raise RuntimeError(f'Missing export: {name}')

dest = ROOT/'dist'
if dest.exists(): shutil.rmtree(dest)
dest.mkdir(); (dest/'data').mkdir(); (dest/'fonts').mkdir()
for source in (ROOT/'web').iterdir():
    if source.name == 'sw-template.js': continue
    if source.is_dir(): shutil.copytree(source, dest/source.name)
    else: shutil.copy2(source, dest/source.name)
for name in ['Cormorant.ttf','Inter.ttf']:
    shutil.copy2(ROOT/'assets/fonts'/name, dest/'fonts'/name)
shutil.copy2(ROOT/'icon.svg', dest/'icon.svg')
shutil.copy2(ROOT/'CREDITS.txt', dest/'CREDITS.txt')
shutil.copytree(ROOT/'LICENSES', dest/'LICENSES', dirs_exist_ok=True)
for path in raw.glob('game.*'):
    if path.name not in ['game.wasm','game.pck','game.js','game.html']:
        shutil.copy2(path, dest/path.name)
script = (raw/'game.js').read_bytes()
script_name = 'engine.'+hashlib.sha256(script).hexdigest()[:12]+'.js'
(dest/script_name).write_bytes(script)

def encode(name):
    data = (raw/name).read_bytes()
    compressed = gzip.compress(data, compresslevel=9, mtime=0)
    parts = []
    # Each file stays well below static-host per-file limits. Safari receives
    # an ordinary ArrayBuffer and never needs SharedArrayBuffer or COOP/COEP.
    for i, at in enumerate(range(0,len(compressed),8*1024*1024)):
        chunk = compressed[at:at+8*1024*1024]
        filename = f'data/{name}-{i:02d}.{hashlib.sha256(chunk).hexdigest()[:12]}.bin'
        (dest/filename).write_bytes(chunk)
        parts.append({'url':filename,'bytes':len(chunk)})
    assert gzip.decompress(compressed) == data
    return {'bytes':len(data),'compressedBytes':len(compressed),'sha256':hashlib.sha256(data).hexdigest(),'parts':parts}

manifest = {'engine':encode('game.wasm'),'pack':encode('game.pck'),'script':script_name,'threaded':False}
manifest['downloadBytes'] = manifest['engine']['compressedBytes']+manifest['pack']['compressedBytes']
inputs = (ROOT/'web/app.js').read_bytes()+(ROOT/'web/style.css').read_bytes()+json.dumps(manifest,sort_keys=True).encode()
manifest['version'] = hashlib.sha256(inputs).hexdigest()[:16]
(dest/'runtime.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
shell = ['./','index.html','app.js','style.css','manifest.webmanifest','icon.svg','runtime.json',script_name,
         'assets/poster.png','fonts/Inter.ttf','fonts/Cormorant.ttf','game.audio.worklet.js']
shell = [n for n in shell if n == './' or (dest/n).is_file()]
sw = (ROOT/'web/sw-template.js').read_text().replace('__VERSION__',manifest['version']).replace('__SHELL__',json.dumps(shell))
(dest/'sw.js').write_text(sw)
files = list(p for p in dest.rglob('*') if p.is_file())
assert max(p.stat().st_size for p in files)<25*1024*1024
report = dict(manifest, files=len(files),staticBytes=sum(p.stat().st_size for p in files),maxFileBytes=max(p.stat().st_size for p in files))
(ROOT/'artifacts/web_build.json').write_text(json.dumps(report,indent=2))
print(json.dumps({'version':manifest['version'],'downloadMB':round(manifest['downloadBytes']/1048576,2),
                  'packMB':round(manifest['pack']['bytes']/1048576,2),'files':len(files),'maxFileMB':round(report['maxFileBytes']/1048576,2)},indent=2),flush=True)
