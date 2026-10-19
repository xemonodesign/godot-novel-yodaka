// Optional integration test: install Playwright and run against `make serve`.
// YODAKA_URL may point at Pages. Uses an isolated browser profile and its own saves.
// YODAKA_CHROMIUM points at a Chromium binary; otherwise the "chrome" channel is used.
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
const OVERLAY = [640, 400];
const KARTE_CLOSE = [953, 638];
const SLEEP = [1044, 543];
const KEEP = [930, 286];            // "心に留める" on the receive overlay (with a free slot)
const RELEASE_FREE = [930, 346];    // "手放して EXP" when a slot is free
const RELEASE_FULL = [930, 490];    // "手放して EXP" when the shelf is full
const TALK = [1048, 490];           // "みなとに話す"
const FACE = [216, 505];            // "向き合う" on the board
const GROW = [798, 490];            // "掘り下げる" on the board
const FIRST_CARD = [725, 342];      // first word offered to bring along
const FINISH = [1067, 559];         // "今日は、ここまで"
const COUNSEL_CHOICE = [434, 463];
const boardCard = index => [76 + index * 141 + 66, 216];
const pinPoint = event => [76 + event.pin[0] + 20, 148 + event.pin[1] + 15];
const traumaDef = id => scenario.traumas.find(t => t.id === id);

function availableEvent(save, effectiveStress) {
  const week = save.round_index + 1;
  for (let i = 0; i < scenario.map_events.length; i++) {
    const event = scenario.map_events[i];
    if (event.repeatable) continue;
    if (event.unlock > week || save.visited.includes(event.id) || effectiveStress >= 80) continue;
    return i;
  }
  return scenario.map_events.findIndex(event => event.repeatable);
}

function talkable(save) {
  // The slot index of the first trauma Yodaka may talk about this session.
  return save.slots.findIndex(slot => slot.kind === 'trauma' && !save.traumas[slot.id].resolved
    && (save.session > 1 || !traumaDef(slot.id).deeper));
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
    assert.equal(initial.slots.filter(slot => slot.kind === 'trauma').length, 8, 'Shelf starts full of traumas');
    assert.equal(initial.exp, 0);
    await page.keyboard.press('Space');
    await page.keyboard.press('Escape');
    await page.waitForTimeout(800);
    assert.equal((await saveRecord(page)).scene_key, '', 'Blackout requires a click');
    await click(OVERLAY, 2800);
    await shot('minato');

    // Drive the whole loop from the real save state: counseling, outings, nights, chapters, sessions.
    const seen = { map: 0, night: 0, chapter: new Set(), sessions: [], talks: 0, faced: 0, kept: 0, released: 0, karte: 0, cards: 0 };
    let save = initial;
    let signature = '';
    let stalled = 0;
    for (let i = 0; i < 2400 && save.current !== 'result'; i++) {
      save = await saveRecord(page);
      const next = JSON.stringify([save.current, save.counsel_step, save.read_count, save.exp, save.visited.length, save.pending_word, save.talked, save.session]);
      stalled = next === signature ? stalled + 1 : 0;
      signature = next;
      if (stalled >= 12) {
        await shot('stall');
        throw new Error('Playthrough stalled at ' + next);
      }
      if (save.pending_word) {
        // A word arrived: keep it when a slot is free, otherwise let it go for EXP.
        const free = save.slots.some(slot => !slot.kind);
        if (seen.kept + seen.released === 0) await shot('receive');
        await page.waitForTimeout(600);
        await click(free ? KEEP : RELEASE_FULL, 900);
        const decided = await settled(record => record.pending_word === '');
        assert.equal(decided.pending_word, '', 'Word decided');
        if (free) seen.kept++; else seen.released++;
        continue;
      }
      if (save.current === 'map') {
        seen.map++;
        if (seen.map === 1) await shot('map');
        const stressPlus = save.slots.filter(slot => slot.kind === 'trauma').reduce((sum, slot) => {
          const def = traumaDef(slot.id);
          return sum + (def.debuff.kind === 'plus' ? Math.ceil(def.debuff.value * save.traumas[slot.id].strength / def.strength) : 0);
        }, 0);
        await click(pinPoint(scenario.map_events[availableEvent(save, save.stats[0] + stressPlus)]), 900);
        await settled(record => record.current !== 'map');
        await click(OVERLAY, 900);
        continue;
      }
      if (save.current === 'night') {
        seen.night++;
        await page.waitForTimeout(3400);  // the darkening intro
        await click(OVERLAY, 600);
        if (seen.night === 1) await shot('night');
        await click(SLEEP, 900);  // the map, a chapter card or a session follows; the next pass handles it
        await settled(record => record.current !== 'night');
        continue;
      }
      if (save.current === 'counseling' && save.counsel_step === 'board') {
        if (!seen.sessions.includes(save.session)) seen.sessions.push(save.session);
        if (!save.talked) {
          const index = talkable(save);
          assert.ok(index >= 0, 'Something to talk about');
          await click(boardCard(index), 500);
          if (save.slots.some(slot => slot.kind === 'word')) {
            await click(FIRST_CARD, 400);  // bring the first held word along
            seen.cards++;
          }
          if (seen.talks === 0) await shot('board');
          await click(TALK, 900);
          const talked = await settled(record => record.talked);
          assert.ok(talked.talked, 'Talked about ' + save.slots[index].id);
          seen.talks++;
          continue;
        }
        const affordable = save.slots.findIndex(slot => slot.kind === 'trauma' && save.traumas[slot.id].unraveled
          && Math.ceil(save.traumas[slot.id].cost * save.traumas[slot.id].strength / traumaDef(slot.id).strength) <= save.exp);
        if (affordable >= 0) {
          await click(boardCard(affordable), 500);
          await click(FACE, 900);
          const faced = await settled(record => record.traumas[save.slots[affordable].id].resolved);
          assert.ok(faced.traumas[save.slots[affordable].id].resolved, 'Faced ' + save.slots[affordable].id);
          seen.faced++;
          continue;
        }
        await click(FINISH, 900);
        await settled(record => record.counsel_step !== 'board');
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
      if ((node && node.karte) || (save.current === 'counseling' && save.counsel_step === 'closing' && save.round_index >= scenario.rounds.length)) {
        if (after.current === save.current && after.counsel_step === save.counsel_step) {
          seen.karte++;
          await shot(seen.karte === 1 ? 'karte' : 'karte-final');
          await click(KARTE_CLOSE, 400);
          await click(NEXT, 400);
        }
      }
      if (i % 40 === 39) console.log('Playthrough', i + 1, after.current, after.counsel_step, after.round_index, after.exp, after.stats);
    }
    save = await settled(record => record.current === 'result');
    assert.equal(save.current, 'result');
    assert.equal(save.round_index, 4);
    assert.equal(save.session, 4, 'Four counseling sessions');
    assert.deepEqual(seen.sessions, [1, 2, 3, 4], 'Sessions in order');
    assert.equal(seen.chapter.size, 4, 'All four chapters played');
    assert.equal(seen.map, 12, 'Twelve outings');
    assert.equal(seen.night, 16, 'A night after every outing and chapter');
    assert.equal(seen.talks, 4, 'One trauma talked about per session');
    assert.ok(seen.faced >= 1, 'At least the first trauma faced');
    assert.ok(save.collected.length >= 3, 'Words received');
    assert.equal(seen.kept + seen.released, save.collected.length, 'Every word was decided');
    assert.ok(save.exp_total >= save.read_count, 'EXP for every tap');
    for (const id of Object.keys(save.traumas)) {
      assert.equal(save.traumas[id].resolved, !save.slots.some(slot => slot.id === id), 'Unresolved traumas stay on the shelf');
    }
    for (const id of [...save.forgotten, ...save.used]) assert.ok(!save.slots.some(slot => slot.id === id), 'Words let go left the shelf');
    assert.ok(seen.karte >= 2, 'Karte shown in the tutorial and the closing');
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
    const common = { ...initial, version: 5, stats: [60, 5, 5, 5], collected: [], gains: {}, answers: [], history: [],
      pending_word: '', visited: [], round_index: 0, outings_done: 0, after_night: 'map', forgotten: [], used: [],
      exp: 0, exp_total: 0, exp_day: 0, levels: {}, session: 0, counsel_step: 'opening_doctor', talked: false,
      focus: '', cards: [], grow_word: '', talk_result: {} };
    const freed = (base, ids) => {
      // A copy of a save with the given traumas faced, their slots empty.
      const traumas = JSON.parse(JSON.stringify(base.traumas));
      const slots = base.slots.map(slot => ids.includes(slot.id) ? {} : slot);
      for (const id of ids) traumas[id] = { ...traumas[id], resolved: true, strength: 0, unraveled: true };
      return { ...base, traumas, slots };
    };
    // A received word must be kept or let go; the dark does not dismiss it.
    await seed({ ...freed(common, ['coworker']), current: 'cafe_7', collected: ['miracle'], gains: { miracle: [0, 5, 2, 0] },
      scene_key: '0|寄り道 / 奇跡を待つ人|喫茶店', pending_word: 'miracle' });
    await shot('received-word');
    await page.keyboard.press('Space');
    await page.keyboard.press('Escape');
    await click(OVERLAY, 800);
    assert.equal((await saveRecord(page)).pending_word, 'miracle', 'Undecided word stays');
    await click(KEEP, 700);
    const kept = await settled(record => record.pending_word === '');
    assert.equal(kept.pending_word, '');
    assert.ok(kept.slots.some(slot => slot.kind === 'word' && slot.id === 'miracle'), 'Kept word on the shelf');
    await seed({ ...common, current: 'sumika_10', collected: ['happiness'], gains: { happiness: [2, 0, 6, 0] },
      scene_key: '0|寄り道 / 自由と権利|ファミレス(昼)', pending_word: 'happiness' });
    await shot('received-full');
    await click(RELEASE_FULL, 700);
    const released = await settled(record => record.pending_word === '');
    assert.equal(released.exp, 15, 'Letting go pays half under the discount trauma');
    assert.deepEqual(released.forgotten, ['happiness']);

    await seed({ ...common, current: 'counsel1_10', scene_key: '0|はじめてのカウンセリング|診察室' });
    await click(NEXT, 600);
    await shot('tutorial-choice');
    await click([433, 451], 900);
    const tutorial = await settled(record => record.current === 'counsel1_12');
    assert.equal(tutorial.current, 'counsel1_12');
    assert.deepEqual(tutorial.stats, [60, 5, 9, 5]);
    assert.equal(tutorial.exp, 1, 'The line read earned one EXP');

    // Stress 72 reads as 80 under the trauma: only home is pinned.
    await seed({ ...common, current: 'map', stats: [72, 5, 5, 5] });
    await shot('map-stress');
    await click(pinPoint(scenario.map_events[1]), 600);
    assert.equal((await settled(record => record.current !== 'map', 1500)).current, 'map', 'High stress hides outings');
    await click(pinPoint(scenario.map_events[scenario.map_events.length - 1]), 900);
    assert.equal((await settled(record => record.current === 'rest_0')).current, 'rest_0');

    // The courage gate through the cap: fifteen is not enough while the trauma stands.
    const gate = scenario.nodes.main4_31;
    const gateScene = `4|${gate.chapter}|${gate.place}`;
    await seed({ ...common, current: 'main4_31', stats: [60, 15, 5, 5], scene_key: gateScene, round_index: 3 });
    await page.waitForTimeout(1400);
    await shot('courage-locked');
    await click([791, 450], 800);
    assert.equal((await settled(record => record.current !== 'main4_31', 1500)).current, 'main4_31');
    await seed({ ...freed(common, ['no_longer']), current: 'main4_31', stats: [60, 15, 5, 5], scene_key: gateScene, round_index: 3 });
    await page.waitForTimeout(1400);
    await click([791, 450], 2400);
    assert.equal((await settled(record => record.current === 'main4_38')).current, 'main4_38');

    // A session board: bring a word along, then grow another.
    const board = freed(common, ['handle', 'normal']);
    board.slots[0] = { kind: 'word', id: 'miracle' };
    board.slots[2] = { kind: 'word', id: 'queen' };
    await seed({ ...board, current: 'counseling', collected: ['miracle', 'queen'], gains: { miracle: [0, 5, 2, 0], queen: [3, 0, 0, 6] },
      session: 2, counsel_step: 'board', exp: 300, round_index: 1, scene_key: '0|2回目のカウンセリング|診察室' });
    await click(boardCard(1), 500);  // もう男じゃないんだし
    await click(FIRST_CARD, 400);    // 「奇跡」 resonates with the body
    await shot('board-talk');
    await click(TALK, 900);
    const talked = await settled(record => record.talked);
    assert.equal(talked.traumas.no_longer.strength, 70, 'Talk plus a resonant word: minus thirty');
    assert.deepEqual(talked.used, ['miracle']);
    assert.equal(talked.counsel_step, 'talk_recall');
    await shot('talk-recall');
    // Each click completes a line or advances it; poll rather than count, so no click lands on the board.
    const advanceUntil = async step => {
      for (let i = 0; i < 12 && (await saveRecord(page)).counsel_step !== step; i++) await click(NEXT, 700);
      return settled(record => record.counsel_step === step);
    };
    const back = await advanceUntil('board');
    assert.equal(back.counsel_step, 'board');
    await click(boardCard(2), 500);  // 「女王」
    await shot('board-word');
    await click(GROW, 900);
    const growing = await settled(record => record.counsel_step === 'grow_question');
    assert.equal(growing.levels.queen, 2);
    await advanceUntil('grow_choice');
    await click(NEXT, 600);
    await shot('choice-preview');
    await click(COUNSEL_CHOICE, 2800);
    const answered = await settled(record => record.counsel_step === 'grow_reply');
    assert.equal(answered.counsel_step, 'grow_reply');
    assert.deepEqual(answered.answers[0].delta, [0, 6, 0, 6]);
    await shot('yodaka-reply');

    await page.setViewportSize({ width: 844, height: 390 });
    await page.waitForTimeout(500);
    await shot('mobile');
    fs.writeFileSync(path.join(output, 'verification.json'), JSON.stringify({ errors, seen: { ...seen, chapter: [...seen.chapter] },
      fullRun: save, answered }, null, 2));
    assert.deepEqual(errors, [], 'No runtime errors');
    console.log(`PASS: full loop (${seen.map} outings, ${seen.night} nights, ${seen.sessions.length} sessions, ${seen.talks} talks, ${seen.faced} faced, ${seen.kept} kept, ${seen.released} let go, EXP ${save.exp}/${save.exp_total}), receive overlay, tutorial effects, stress through trauma, courage cap, board talk and growth`);
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
