import './sound.js';
const $ = id => document.getElementById(id);
const canvas = $('game');
let engineReady = false;
let loading = false;
let lastState = null;
let wasActive = false;
let previousPhase = 'title';
let previousBossPhase = 1;
let rotationPauseRequested = false;
let resultTimer = 0;
let announcementTimer = 0;
let pendingSoundVolume = null;
let soundTestUntil = 0;
let runningBuild = null;
let availableBuild = null;
let serviceWorkerRegistration = null;
let lastUpdateCheck = -Infinity;
const pointers = new Map();
let stickPointer = null;
let lookPointer = null;
let lookPoint = null;
const audioContexts = new Set();
const graphicsProfiles = [
  { name: 'Плавность', dpr: 1.25, width: 1440, height: 864 },
  { name: 'Высокая · HD', dpr: 2, width: 2304, height: 1296 },
  { name: 'Максимальная', dpr: 2.5, width: 2880, height: 1620 },
];
let graphicsQuality = 1;
try {
  const saved = Number(localStorage.getItem('blackblade-visual-quality-v2') ?? 1);
  if (Number.isInteger(saved) && graphicsProfiles[saved]) graphicsQuality = saved;
} catch { /* Storage can be unavailable in a private browsing session. */ }
$('graphics-quality').value = String(graphicsQuality);

// Safari requires resume() to run inside a real user gesture, including when
// that gesture belongs to an HTML control rather than to Godot's canvas.
const AudioContextClass = window.AudioContext || window.webkitAudioContext;
if (AudioContextClass) {
  const GestureAudioContext = new Proxy(AudioContextClass, {
    construct(Target, args) {
      const context = Reflect.construct(Target, args);
      audioContexts.add(context);
      return context;
    },
  });
  window.AudioContext = GestureAudioContext;
  if (window.webkitAudioContext) window.webkitAudioContext = GestureAudioContext;
}
function unlockAudio() {
  window.BlackbladeSound.unlock();
  for (const context of audioContexts) {
    if (context.state === 'suspended') context.resume().catch(() => {});
  }
}
document.addEventListener('keydown', unlockAudio, { capture: true });
document.addEventListener('click', unlockAudio, { capture: true });
document.addEventListener('pointerdown', unlockAudio, { capture: true });
document.addEventListener('touchend', unlockAudio, { capture: true, passive: true });

function send(data) {
  if (typeof window.BlackbladeNative === 'function') window.BlackbladeNative(JSON.stringify(data));
}
function focusGame() { canvas.focus({ preventScroll: true }); }
function bar(id, value) { $(id).style.transform = `scaleX(${Math.max(0, Math.min(1, value))})`; }
function announce(text, duration = 2400) {
  clearTimeout(announcementTimer);
  $('announcement').textContent = text;
  $('announcement').classList.add('show');
  announcementTimer = setTimeout(() => $('announcement').classList.remove('show'), duration);
}
function isPortrait() { return window.innerHeight > window.innerWidth / 1.3; }
function orientation() {
  const rotate = engineReady && lastState?.phase !== 'title' && isPortrait();
  $('rotate').hidden = !rotate;
  if (rotate && lastState?.phase === 'fight' && !lastState.paused && !rotationPauseRequested) {
    rotationPauseRequested = true;
    cancelControls();
    send({ type: 'blur' });
  }
  if (!rotate) rotationPauseRequested = false;
}

window.BlackbladeUI = {
  get state() { return lastState; },
  get audioStates() { return [...audioContexts].map(context => context.state); },
  get graphics() { return { quality: graphicsQuality, name: graphicsProfiles[graphicsQuality].name,
    width: canvas.width, height: canvas.height, dpr: devicePixelRatio }; },
  ready() {
    engineReady = true;
    document.body.classList.add('loaded');
    $('enter').disabled = false;
    $('enter-text').textContent = 'Вступить в бой';
    $('training').hidden = false;
    $('progress-track').hidden = true;
    $('load-status').textContent = 'Храм открыт. Выбери бой или тренировку.';
    // ready() runs inside Godot's initialisation callback. Do not re-enter
    // WebAssembly to rebuild viewports while the renderer is being created.
    if (pendingSoundVolume !== null) setTimeout(() => send({ type: 'setting', key: 'volume', value: pendingSoundVolume }), 0);
    if (graphicsQuality !== 1) setTimeout(() => send({ type: 'setting', key: 'quality', value: graphicsQuality }), 0);
  },
  update(encoded) {
    const state = JSON.parse(encoded);
    const oldState = lastState;
    lastState = state;
    const fighting = state.phase === 'fight';
    const active = fighting && !state.paused && !isPortrait();
    const cancel = wasActive && !active;
    wasActive = active;
    $('home').hidden = state.phase !== 'title';
    $('hud').hidden = !['intro', 'fight', 'dead', 'won'].includes(state.phase);
    $('touch-controls').hidden = !active;
    $('pause-menu').hidden = !(fighting && state.paused);
    $('training-tag').hidden = !state.training;
    $('change-phase').hidden = !state.training;
    $('boss-hud').hidden = state.bossHP <= 0;
    $('curse').hidden = state.curse <= 0;
    $('lock').setAttribute('aria-pressed', String(state.locked));
    $('hp-text').textContent = `${Math.ceil(state.hp)} / ${Math.ceil(state.hpCap)}`;
    $('boss-name').textContent = state.bossPhase === 1 ? 'Астар, зверь затмения' : 'Астар, Чёрный Клинок';
    $('boss-phase').textContent = state.bossPhase === 1 ? 'I / ЗВЕРИНАЯ КЛЯТВА' : 'II / ПРЕДНАЧЕРТАННАЯ СМЕРТЬ';
    $('flask-count').textContent = state.training ? '∞' : state.flasks;
    $('heavy').querySelector('span').textContent = state.counter ? 'КОНТР' : (state.charged && state.action === 'heavy' ? 'ЗАРЯЖЕН' : 'СИЛЬНЫЙ');
    $('heavy').classList.toggle('charged', state.charged && state.action === 'heavy');
    bar('hp-fill', state.hp / state.maxHP);
    bar('stamina-fill', state.stamina / state.maxStamina);
    bar('boss-fill', state.bossHP / state.maxBossHP);
    bar('stance-fill', state.stance / state.maxStance);
    for (const [id, cost] of [['light', 20], ['heavy', state.counter ? 28 : 34], ['dodge', 18], ['jump', 12], ['parry', 16]]) {
      $(id).classList.toggle('insufficient', state.stamina + .01 < cost);
    }
    if (document.activeElement !== $('volume')) $('volume').value = state.volume;
    $('shake').checked = state.shake;
    updateSoundControls();
    if (document.activeElement !== $('music-volume')) $('music-volume').value = state.music;
    if (state.phase !== previousPhase) {
      previousPhase = state.phase;
      clearTimeout(resultTimer);
      $('result').hidden = true;
      if (state.phase === 'intro') announce('АСТАР · ЗВЕРЬ ЗАТМЕНИЯ');
      if (state.phase === 'dead' || state.phase === 'won') {
        const won = state.phase === 'won';
        const seconds = Math.floor(state.elapsed);
        $('result-title').textContent = won ? 'ВРАГ ПОВЕРЖЕН' : 'ТЫ ПОГИБ';
        $('result').querySelector('.result-content').classList.toggle('won', won);
        $('result-stats').textContent = `${String(Math.floor(seconds / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')} · Попаданий: ${state.hits} · Уклонений: ${state.evades}`;
        resultTimer = setTimeout(() => { if (lastState?.phase === state.phase) $('result').hidden = false; }, 1000);
      }
    }
    if (state.bossPhase === 2 && previousBossPhase === 1 && fighting) announce('ЧЁРНЫЙ КЛИНОК');
    previousBossPhase = state.bossPhase;
    if (cancel) cancelControls();
    orientation();
    if (!oldState) resizeCanvas();
  },
};

function cancelControls() {
  for (const entry of pointers.values()) entry.button.classList.remove('held');
  pointers.clear();
  stickPointer = null; lookPointer = null; lookPoint = null;
  $('joystick').classList.remove('active');
  $('stick-knob').style.transform = '';
  send({ type: 'cancel' });
}
for (const button of document.querySelectorAll('.action-button')) {
  button.addEventListener('pointerdown', event => {
    event.preventDefault();
    if (!wasActive || [...pointers.values()].some(entry => entry.action === button.dataset.action)) return;
    button.setPointerCapture(event.pointerId);
    pointers.set(event.pointerId, { button, action: button.dataset.action });
    button.classList.add('held');
    send({ type: 'action', action: button.dataset.action, pressed: true });
  });
  button.addEventListener('pointerup', event => {
    event.preventDefault();
    const entry = pointers.get(event.pointerId);
    if (!entry) return;
    pointers.delete(event.pointerId);
    entry.button.classList.remove('held');
    send({ type: 'action', action: entry.action, pressed: false });
  });
  button.addEventListener('pointercancel', cancelControls);
  button.addEventListener('lostpointercapture', event => {
    if (event.target !== event.currentTarget) return;
    if (pointers.has(event.pointerId)) cancelControls();
  });
}

function moveStick(event) {
  const bounds = $('joystick').getBoundingClientRect();
  const radius = bounds.width * .34;
  const x = (event.clientX - bounds.left - bounds.width / 2) / radius;
  const y = (event.clientY - bounds.top - bounds.height / 2) / radius;
  const length = Math.hypot(x, y);
  const dx = length ? x / length : 0, dy = length ? y / length : 0;
  const strength = Math.min(1, Math.max(0, (length - .12) / .88));
  $('stick-knob').style.transform = `translate(${dx * Math.min(1, length) * radius}px,${dy * Math.min(1, length) * radius}px)`;
  send({ type: 'move', active: true, x: dx * strength, y: dy * strength });
}
$('joystick').addEventListener('pointerdown', event => {
  event.preventDefault();
  if (!wasActive || stickPointer !== null) return;
  stickPointer = event.pointerId;
  $('joystick').setPointerCapture(stickPointer);
  $('joystick').classList.add('active');
  moveStick(event);
});
$('joystick').addEventListener('pointermove', event => {
  if (event.pointerId !== stickPointer) return;
  event.preventDefault(); moveStick(event);
});
function releaseStick(event) {
  if (event.pointerId !== stickPointer) return;
  stickPointer = null;
  $('joystick').classList.remove('active'); $('stick-knob').style.transform = '';
  send({ type: 'move', active: false });
}
$('joystick').addEventListener('pointerup', releaseStick);
$('joystick').addEventListener('pointercancel', cancelControls);
$('joystick').addEventListener('lostpointercapture', event => {
  if (event.target === event.currentTarget) releaseStick(event);
});
canvas.addEventListener('contextmenu', event => event.preventDefault());
canvas.addEventListener('pointerdown', event => {
  if (!wasActive || lookPointer !== null) return;
  event.preventDefault();
  lookPointer = event.pointerId; lookPoint = { x: event.clientX, y: event.clientY };
  canvas.setPointerCapture(lookPointer);
});
canvas.addEventListener('pointermove', event => {
  if (event.pointerId !== lookPointer || !lookPoint) return;
  event.preventDefault();
  const scale = 1600 / window.innerWidth;
  send({ type: 'look', x: (event.clientX - lookPoint.x) * scale, y: (event.clientY - lookPoint.y) * scale });
  lookPoint = { x: event.clientX, y: event.clientY };
});
canvas.addEventListener('pointerup', event => { if (event.pointerId === lookPointer) { lookPointer = null; lookPoint = null; } });
canvas.addEventListener('pointercancel', cancelControls);

function resizeCanvas() {
  // CSS pixels are not display pixels on an iPhone. Render at retina density,
  // retaining a bounded GPU budget and a deliberate user-selected fallback.
  const width = window.innerWidth, height = window.innerHeight;
  const profile = graphicsProfiles[graphicsQuality];
  const scale = Math.min(devicePixelRatio || 1, profile.dpr, profile.width / width, profile.height / height);
  const w = Math.max(320, Math.round(width * scale)), h = Math.max(180, Math.round(height * scale));
  if (canvas.width !== w) canvas.width = w;
  if (canvas.height !== h) canvas.height = h;
  orientation();
}
window.addEventListener('resize', resizeCanvas);
window.visualViewport?.addEventListener('resize', resizeCanvas);
document.addEventListener('visibilitychange', () => {
  if (document.hidden) { cancelControls(); send({ type: 'blur' }); }
  else checkForGameUpdate();
});
window.addEventListener('blur', () => { cancelControls(); send({ type: 'blur' }); });
resizeCanvas();

$('pause').addEventListener('click', () => { cancelControls(); send({ type: 'pause' }); });
$('resume').addEventListener('click', () => { send({ type: 'pause' }); focusGame(); });
$('restart').addEventListener('click', () => { cancelControls(); send({ type: 'retry' }); focusGame(); });
$('retry').addEventListener('click', () => { cancelControls(); send({ type: 'retry' }); focusGame(); });
for (const id of ['to-title', 'result-home']) $(id).addEventListener('click', () => { cancelControls(); send({ type: 'title' }); });
$('change-phase').addEventListener('click', () => send({ type: 'phase' }));
$('music-volume').addEventListener('input', event => send({ type: 'setting', key: 'music', value: Number(event.target.value) }));
function updateSoundControls() {
  const sound = window.BlackbladeSound;
  const disabled = sound.muted || sound.volume <= .0001;
  $('sound-toggle').textContent = disabled ? 'Включить звук' : 'Выключить звук';
  $('sound-toggle').setAttribute('aria-pressed', String(disabled));
  $('sound-enable')?.classList.toggle('needs-audio', disabled || sound.needsGesture);
  const text = disabled ? 'Звук выключен.' : performance.now() < soundTestUntil
    ? 'Проверка: два коротких сигнала.' : sound.needsGesture
      ? 'Нажми кнопку со значком звука.' : 'Звук включён. Можно проверить сигналом.';
  for (const id of ['sound-status', 'home-sound-status']) if ($(id)) $(id).textContent = text;
}
function enableSound() {
  const sound = window.BlackbladeSound;
  if (sound.volume <= .0001) {
    pendingSoundVolume = .75;
    sound.settings(.75, sound.musicVolume);
    send({ type: 'setting', key: 'volume', value: .75 });
  }
  sound.mute(false);
  sound.unlock({ repair: true, test: true });
  soundTestUntil = performance.now() + 1800;
  updateSoundControls();
  setTimeout(updateSoundControls, 1900);
}
for (const id of ['home-sound', 'sound-enable', 'sound-check']) $(id)?.addEventListener('click', enableSound);
window.addEventListener('blackbladeaudiochange', updateSoundControls);
window.addEventListener('blackbladeaudioprobe', () => { soundTestUntil = performance.now() + 1800; updateSoundControls(); setTimeout(updateSoundControls, 1900); });
$('sound-toggle').addEventListener('click', () => {
  const sound = window.BlackbladeSound;
  if (sound.muted || sound.volume <= .0001) enableSound();
  else { sound.mute(true); updateSoundControls(); }
});
updateSoundControls();
$('volume').addEventListener('input', event => send({ type: 'setting', key: 'volume', value: Number(event.target.value) }));
$('shake').addEventListener('change', event => send({ type: 'setting', key: 'shake', value: event.target.checked }));
$('graphics-quality').addEventListener('change', event => {
  graphicsQuality = Number(event.target.value);
  try { localStorage.setItem('blackblade-visual-quality-v2', String(graphicsQuality)); } catch {}
  resizeCanvas();
  send({ type: 'setting', key: 'quality', value: graphicsQuality });
});
$('reload').addEventListener('click', () => location.reload());
$('home-help-toggle').addEventListener('click', () => {
  $('home-help').hidden = !$('home-help').hidden;
  $('home-help-toggle').setAttribute('aria-expanded', String(!$('home-help').hidden));
});
if (!document.fullscreenEnabled) $('fullscreen').hidden = true;
$('fullscreen').addEventListener('click', async () => {
  try {
    if (!document.fullscreenElement) {
      await document.documentElement.requestFullscreen({ navigationUI: 'hide' });
      try { await screen.orientation?.lock('landscape'); } catch {}
    } else await document.exitFullscreen();
  } catch {}
});

const manifestPromise = fetch('runtime.json', { cache: 'no-cache' }).then(response => {
  if (!response.ok) throw new Error(`Не удалось получить файлы игры (${response.status}).`);
  return response.json();
});
manifestPromise.then(manifest => {
  runningBuild = manifest.version;
  if ($('build-version')) $('build-version').textContent = 'Версия ' + runningBuild.slice(0, 8);
  showGameUpdate();
  if (!loading) $('load-status').textContent = `Загрузка ≈ ${Math.ceil(manifest.downloadBytes / 1048576)} МБ · горизонтальный экран`;
}).catch(() => {});

async function loadScript(url) {
  await new Promise((resolve, reject) => {
    const script = document.createElement('script'); script.src = url;
    script.onload = resolve; script.onerror = () => reject(new Error('Не удалось загрузить движок. Проверь соединение.'));
    document.head.appendChild(script);
  });
}
async function loadGame() {
  if (loading) return;
  loading = true; $('enter').disabled = true; $('enter-text').textContent = 'Открываем храм…';
  $('progress-track').hidden = false;
  try {
    if (!window.WebAssembly) throw new Error('Этот браузер не поддерживает WebAssembly. Открой игру в актуальном Safari или Chrome.');
    const probe = document.createElement('canvas');
    const gl = probe.getContext('webgl2', { antialias: false });
    if (!gl) throw new Error('Не удалось включить WebGL 2. Проверь, что аппаратная графика разрешена в браузере.');
    gl.getExtension('WEBGL_lose_context')?.loseContext();
    const manifest = await manifestPromise;
    let downloaded = 0;
    const progress = amount => {
      downloaded += amount;
      $('progress-fill').style.transform = `scaleX(${Math.min(.96, downloaded / manifest.downloadBytes * .96)})`;
      $('load-status').textContent = `${(downloaded / 1048576).toFixed(1)} / ${(manifest.downloadBytes / 1048576).toFixed(1)} МБ`;
    };
    async function unpack(asset) {
      const parts = [];
      for (const part of asset.parts) {
        const response = await fetch(part.url, { cache: 'force-cache' });
        if (!response.ok) throw new Error(`Не удалось загрузить часть игры (${response.status}). Проверь соединение.`);
        const reader = response.body.getReader(); let count = 0;
        while (true) {
          const { value, done } = await reader.read(); if (done) break;
          parts.push(value); count += value.length; progress(value.length);
        }
        if (count !== part.bytes) throw new Error('Загрузка прервалась. Попробуй войти ещё раз.');
      }
      const compressed = new Blob(parts);
      let buffer;
      if (typeof DecompressionStream === 'function') buffer = await new Response(compressed.stream().pipeThrough(new DecompressionStream('gzip'))).arrayBuffer();
      else {
        const { gunzipSync } = await import('./vendor/fflate.js');
        buffer = gunzipSync(new Uint8Array(await compressed.arrayBuffer())).buffer;
      }
      if (buffer.byteLength !== asset.bytes) throw new Error('Файлы игры загрузились не полностью. Попробуй ещё раз.');
      return buffer;
    }
    let [wasm, pack] = await Promise.all([unpack(manifest.engine), unpack(manifest.pack), loadScript(manifest.script), window.BlackbladeSound.prepare()]);
    $('load-status').textContent = 'Создаём мир. Первый вход может занять немного времени…';
    const originalFetch = window.fetch;
    window.fetch = function(input, init) {
      const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
      if (new URL(url, location.href).pathname.endsWith('/game.wasm')) {
        return Promise.resolve(new Response(wasm, { headers: { 'Content-Type': 'application/wasm', 'Content-Length': String(wasm.byteLength) } }));
      }
      return originalFetch.call(this, input, init);
    };
    const engine = new Engine({ canvas, executable: 'game', canvasResizePolicy: 0, focusCanvas: true,
      persistentPaths: ['/userfs'], args: ['--main-pack', 'game.pck', ...(new URLSearchParams(location.search).has('qa') ? ['--', '--qa-controls'] : [])], onExit: code => {
        if (code) showError(new Error('Игра завершилась. Попробуй открыть храм заново.'));
      },
      onPrintError: text => console.error('[Godot]', text),
    });
    try { await engine.init('game'); } finally { window.fetch = originalFetch; wasm = null; }
    await engine.preloadFile(pack, 'game.pck'); pack = null;
    await engine.start();
    resizeCanvas();
    $('progress-fill').style.transform = 'scaleX(1)';
  } catch (error) { console.error(error); showError(error); }
}
function showError(error) {
  $('error-text').textContent = error.message || 'Не удалось загрузить игру. Проверь соединение и попробуй снова.';
  $('error').hidden = false;
}
$('enter').addEventListener('click', () => {
  if (!engineReady) loadGame();
  else { cancelControls(); send({ type: 'start', training: false }); focusGame(); }
});
$('training').addEventListener('click', () => { cancelControls(); send({ type: 'start', training: true }); focusGame(); });

function showGameUpdate() {
  const available = !!(runningBuild && availableBuild && runningBuild !== availableBuild);
  for (const id of ['update-game', 'home-update-game']) if ($(id)) $(id).hidden = !available;
}
function checkForGameUpdate() {
  if (!serviceWorkerRegistration || performance.now() - lastUpdateCheck < 15000) return;
  lastUpdateCheck = performance.now(); serviceWorkerRegistration.update().catch(() => {});
}
for (const id of ['update-game', 'home-update-game']) $(id)?.addEventListener('click', () => {
  cancelControls(); send({ type: 'blur' }); location.reload();
});
if ('serviceWorker' in navigator && !new URLSearchParams(location.search).has('qa')) {
  navigator.serviceWorker.addEventListener('message', event => {
    if (event.data?.type !== 'blackblade-update-ready') return;
    availableBuild = event.data.version; showGameUpdate();
  });
  navigator.serviceWorker.addEventListener('controllerchange', () => navigator.serviceWorker.controller?.postMessage({ type: 'blackblade-version' }));
  window.addEventListener('load', () => navigator.serviceWorker.register('sw.js', { updateViaCache: 'none' }).then(registration => {
    serviceWorkerRegistration = registration; checkForGameUpdate();
  }).catch(error => console.warn('Offline cache unavailable', error)));
  window.addEventListener('pageshow', checkForGameUpdate);
}
