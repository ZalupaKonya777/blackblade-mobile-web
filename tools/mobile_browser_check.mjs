import { chromium } from '../.runtime/qa/node_modules/playwright-core/index.mjs';
import { writeFile, mkdir } from 'node:fs/promises';

const artifacts = new URL('../artifacts/', import.meta.url);
await mkdir(artifacts, { recursive: true });
const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_PATH || '/root/.cache/ms-playwright/chromium-1248/chrome-linux64/chrome',
  headless: true,
  env: { ...process.env, XDG_DATA_HOME: new URL('../.runtime/qa-data', import.meta.url).pathname,
    XDG_CONFIG_HOME: new URL('../.runtime/qa-config', import.meta.url).pathname,
    XDG_CACHE_HOME: new URL('../.runtime/qa-cache', import.meta.url).pathname },
  args: ['--no-sandbox', '--disable-dev-shm-usage', '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--autoplay-policy=user-gesture-required'],
});
const context = await browser.newContext({ viewport: { width: 844, height: 390 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true, serviceWorkers: 'block' });
const page = await context.newPage();
const cdp = await context.newCDPSession(page);
const touches = new Map();
const errors = [], logs = [], checks = [];
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => { logs.push({ type: message.type(), text: message.text() }); if (message.type() === 'error') console.log('BROWSER ERROR', message.text().slice(0, 400)); });
page.on('requestfailed', request => logs.push({ type: 'requestfailed', text: `${request.url()} ${request.failure()?.errorText}` }));
function check(name, condition, detail = '') {
  checks.push({ name, ok: !!condition, detail }); console.log(condition ? 'PASS' : 'FAIL', name, JSON.stringify(detail));
  if (!condition) throw new Error(name);
}
async function state() { return page.evaluate(() => window.BlackbladeUI?.state); }
async function waitState(expression, timeout = 180000) {
  await page.waitForFunction(expression, null, { timeout, polling: 150 }); return state();
}
async function pointer(selector, type, id, dx = 0, dy = 0) {
  const ending = touches.get(id);
  if (type === 'pointerup') touches.delete(id);
  else {
    const r = await page.locator(selector).boundingBox();
    if (!r) throw new Error('Hidden touch target '+selector);
    touches.set(id, { x:r.x+r.width/2+dx, y:r.y+r.height/2+dy, id, radiusX:8, radiusY:8, force:.6 });
  }
  await cdp.send('Input.dispatchTouchEvent', {
    type: type === 'pointerdown' ? 'touchStart' : type === 'pointerup' ? 'touchEnd' : 'touchMove',
    // Chromium's implementation ends the IDs listed in a nonempty touchEnd;
    // sending the remaining fingers would release the joystick instead.
    touchPoints: type === 'pointerup' ? (touches.size && ending ? [ending] : []) : [...touches.values()],
  });
}
async function tap(selector, id = 5) {
  const r = await page.locator(selector).boundingBox();
  if (!r) throw new Error('Hidden tap target '+selector);
  const point = {x:r.x+r.width/2,y:r.y+r.height/2,id,radiusX:8,radiusY:8,force:.6};
  touches.set(id,point);
  const press = cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[...touches.values()]});
  touches.delete(id);
  const release = cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:touches.size?[point]:[]});
  // Queue a real quick tap before waiting for a software-rendered frame's ACK.
  // Waiting for that ACK can turn 70 ms into a sprint-length hold on this GPU.
  await Promise.all([press,release]);
}

let failure = null;
try {
  await page.goto(process.env.MOBILE_PREVIEW_URL || 'http://127.0.0.1:8793/?qa=1', { waitUntil: 'networkidle', timeout: 60000 });
  await page.screenshot({ path: new URL('mobile-home-landscape.png', artifacts).pathname, scale: 'css' });
  check('Landing fits landscape', await page.evaluate(() => document.documentElement.scrollWidth === innerWidth));
  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({ path: new URL('mobile-home-portrait.png', artifacts).pathname, scale: 'css' });
  check('Landing fits portrait', await page.evaluate(() => document.documentElement.scrollWidth === innerWidth));
  await page.setViewportSize({ width: 844, height: 390 });
  await page.getByRole('button', { name: /Войти в храм/ }).tap();
  console.log('Waiting for native Web engine…');
  await page.waitForFunction(() => typeof window.BlackbladeNative === 'function' && window.BlackbladeUI?.state?.phase === 'title', null, { timeout: 300000 });
  check('Actual Godot Web engine reaches title', true, await state());
  await page.getByRole('button', { name: 'Тренировка', exact: true }).tap();
  await waitState(() => window.BlackbladeUI.state.phase === 'fight');
  check('Training starts from the mobile menu', (await state()).training);
  await page.screenshot({ path: new URL('mobile-fight.png', artifacts).pathname, scale: 'css' });
  const layout = await page.evaluate(() => [...document.querySelectorAll('.combat-button,.utility')].filter(element => !element.hidden && element.getBoundingClientRect().width).map(element => {
    const r = element.getBoundingClientRect(); return { id: element.id, width: r.width, height: r.height, inside: r.x >= 0 && r.y >= 0 && r.right <= innerWidth && r.bottom <= innerHeight };
  }));
  check('Combat targets fit and are at least 44 CSS px', layout.every(r => r.inside && r.width >= 44 && r.height >= 44), layout);
  check('3D drawing buffer stays within its mobile budget', await page.evaluate(() => { const c = document.getElementById('game'); return c.width <= 1100 && c.height <= 650; }), await page.evaluate(() => ({ w: game.width, h: game.height, dpr: devicePixelRatio })));
  // The first screenshot uses the real 844px drawing buffer. Input probes use
  // a smaller buffer on this software-only GPU; DOM/touch coordinates stay real.
  await page.evaluate(() => { const c = document.getElementById('game'); c.width = 480; c.height = Math.round(480 * innerHeight / innerWidth); });
  await page.getByRole('button', { name: 'Пауза', exact: true }).tap();
  await waitState(() => window.BlackbladeUI.state.paused);
  await page.getByRole('button', { name: 'Начать заново', exact: true }).tap();
  await waitState(() => !window.BlackbladeUI.state.paused && window.BlackbladeUI.state.playerState === 'idle');
  const before = await state();
  await pointer('#joystick', 'pointerdown', 1, 0, 40);
  await page.waitForFunction(z => window.BlackbladeUI.state.playerZ > z+.12, before.playerZ, { timeout:60000 });
  await pointer('#joystick', 'pointermove', 1, 90, 40);
  await waitState(() => window.BlackbladeUI.state.playerZ > 6.3);
  check('Stick moves the real knight even beyond its ring', (await state()).playerZ > before.playerZ, [before.playerZ, (await state()).playerZ]);
  await tap('#dodge', 2);
  await waitState(() => window.BlackbladeUI.state.rolls > 0,30000);
  check('Second finger rolls while first finger keeps moving', (await state()).rolls > 0);
  await pointer('#joystick', 'pointerup', 1);
  await waitState(() => ['idle', 'move'].includes(window.BlackbladeUI.state.playerState));
  await tap('#light', 3);
  await waitState(() => window.BlackbladeUI.state.playerState === 'attack');
  check('Touch attack enters the real combat state', (await state()).action === 'light', await state());
  await waitState(() => ['idle', 'move'].includes(window.BlackbladeUI.state.playerState));
  // Start a fresh attempt before holding charge so this input check does not
  // depend on a random boss combination interrupting its anticipation.
  await page.getByRole('button', { name: 'Пауза', exact: true }).tap();
  await waitState(() => window.BlackbladeUI.state.paused);
  await page.getByRole('button', { name: 'Начать заново', exact: true }).tap();
  await waitState(() => !window.BlackbladeUI.state.paused && window.BlackbladeUI.state.playerState === 'idle');
  check('Mobile retry resets the actual attempt', (await state()).hp === 1300 && (await state()).stamina === 120);
  await pointer('#heavy', 'pointerdown', 4);
  await waitState(() => window.BlackbladeUI.state.charged && window.BlackbladeUI.state.action === 'heavy',60000);
  check('Held heavy button reaches full charge', true, await state());
  await pointer('#heavy', 'pointerup', 4);
  await page.getByRole('button', { name: 'Пауза', exact: true }).tap();
  await waitState(() => window.BlackbladeUI.state.paused);
  const paused = await state(); await page.waitForTimeout(700);
  check('Pause freezes combat time', Math.abs((await state()).elapsed - paused.elapsed) < .02);
  await page.screenshot({ path: new URL('mobile-pause.png', artifacts).pathname, scale: 'css' });
  await page.getByRole('button', { name: /Продолжить бой/ }).tap();
  await waitState(() => !window.BlackbladeUI.state.paused);
  await pointer('#dodge', 'pointerdown', 6);
  await page.evaluate(() => window.dispatchEvent(new Event('blur')));
  await waitState(() => window.BlackbladeUI.state.paused);
  await pointer('#dodge', 'pointerup', 6);
  check('Backgrounding releases inputs and pauses', await page.evaluate(() => !document.querySelector('.combat-button.held')));
  await page.setViewportSize({ width: 390, height: 844 });
  check('Portrait asks for rotation', await page.locator('#rotate').isVisible());
  await page.setViewportSize({ width: 667, height: 375 });
  await page.getByRole('button', { name: /Продолжить бой/ }).tap();
  await waitState(() => !window.BlackbladeUI.state.paused);
  await page.screenshot({ path: new URL('mobile-iphone-se.png', artifacts).pathname, scale: 'css' });
  check('Controls remain inside an iPhone SE landscape viewport', await page.evaluate(() => [...document.querySelectorAll('.combat-button')].every(element => { const r = element.getBoundingClientRect(); return r.x >= 0 && r.y >= 0 && r.right <= innerWidth && r.bottom <= innerHeight; })));
  check('Sound is unlocked after a real menu tap', await page.evaluate(() => window.BlackbladeUI.audioStates.some(state => state === 'running')), await page.evaluate(() => window.BlackbladeUI.audioStates));
  check('No JavaScript exceptions', errors.length === 0, errors);
  const nativeErrors = logs.filter(entry => entry.type === 'error' && /USER ERROR|SCRIPT ERROR|Failed loading resource|WebAssembly.*error/i.test(entry.text));
  check('No native browser resource or script errors', nativeErrors.length === 0, nativeErrors);
} catch (error) {
  failure = String(error); console.log('QA FAILED', failure);
  await page.screenshot({ path: new URL('mobile-failure.png', artifacts).pathname, scale: 'css' }).catch(() => {});
} finally {
  const report = { checks, failures: failure ? 1 : 0, failure, errors, state: await state().catch(() => null), logs, note: 'Chromium touch emulation with a real WebAssembly game and SwiftShader. The initial screenshot is 844px; later input probes lower only the 3D buffer to 480px. This does not measure physical iPhone/Safari performance.' };
  await writeFile(new URL('mobile_browser_check.json', artifacts), JSON.stringify(report, null, 2));
  await browser.close();
}
if (failure) process.exitCode = 1;
