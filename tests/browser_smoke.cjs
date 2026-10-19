// Optional integration test: install Playwright and run against `make serve`.
// YODAKA_URL may point at Pages. Uses an isolated browser profile and its own saves.
// YODAKA_CHROMIUM points at a Chromium binary; otherwise the "chrome" channel is used.
// YODAKA_QUICK=1 skips the full playthrough (about 25 minutes) and runs only the seeded checks.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const scenario = require('../src/data/scenario.json');
const output = process.env.YODAKA_SCREENSHOTS || '/tmp/yodaka-v5-browser';
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
const OVERLAY = [640, 640];
const KARTE_CLOSE = [953, 638];
const KEEP = [771, 478];
const RELEASE = [1049, 478];
const TALK = [948, 294];
const FACE = [948, 460];
const GROW = [948, 411];
const END_SESSION = [1074, 541];
const MAP_SLOTS = [[253, 211], [623, 211], [253, 336], [623, 336], [253, 461], [623, 461]];
const slotPoint = index => [294 + index * 116 + 54, 704];

function effectiveStress(save) {
  let offset = 0;
  for (const entry of save.slots) {
    if (!entry.startsWith('t:')) continue;
    const trauma = scenario.traumas.find(t => t.id === entry.slice(2));
    const scale = save.trauma_state[trauma.id].hardness / 100;
    for (const debuff of trauma.debuffs) {
      if (debuff.kind === 'offset' && debuff.stat === 'ストレス') offset += Math.round(debuff.value * scale);
    }
  }
  return Math.min(100, Math.max(0, save.stats[0] + offset));
}

function availableEvent(save) {
  const week = save.round_index + 1;
  for (let i = 0; i < scenario.map_events.length; i++) {
    const event = scenario.map_events[i];
    if (event.repeatable) continue;
    if (event.unlock > week || save.visited.includes(event.id) || effectiveStress(save) >= 80) continue;
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
    assert.equal(initial.version, 5);
    assert.equal(initial.current, 'counsel0_6');
    assert.equal(initial.scene_key, '');
    assert.equal(initial.slots.filter(entry => entry.startsWith('t:')).length, 8, 'Every slot starts as a trauma');
    assert.equal(initial.exp, 0);
    await page.keyboard.press('Space');
    await page.keyboard.press('Escape');
    await page.waitForTimeout(800);
    assert.equal((await saveRecord(page)).scene_key, '', 'Blackout requires a click');
    await click(OVERLAY, 2800);
    await shot('minato');

    // Drive the whole loop from the real save state: counseling sessions, outings, chapters.
    const seen = { map: 0, chapter: new Set(), sessions: new Set(), talks: 0, faced: 0, grown: 0, offers: 0, kept: 0, karte: 0 };
    let save = initial;
    let previous = '';
    const quick = Boolean(process.env.YODAKA_QUICK);
    for (let i = 0; !quick && i < 1200 && save.current !== 'result'; i++) {
      save = await saveRecord(page);
      if (save.pending_word) {
        if (save.pending_step === 'offer') {
          seen.offers++;
          const free = save.slots.includes('');
          if (seen.offers === 1) await shot('word-offer');
          await click(free ? KEEP : RELEASE, 900);
          const decided = await settled(record => record.pending_step === 'kept' || record.pending_step === 'released');
          assert.ok(['kept', 'released'].includes(decided.pending_step), 'Offer decided');
          if (decided.pending_step === 'kept') seen.kept++;
          if (seen.offers === 1) await shot('word-decided');
        }
        await click(OVERLAY, 900);
        await settled(record => !record.pending_word, 3000);
        continue;
      }
      if (save.current === 'map') {
        seen.map++;
        if (seen.map === 1) await shot('map');
        await click(MAP_SLOTS[availableEvent(save)], 900);
        await click(OVERLAY, 900);
        continue;
      }
      if (save.current === 'counseling') {
        seen.sessions.add(save.counsel_session);
        if (save.counsel_step === 'session') {
          const key = `${save.counsel_session}|${save.exp}|${save.talked}|${save.slots.join()}|${JSON.stringify(save.trauma_state)}|${JSON.stringify(save.levels)}`;
          if (key === previous) {
            // Nothing changed since the last action: there is nothing affordable left.
            await click(END_SESSION, 900);
            await settled(record => record.counsel_step !== 'session', 3000);
            previous = '';
            continue;
          }
          previous = key;
          if (seen.sessions.size === 1 && seen.talks === 0) await shot('session');
          const sealed = save.slots.findIndex(entry => entry.startsWith('t:') && !save.trauma_state[entry.slice(2)].loosened);
          if (!save.talked && sealed >= 0) {
            await click(slotPoint(sealed), 500);
            await click(TALK, 900);
            const talking = await settled(record => record.counsel_step === 'talk');
            assert.equal(talking.counsel_step, 'talk', 'Talk starts');
            seen.talks++;
            if (seen.talks === 1) await shot('talk');
            continue;
          }
          const loosened = save.slots.findIndex(entry => entry.startsWith('t:') && save.trauma_state[entry.slice(2)].loosened
            && save.trauma_state[entry.slice(2)].cost <= save.exp);
          if (loosened >= 0) {
            const id = save.slots[loosened].slice(2);
            await click(slotPoint(loosened), 500);
            if (seen.faced === 0) await shot('session-face');
            await click(FACE, 900);
            const faced = await settled(record => record.exp < save.exp);
            assert.ok(faced.exp < save.exp, 'Facing spends EXP');
            assert.ok(!faced.slots.includes('t:' + id) || faced.trauma_state[id].hardness < save.trauma_state[id].hardness, 'Facing softens or removes the trauma');
            seen.faced++;
            await click(OVERLAY, 900);  // dismisses a resolution or surfacing card, otherwise harmless
            continue;
          }
          const growable = save.slots.findIndex(entry => {
            if (!entry.startsWith('w:')) return false;
            const word = scenario.words.find(w => w.id === entry.slice(2));
            const level = save.levels[word.id];
            return level < word.levels.length && word.levels[level].cost <= save.exp;
          });
          if (growable >= 0) {
            const id = save.slots[growable].slice(2);
            await click(slotPoint(growable), 500);
            await click(GROW, 900);
            const grown = await settled(record => record.levels[id] > save.levels[id]);
            assert.equal(grown.levels[id], save.levels[id] + 1, 'Growing raises the level');
            seen.grown++;
            if (seen.grown === 1) await shot('session-grown');
            continue;
          }
          await click(END_SESSION, 900);
          await settled(record => record.counsel_step !== 'session', 3000);
          previous = '';
          continue;
        }
        await click(NEXT, 500);
        await click(OVERLAY, 500);
        const after = await saveRecord(page);
        if (save.counsel_step === 'closing' && save.counsel_session > 0 && after.counsel_step === 'closing') {
          seen.karte++;
          await shot(seen.karte === 1 ? 'karte' : 'karte-final');
          await click(KARTE_CLOSE, 400);
          await click(NEXT, 400);
        }
        continue;
      }
      const node = scenario.nodes[save.current];
      if (node && node.kind === 'main') seen.chapter.add(node.chapter);
      const choices = node && node.choices ? node.choices.length : 0;
      await click(NEXT, 500);
      await click(OVERLAY, 500);  // dismisses a blackout, otherwise advances the finished line
      if (choices > 1) {
        const width = 614 / choices;
        await click([337 + width / 2, 451], 500);
      }
      const after = await saveRecord(page);
      if (node && node.karte && after.current === save.current) {
        seen.karte++;
        await shot(seen.karte === 1 ? 'karte' : 'karte-final');
        await click(KARTE_CLOSE, 400);
        await click(NEXT, 400);
      }
      if (i % 40 === 39) console.log('Playthrough', i + 1, after.current, after.counsel_step, after.round_index, after.exp, after.stats);
    }
    if (!quick) {
    save = await settled(record => record.current === 'result');
    assert.equal(save.current, 'result');
    assert.equal(save.round_index, 4);
    assert.equal(seen.chapter.size, 4, 'All four chapters played');
    assert.equal(seen.map, 6, 'Six outings');
    assert.deepEqual([...seen.sessions].sort(), [0, 1, 2, 3], 'Four counseling sessions');
    assert.equal(seen.talks, 4, 'One trauma talked about per session');
    assert.ok(seen.faced >= 4, 'Traumas were faced');
    assert.ok(save.collected.length >= 8, 'Words heard');
    assert.equal(save.collected.length, seen.offers, 'Every heard word was offered');
    assert.ok(save.resolved.length + save.surfaced.length >= 1, 'The first trauma dissolved or revealed its depth');
    assert.ok(seen.karte >= 3, 'Karte shown in the tutorial and in later sessions');
    assert.ok(save.exp >= 0 && save.exp_total >= 250, 'EXP accumulated over the run');
    assert.equal(save.slots.length, 8);
    for (const id of save.collected) assert.equal(save.gains[id].length, 4);
    await shot('result');
    await page.reload();
    await ready();
    await page.mouse.click(475, 500);
    await page.waitForTimeout(800);
    await shot('resumed');
    assert.equal((await saveRecord(page)).current, 'result');
    }

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
    const common = { ...initial, version: 5, stats: [20, 35, 35, 35], collected: [], gains: {}, history: [],
      pending_word: '', pending_step: '', visited: [], round_index: 0, outings_done: 0, counsel_step: 'opening_doctor',
      counsel_session: 0, talked: false, session_lines: [], levels: {}, exp: 0, exp_total: 0, released: [], resolved: [], surfaced: [] };
    await seed({ ...common, current: 'sushi_10', collected: ['praise'], gains: { praise: [-3, 0, 3, 0] },
      scene_key: '0|寄り道 / 売ったバッシュで寿司を食う|自宅_リビング', pending_word: 'praise', pending_step: 'offer' });
    await shot('received-word');
    await page.keyboard.press('Space');
    await page.keyboard.press('Escape');
    await click(OVERLAY, 800);
    assert.equal((await saveRecord(page)).pending_step, 'offer', 'The offer needs a decision');
    await click(RELEASE, 700);
    const released = await settled(record => record.pending_step === 'released');
    assert.equal(released.pending_step, 'released');
    assert.equal(released.exp, 30, 'Releasing the first word pays its value');
    await click(OVERLAY, 700);
    assert.equal((await settled(record => record.pending_word === '')).pending_word, '');

    await seed({ ...common, current: 'counsel1_10', scene_key: '0|はじめてのカウンセリング|診察室' });
    await click(NEXT, 600);
    await shot('tutorial-choice');
    await click([433, 451], 900);
    const tutorial = await settled(record => record.current === 'counsel1_12');
    assert.equal(tutorial.current, 'counsel1_12');
    assert.deepEqual(tutorial.stats, [20, 35, 37, 35], 'Halved self gain from the classroom air');

    await seed({ ...common, current: 'map', stats: [50, 35, 35, 35] });
    await shot('map-stress');
    await click(MAP_SLOTS[1], 600);
    assert.equal((await settled(record => record.current !== 'map', 1500)).current, 'map', 'Effective stress 80 blocks outings');
    await click(MAP_SLOTS[5], 900);
    assert.equal((await settled(record => record.current === 'rest_0')).current, 'rest_0');

    const gate = scenario.nodes.main4_31;
    const gateScene = `4|${gate.chapter}|${gate.place}`;
    await seed({ ...common, current: 'main4_31', stats: [20, 60, 35, 35], scene_key: gateScene, round_index: 3 });
    await page.waitForTimeout(1400);
    await shot('courage-locked');
    await click([791, 450], 800);
    assert.equal((await settled(record => record.current !== 'main4_31', 1500)).current, 'main4_31', 'Capped courage keeps the choice locked');
    const softened = { ...initial.trauma_state, bash: { hardness: 40, cost: 20, loosened: true } };
    await seed({ ...common, current: 'main4_31', stats: [20, 60, 35, 35], scene_key: gateScene, round_index: 3, trauma_state: softened });
    await page.waitForTimeout(1400);
    await click([791, 450], 2400);
    assert.equal((await settled(record => record.current === 'main4_38')).current, 'main4_38', 'Softened shoes unlock the choice');

    await seed({ ...common, current: 'counseling', counsel_step: 'session', counsel_session: 1, round_index: 1, exp: 60, exp_total: 60,
      talked: true, scene_key: '0|第2回のカウンセリング|診察室', trauma_state: { ...initial.trauma_state, bash: { hardness: 100, cost: 20, loosened: true } } });
    await click(slotPoint(0), 600);
    await shot('session-preview');
    await click(FACE, 1200);
    const faced = await settled(record => record.exp === 40);
    assert.equal(faced.exp, 40);
    assert.equal(faced.trauma_state.bash.hardness, 70, 'Facing softens by thirty');
    await shot('session-faced');

    await page.setViewportSize({ width: 844, height: 390 });
    await page.waitForTimeout(500);
    await shot('mobile');
    fs.writeFileSync(path.join(output, 'verification.json'), JSON.stringify({ errors, seen: { ...seen, chapter: [...seen.chapter], sessions: [...seen.sessions] },
      fullRun: save, faced }, null, 2));
    assert.deepEqual(errors, [], 'No runtime errors');
    if (quick) { console.log('PASS (quick): word offer, tutorial effects, stress lock, courage gate, session facing'); await page.close(); return; }
    console.log(`PASS: full loop (${seen.map} outings, ${seen.sessions.size} sessions, ${seen.talks} talks, ${seen.faced} facings, ${seen.grown} grown, ${save.collected.length} words, ${save.resolved.length} resolved, ${save.surfaced.length} surfaced, EXP ${save.exp_total}), word offer, tutorial effects, stress lock, courage gate, session facing`);
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
