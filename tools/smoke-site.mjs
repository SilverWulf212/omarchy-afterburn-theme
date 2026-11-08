#!/usr/bin/env node
// Real Chromium smoke. Requires an existing playwright-core installation; installs nothing.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

const [target, output = `afterburn-browser-smoke-${Date.now()}`] = process.argv.slice(2);
if (!target || !/^https?:\/\//.test(target)) {
  console.error('Usage: node tools/smoke-site.mjs URL [ARTIFACT_DIRECTORY]');
  process.exit(2);
}
const url = new URL(target);
const artifacts = path.resolve(output);
await mkdir(artifacts, { recursive: true });
const result = { url: url.href, started: new Date().toISOString(), status: 'running', checks: [], pageErrors: [], sameOriginFailures: [], externalFailures: [], cancelledRequests: [] };
let browser, activePage;
const check = async (name, fn) => {
  await fn();
  result.checks.push(name);
  console.log(`PASS ${name}`);
};
function observe(page) {
  page.on('pageerror', error => result.pageErrors.push(String(error)));
  const failure = (address, details) => {
    const record = { url: address, details };
    (new URL(address).origin === url.origin ? result.sameOriginFailures : result.externalFailures).push(record);
  };
  page.on('requestfailed', request => {
    // Chromium cancels in-flight resources on explicit page reloads and video
    // range transfers on scrolling. Navigation failures still reject goto/reload.
    // Completed HTTP errors still count even for videos.
    if (request.failure()?.errorText === 'net::ERR_ABORTED') {
      result.cancelledRequests.push(request.url());
      return;
    }
    failure(request.url(), request.failure()?.errorText);
  });
  page.on('response', response => {
    if (response.status() >= 400) failure(response.url(), `HTTP ${response.status()}`);
  });
}
async function pressed(page, selector, expected) {
  await page.waitForFunction(({ selector, expected }) => document.querySelector(selector)?.getAttribute('aria-pressed') === String(expected), { selector, expected });
}
try {
  const require = createRequire(import.meta.url);
  const { chromium } = require(process.env.PW_MODULE_PATH || 'playwright-core');
  browser = await chromium.launch({
    headless: true,
    ...(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {}),
    args: process.env.PW_NO_SANDBOX === '1' ? ['--no-sandbox'] : [],
  });
  const desktop = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  await desktop.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: url.origin });
  const page = await desktop.newPage();
  activePage = page;
  observe(page);
  page.setDefaultTimeout(10000);
  await page.goto(url.href, { waitUntil: 'domcontentloaded' });
  await check('page initializes six editions and eight swatches', async () => {
    await page.waitForFunction(() => document.querySelectorAll('#edRow button').length === 6 && document.querySelectorAll('#swatches button').length === 8);
    assert.match(await page.title(), /afterburn/i);
  });
  const accents = new Set();
  for (const edition of ['afterburn', 'voltage', 'cyber', 'overdrive', 'redline', 'phantom']) {
    await check(`${edition}: edition selection, palette and hash survive reload`, async () => {
      const selector = `#edRow [data-ed-pick="${edition}"]`;
      await page.locator(selector).click();
      await pressed(page, selector, true);
      assert.equal(new URL(page.url()).hash, `#${edition}`);
      accents.add(await page.locator('#swatches button').first().getAttribute('data-hex'));
      await page.reload({ waitUntil: 'domcontentloaded' });
      await pressed(page, selector, true);
    });
  }
  assert.equal(accents.size, 6, 'all editions need distinct palette accents');
  await check('wallpaper button and keyboard shortcut change desktop', async () => {
    const background = () => page.locator('#wpbg').getAttribute('style');
    const first = await background();
    await page.locator('#tNext').click();
    assert.notEqual(await background(), first);
    const second = await background();
    await page.keyboard.press('Control+Space');
    assert.notEqual(await background(), second);
  });
  await check('terminal handles help and rejects unknown commands', async () => {
    await page.locator('#termInput').fill('help');
    await page.locator('#termInput').press('Enter');
    assert.match(await page.locator('#termOut').innerText(), /commands.*fastfetch/);
    await page.locator('#termInput').fill('smoke-unknown-command');
    await page.locator('#termInput').press('Enter');
    assert.match(await page.locator('#termOut').innerText(), /command not found.*smoke-unknown-command/);
  });
  await check('clipboard contains real install command and selected swatch', async () => {
    await page.locator('[data-copy-install]').first().click();
    await page.waitForFunction(async () => /omarchy theme install/.test(await navigator.clipboard.readText()));
    assert.match(await page.evaluate(() => navigator.clipboard.readText()), /omarchy theme install https:\/\/github.com\/silverwulf212\/omarchy-afterburn-theme/i);
    const swatch = page.locator('#swatches button').first();
    const hex = await swatch.getAttribute('data-hex');
    await swatch.click();
    await page.waitForFunction(async expected => (await navigator.clipboard.readText()) === expected, hex);
    assert.equal(await page.evaluate(() => navigator.clipboard.readText()), hex);
  });
  await check('installer simulation aborts and completes with undo guidance', async () => {
    await page.locator('#installer .ask button').filter({ hasText: /^No$/ }).click();
    assert.match(await page.locator('#installer').innerText(), /nothing changed/i);
    await page.locator('#installer button').filter({ hasText: /^Run again$/ }).click();
    let steps = 0;
    while (await page.locator('#installer .ask button').filter({ hasText: /^Yes$/ }).count()) {
      assert.ok(steps++ < 20, 'simulation did not terminate');
      await page.locator('#installer .ask button').filter({ hasText: /^Yes$/ }).click();
    }
    assert.ok(steps >= 8, 'simulation omitted installation decisions');
    assert.match(await page.locator('#installer').innerText(), /undo:.*uninstall\.sh/i);
    assert.equal(await page.locator('#installer button').filter({ hasText: /^Run again$/ }).count(), 1);
  });
  await check('edition preview loads when scrolled into view', async () => {
    const preview = page.locator('.ed-card video').first();
    await preview.scrollIntoViewIfNeeded();
    await page.waitForFunction(() => document.querySelector('.ed-card video')?.readyState >= 1);
  });
  await page.screenshot({ path: path.join(artifacts, 'desktop.png'), fullPage: true, timeout: 15000 });
  const mobile = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, reducedMotion: 'reduce' });
  const small = await mobile.newPage();
  activePage = small;
  observe(small);
  small.setDefaultTimeout(10000);
  await small.goto(url.href, { waitUntil: 'domcontentloaded' });
  await check('mobile edition controls work without document overflow', async () => {
    await small.locator('#edRow [data-ed-pick="cyber"]').click();
    await pressed(small, '#edRow [data-ed-pick="cyber"]', true);
    const dimensions = await small.evaluate(() => ({ content: document.documentElement.scrollWidth, viewport: innerWidth }));
    assert.ok(dimensions.content <= dimensions.viewport + 1, `horizontal overflow: ${JSON.stringify(dimensions)}`);
  });
  await check('reduced motion leaves automatic embers and preview videos off', async () => {
    await pressed(small, '#tEmbers', false);
    await small.locator('.ed-card video').first().scrollIntoViewIfNeeded();
    assert.equal(await small.locator('.ed-card video[src]').count(), 0);
  });
  await small.screenshot({ path: path.join(artifacts, 'mobile-reduced-motion.png'), fullPage: true, timeout: 15000 });
  await check('no JavaScript errors or failed requested same-origin assets', async () => {
    assert.deepEqual(result.pageErrors, []);
    assert.deepEqual(result.sameOriginFailures, []);
  });
  result.status = 'passed';
} catch (error) {
  result.status = 'failed';
  result.error = String(error.stack || error);
  console.error(result.error);
  if (activePage) {
    try { await activePage.screenshot({ path: path.join(artifacts, 'failure.png'), timeout: 5000 }); }
    catch { /* Preserve the original error even when the page has crashed. */ }
  }
  process.exitCode = 1;
} finally {
  if (browser) await browser.close();
  result.finished = new Date().toISOString();
  await writeFile(path.join(artifacts, 'result.json'), `${JSON.stringify(result, null, 2)}\n`);
  console.log(`${result.status.toUpperCase()}: ${artifacts}`);
  if (result.externalFailures.length) console.log(`External CDN/network failures recorded separately: ${result.externalFailures.length}`);
}
