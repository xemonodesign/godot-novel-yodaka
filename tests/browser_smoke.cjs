// Optional integration test: install Playwright and run against `make serve`.
// YODAKA_URL may point at Pages. Uses an isolated browser profile and its own saves.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const scenario = require('../src/data/scenario.json');
const output = process.env.YODAKA_SCREENSHOTS || '/tmp/yodaka-v3-browser';
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

(async () => {
  const browser = await chromium.launch({ channel: 'chrome', headless: true,
    args: ['--no-proxy-server', '--enable-webgl', '--ignore-gpu-blocklist'] });
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
    const shot = name => page.screenshot({ path: path.join(output, `${name}.png`) });
    const ready = async () => {
      await page.locator('#loading').waitFor({ state: 'detached', timeout: 60000 });
      await page.waitForTimeout(700);
    };
    await page.goto(process.env.YODAKA_URL || 'http://127.0.0.1:8060/');
    await ready();
    await shot('title');
    await page.mouse.click(210, 500);
    await page.waitForTimeout(800);
    await shot('chapter');
    const initial = await saveRecord(page);
    assert.equal(initial.scene_key, '');
    await page.keyboard.press('Space');
    await page.keyboard.press('Escape');
    await page.waitForTimeout(800);
    assert.equal((await saveRecord(page)).scene_key, '', 'Blackout requires a click');
    await page.mouse.click(640, 710);
    await page.waitForTimeout(2800);
    await shot('doctor');
    await page.mouse.click(1095, 557);
    await page.waitForTimeout(2800);
    await shot('yodaka');
    let result;
    for (let i = 0; i < 720; i++) {
      await page.mouse.click(1095, 557);
      await page.waitForTimeout(45);
      await page.mouse.click(550, 466);
      await page.waitForTimeout(45);
      if (i % 50 === 49) {
        result = await saveRecord(page);
        console.log('Playthrough', i + 1, result.current, result.counsel_step);
        if (result.current === 'map') await page.mouse.click(365, 455);
        if (result.current === 'result') break;
      }
    }
    await page.waitForTimeout(1000);
    result = await saveRecord(page);
    assert.equal(result.current, 'result');
    assert.equal(result.collected.length, 8);
    assert.equal(result.answers.length, 8);
    for (const answer of result.answers) {
      assert.ok(answer.delta.filter(value => value !== 0).length <= 2);
    }
    await shot('result');
    await page.reload();
    await ready();
    await page.mouse.click(475, 500);
    await page.waitForTimeout(800);
    await shot('resumed');

    // Reuse the real save structure to inspect exact visual states in an isolated profile.
    const seed = async replacement => {
      await saveRecord(page, replacement);
      await page.reload();
      await ready();
      await page.mouse.click(475, 500);
      await page.waitForTimeout(800);
    };
    const common = { ...initial, version: 3, stats: [65, 40, 45, 40, 35, 35],
      collected: scenario.words.map(word => word.id), answers: [], history: [], pending_word: '' };
    await seed({ ...common, current: 'mother_10', collected: ['praise'],
      scene_key: '1|売ったバッシュで寿司を食う|自宅_リビング', pending_word: 'praise' });
    await shot('received-word');
    await page.keyboard.press('Space');
    await page.keyboard.press('Escape');
    await page.waitForTimeout(800);
    assert.equal((await saveRecord(page)).pending_word, 'praise');
    await page.mouse.click(640, 710);
    await page.waitForTimeout(700);
    assert.equal((await saveRecord(page)).pending_word, '');

    await seed({ ...common, current: 'main1_28', collected: [],
      scene_key: '2|tiktokの女王|教室' });
    // Capture the character layout before the marked line finishes and opens its effect.
    await shot('ashika');

    await seed({ ...common, current: 'counseling', counsel_step: 'choice',
      scene_key: '7|今週、僕に残った言葉|診察室' });
    await page.waitForTimeout(600);
    await shot('choice-preview');
    await page.mouse.click(431, 468);
    await page.waitForTimeout(2800);
    const answered = await saveRecord(page);
    assert.equal(answered.counsel_step, 'reply');
    assert.deepEqual(answered.answers[0].delta, [-18, 0, 0, 0, 0, 16]);
    assert.deepEqual(answered.stats, [47, 40, 45, 40, 35, 51]);
    await shot('yodaka-reply');
    await page.reload();
    await ready();
    await page.mouse.click(475, 500);
    await page.waitForTimeout(2000);
    assert.equal((await saveRecord(page)).counsel_step, 'reply');
    await shot('resumed-reply');
    await seed({ ...common, current: 'map', selected_event: '', counsel_return: 'result' });
    await shot('map');
    await page.mouse.click(610, 325);
    await page.waitForTimeout(1000);
    let selected = await saveRecord(page);
    assert.equal(selected.selected_event, 'cafe');
    assert.equal(selected.current, 'map_cafe_6');
    await shot('map-event-chapter');
    await page.mouse.click(640, 710);
    await page.waitForTimeout(2600);
    await shot('cafe');

    await seed({ ...common, current: 'mother_8', collected: [], scene_key: '1|売ったバッシュで寿司を食う|自宅_リビング' });
    await page.waitForTimeout(2000);
    await shot('mother');
    const sumika = scenario.nodes.sumika_6;
    await seed({ ...common, current: 'sumika_6', collected: [], scene_key: `4|${sumika.chapter}|${sumika.place}` });
    await page.waitForTimeout(2000);
    await shot('sumika');

    const gate = scenario.nodes.main4_31;
    const gateScene = `6|${gate.chapter}|${gate.place}`;
    await seed({ ...common, current: 'main4_31', stats: [65, 54, 45, 40, 35, 35], scene_key: gateScene });
    await page.waitForTimeout(1400);
    await shot('courage-locked');
    await page.mouse.click(791, 450);
    await page.waitForTimeout(800);
    assert.equal((await saveRecord(page)).current, 'main4_31');
    await seed({ ...common, current: 'main4_31', stats: [65, 55, 45, 40, 35, 35], scene_key: gateScene });
    await page.waitForTimeout(1400);
    await shot('courage-unlocked');
    await page.mouse.click(791, 450);
    await page.waitForTimeout(2400);
    assert.equal((await saveRecord(page)).current, 'main4_38');

    await page.setViewportSize({ width: 844, height: 390 });
    await page.waitForTimeout(500);
    await shot('mobile');
    fs.writeFileSync(path.join(output, 'verification.json'), JSON.stringify({ errors,
      fullRun: result, selectedReply: answered }, null, 2));
    assert.deepEqual(errors, [], 'No runtime errors');
    console.log('PASS: full run, explicit blackout clicks, 8 words, 8 two-stat answers, previews, MAP, courage gate and reply resume');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
