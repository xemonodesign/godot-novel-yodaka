// Optional integration test: install Playwright and run against `make serve`.
// YODAKA_URL may point at Pages. Uses an isolated browser profile and its own saves.
// YODAKA_CHROMIUM points at a Chromium binary; otherwise the "chrome" channel is used.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const scenario = require('../src/data/scenario.json');
const output = process.env.YODAKA_SCREENSHOTS || '/tmp/yodaka-v4-browser';
fs.mkdirSync(output, { recursive: true });

async function saveRecord(page, replacement) {
  return page.evaluate(async (replacement) => {
    const db = await new Promise((resolve, reject) => {
      const request = indexedDB.open('/userfs');
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    const tx = db.transaction('FILE_DATA', replacement ? 'readwrite' : 'readonly');
    const done = new Promise((resolve, reject) => {
      tx.oncomplete = resolve;
      tx.onerror = () => reject(tx.error);
    });
    const store = tx.objectStore('FILE_DATA');
    let saved;
    await new Promise((resolve, reject) => {
      const cursor = store.openCursor();
      cursor.onerror = () => reject(cursor.error);
      cursor.onsuccess = () => {
        const entry = cursor.result;
        if (!entry) return resolve();
        if (String(entry.key).endsWith('yodaka_v1.json')) {
          saved = JSON.parse(new TextDecoder().decode(entry.value.contents));
          if (replacement) entry.update({ ...entry.value,
            contents: new TextEncoder().encode(JSON.stringify(replacement)), timestamp: new Date() });
        }
        entry.continue();
      };
    });
    await done;
    db.close();
    return saved;
  }, replacement);
}

// Screen coordinates of the 1280x800 stage (see src/main.gd).
const NEXT = [1095, 557];
const OVERLAY = [640, 400];
const KARTE_CLOSE = [953, 638];
const SLEEP = [1044, 543];
const FIRST_WORD = [136, 289];
const FIRST_GROWTH = [952, 373];
const COUNSEL_CHOICE = [434, 463];
const MAP_SLOTS = Array.from({ length: 18 }, (_, i) => [202 + (i % 3) * 244, 185 + Math.floor(i / 3) * 66]);

function availableEvent(save) {
  const week = save.round_index + 1;
  for (let i = 0; i < scenario.map_events.length; i++) {
    const event = scenario.map_events[i];
    if (event.repeatable) continue;
    if (event.unlock > week || save.visited.includes(event.id) || save.stats[0] >= 80) continue;
    return i;
  }
  return scenario.map_events.findIndex(event => event.repeatable);
}

(async () => {
  const launch = { headless: true, args: ['--no-proxy-server', '--enable-webgl', '--ignore-gpu-blocklist', '--use-gl=angle', '--use-angle=swiftshader'] };
  if (process.env.YODAKA_CHROMIUM) launch.executablePath = process.env.YODAKA_CHROMIUM;
  else launch.channel = 'chrome';
  const browser = await chromium.launch(launch);
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
    const shot = name => page.screenshot({ path: path.join(output, `${name}.png`) });
    const click = async (point, wait = 120) => { await page.mouse.click(point[0], point[1]); await page.waitForTimeout(wait); };
    // Godot syncs user:// to IndexedDB shortly after each write; poll instead of trusting one read.
    const settled = async (predicate, timeout = 6000) => {
      const started = Date.now();
      let save = await saveRecord(page);
      while (!predicate(save) && Date.now() - started < timeout) {
        await page.waitForTimeout(250);
        save = await saveRecord(page);
      }
      return save;
    };
    const ready = async () => {
      await page.locator('#loading').waitFor({ state: 'detached', timeout: 90000 });
      await page.waitForTimeout(700);
    };
    await page.goto(process.env.YODAKA_URL || 'http://127.0.0.1:8060/');
    await ready();
    await shot('title');
    await page.mouse.click(210, 500);
    await page.waitForTimeout(800);
    await shot('counseling-card');
    const initial = await saveRecord(page);
    assert.equal(initial.version, 4);
    assert.equal(initial.current, 'counsel0_6');
    assert.equal(initial.scene_key, '');
    await page.keyboard.press('Space');
    await page.keyboard.press('Escape');
    await page.waitForTimeout(800);
    assert.equal((await saveRecord(page)).scene_key, '', 'Blackout requires a click');
    await click(OVERLAY, 2800);
    await shot('minato');

    // Drive the whole loop from the real save state: counseling, outings, nights, chapters.
    const seen = { map: 0, night: 0, chapter: new Set(), grown: 0, karte: 0 };
    let save = initial;
    let signature = '';
    let stalled = 0;
    for (let i = 0; i < 1600 && save.current !== 'result'; i++) {
      save = await saveRecord(page);
      const next = JSON.stringify([save.current, save.counsel_step, save.night_step, save.read_count, save.answers.length, save.visited.length]);
      stalled = next === signature ? stalled + 1 : 0;
      signature = next;
      if (stalled >= 12) {
        await shot('stall');
        throw new Error('Playthrough stalled at ' + next);
      }
      if (save.current === 'map') {
        seen.map++;
        if (seen.map === 1) await shot('map');
        await click(MAP_SLOTS[availableEvent(save)], 900);
        await click(OVERLAY, 900);
        continue;
      }
      if (save.current === 'night') {
        seen.night++;
        const candidates = save.collected.filter(id => !save.answers.some(a => a.word === id));
        if (save.night_step === 'pick' && candidates.length > 0) {
          await click(FIRST_WORD, 400);
          if (seen.night === 1) await shot('night');
          await click(FIRST_GROWTH, 900);
          const grown = await settled(record => record.night_step === 'reply');
          assert.equal(grown.night_step, 'reply');
          assert.equal(grown.answers.length, save.answers.length + 1);
          seen.grown++;
          if (seen.grown === 1) await shot('night-grown');
        }
        await click(SLEEP, 900);  // the map or a chapter card follows; the next pass handles it
        continue;
      }
      const node = scenario.nodes[save.current];
      if (node && node.kind === 'main') seen.chapter.add(node.chapter);
      const choices = save.current === 'counseling' ? (save.counsel_step === 'choice' ? 1 : 0)
        : (node && node.choices ? node.choices.length : 0);
      await click(NEXT, 500);
      await click(OVERLAY, 500);  // dismisses a blackout, otherwise advances the finished line
      if (save.current === 'counseling' && save.counsel_step === 'choice') {
        await click(COUNSEL_CHOICE, 500);
      } else if (choices > 1) {
        const width = 614 / choices;
        await click([337 + width / 2, 451], 500);
      }
      const after = await saveRecord(page);
      if ((node && node.karte) || (save.current === 'counseling' && save.counsel_step === 'closing')) {
        if (after.current === save.current && after.counsel_step === save.counsel_step) {
          seen.karte++;
          await shot(seen.karte === 1 ? 'karte' : 'karte-final');
          await click(KARTE_CLOSE, 400);
          await click(NEXT, 400);
        }
      }
      if (i % 40 === 39) console.log('Playthrough', i + 1, after.current, after.counsel_step, after.round_index, after.stats);
    }
    save = await settled(record => record.current === 'result');
    assert.equal(save.current, 'result');
    assert.equal(save.round_index, 4);
    assert.equal(seen.chapter.size, 4, 'All four chapters played');
    assert.equal(seen.map, 12, 'Twelve outings');
    assert.equal(seen.night, 16, 'A night after every outing and chapter');
    assert.ok(save.collected.length >= 8, 'Words collected');
    assert.equal(save.answers.length, save.collected.length, 'Every word interpreted');
    assert.ok(seen.karte >= 2, 'Karte shown in the tutorial and the closing');
    for (const answer of save.answers) {
      assert.ok(answer.delta.filter(value => value !== 0).length <= 2);
    }
    for (const id of save.collected) assert.equal(save.gains[id].length, 4);
    await shot('result');
    await page.reload();
    await ready();
    await page.mouse.click(475, 500);
    await page.waitForTimeout(800);
    await shot('resumed');
    assert.equal((await saveRecord(page)).current, 'result');

    // Reuse the real save structure to inspect exact visual states in an isolated profile.
    const seed = async replacement => {
      for (let attempt = 0; attempt < 3; attempt++) {
        await page.waitForTimeout(1500);  // let Godot's own IndexedDB sync land first
        await saveRecord(page, replacement);
        await page.reload();
        await ready();
        await page.mouse.click(475, 500);
        const loaded = await settled(record => record.current === replacement.current, 3000);
        if (loaded.current === replacement.current) return;
      }
      throw new Error('Seeded save was not restored: ' + replacement.current);
    };
    const common = { ...initial, version: 4, stats: [60, 35, 35, 35], collected: [], gains: {}, answers: [],
      history: [], pending_word: '', visited: [], round_index: 0, outings_done: 0, after_night: 'map',
      night_step: 'pick', night_word: '', reviewed: 0, counsel_step: 'opening_doctor' };
    await seed({ ...common, current: 'sushi_10', collected: ['praise'], gains: { praise: [-6, 0, 5, 0] },
      scene_key: '0|寄り道 / 売ったバッシュで寿司を食う|自宅_リビング', pending_word: 'praise' });
    await shot('received-word');
    await page.keyboard.press('Space');
    await page.keyboard.press('Escape');
    await page.waitForTimeout(800);
    assert.equal((await saveRecord(page)).pending_word, 'praise');
    await click(OVERLAY, 700);
    assert.equal((await settled(record => record.pending_word === '')).pending_word, '');

    await seed({ ...common, current: 'counsel1_10', scene_key: '0|はじめてのカウンセリング|診察室' });
    await click(NEXT, 600);
    await shot('tutorial-choice');
    await click([433, 451], 900);
    const tutorial = await settled(record => record.current === 'counsel1_12');
    assert.equal(tutorial.current, 'counsel1_12');
    assert.deepEqual(tutorial.stats, [60, 35, 39, 35]);

    await seed({ ...common, current: 'map', stats: [80, 35, 35, 35] });
    await shot('map-stress');
    await click(MAP_SLOTS[1], 600);
    assert.equal((await settled(record => record.current !== 'map', 1500)).current, 'map', 'High stress blocks outings');
    await click(MAP_SLOTS[17], 900);
    assert.equal((await settled(record => record.current === 'rest_0')).current, 'rest_0');

    const gate = scenario.nodes.main4_31;
    const gateScene = `4|${gate.chapter}|${gate.place}`;
    await seed({ ...common, current: 'main4_31', stats: [60, 59, 35, 35], scene_key: gateScene, round_index: 3 });
    await page.waitForTimeout(1400);
    await shot('courage-locked');
    await click([791, 450], 800);
    assert.equal((await settled(record => record.current !== 'main4_31', 1500)).current, 'main4_31');
    await seed({ ...common, current: 'main4_31', stats: [60, 60, 35, 35], scene_key: gateScene, round_index: 3 });
    await page.waitForTimeout(1400);
    await click([791, 450], 2400);
    assert.equal((await settled(record => record.current === 'main4_38')).current, 'main4_38');

    await seed({ ...common, current: 'counseling', collected: ['queen', 'praise'], gains: { queen: [3, 0, 0, 6], praise: [-6, 0, 5, 0] },
      answers: [{ word: 'queen', choice: 0, delta: [0, 6, 0, 6], stage: 'night' }], reviewed: 1, counsel_step: 'choice',
      scene_key: '0|総括のカウンセリング|診察室', round_index: 4, after_night: 'counseling' });
    await page.waitForTimeout(600);
    await shot('choice-preview');
    await click(COUNSEL_CHOICE, 2800);
    const answered = await settled(record => record.counsel_step === 'reply');
    assert.equal(answered.counsel_step, 'reply');
    assert.deepEqual(answered.answers[1].delta, [-8, 0, 4, 0]);
    assert.deepEqual(answered.stats, [52, 35, 39, 35]);
    await shot('yodaka-reply');

    await page.setViewportSize({ width: 844, height: 390 });
    await page.waitForTimeout(500);
    await shot('mobile');
    fs.writeFileSync(path.join(output, 'verification.json'), JSON.stringify({ errors, seen: { ...seen, chapter: [...seen.chapter] },
      fullRun: save, answered }, null, 2));
    assert.deepEqual(errors, [], 'No runtime errors');
    console.log(`PASS: full loop (${seen.map} outings, ${seen.night} nights, ${seen.grown} grown words, ${save.collected.length} words), tutorial effects, stress lock, courage gate, counseling reply`);
    await page.close();
  } catch (error) {
    for (const page of browser.contexts().flatMap(context => context.pages())) {
      await page.screenshot({ path: path.join(output, 'failure.png') });
    }
    throw error;
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
