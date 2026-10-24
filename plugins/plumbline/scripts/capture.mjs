#!/usr/bin/env node
// Takes the screenshots visual-diff.mjs compares, and optionally runs an axe
// accessibility scan, for prototypes and the built app alike, so both sides are
// captured the same way: viewport only, 390x844 and 1280x800, device scale 1,
// animations off, caret hidden, fonts loaded.
//
//   node capture.mjs --out <dir> [--a11y <dir>] [--from <dir>] <screen>=<url> ...
//
// <url> is a full http(s):// or file:// URL, or a path to a local HTML file.
// Playwright is optional: it's looked up (playwright, @playwright/test, then
// playwright-core) from --from (default: current folder), then from
// $CLAUDE_PLUGIN_DATA. axe-core is looked up the same way. The browser is
// Playwright's Chromium, else installed Chrome, else Edge (always present on
// Windows). If nothing is found the script prints SKIPPED with the install
// command and exits 0: a skipped scan must then be waived in qa-report.md.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const VIEWPORTS = [
  { width: 390, height: 844 },
  { width: 1280, height: 800 },
];
const STILL = '*,*::before,*::after{animation:none!important;transition:none!important;caret-color:transparent!important;scroll-behavior:auto!important}';
const WCAG = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'];
const INSTALL = 'npm i -D playwright-core axe-core';

function parseArgs(argv) {
  const opts = { out: null, a11y: null, from: process.cwd(), targets: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--out') opts.out = argv[++i];
    else if (a === '--a11y') opts.a11y = argv[++i];
    else if (a === '--from') opts.from = argv[++i];
    else if (a.includes('=')) {
      const at = a.indexOf('=');
      opts.targets.push({ screen: a.slice(0, at), url: toUrl(a.slice(at + 1)) });
    } else throw new Error(`unexpected argument: ${a}`);
  }
  if (!opts.out || !opts.targets.length) throw new Error('usage: capture.mjs --out <dir> [--a11y <dir>] [--from <dir>] <screen>=<url> ...');
  return opts;
}

// Full URLs pass through. Local paths, including Git Bash's /d/... form, become file:// URLs.
export function toUrl(target) {
  if (/^(https?|file):\/\//i.test(target)) return target;
  let p = target.replace(/^\/([a-zA-Z])\//, (_, d) => `${d.toUpperCase()}:/`);
  return pathToFileURL(path.resolve(p)).href;
}

function lookupDirs(from) {
  const dirs = [from];
  if (process.env.CLAUDE_PLUGIN_DATA) dirs.push(process.env.CLAUDE_PLUGIN_DATA);
  return dirs;
}

function load(names, dirs) {
  for (const dir of dirs) {
    const req = createRequire(path.join(path.resolve(dir), 'noop.js'));
    for (const name of names) {
      try {
        return { mod: req(name), name, dir, req };
      } catch {
        // try the next one
      }
    }
  }
  return null;
}

async function launch(chromium) {
  const attempts = [
    { label: 'Playwright Chromium', opts: {} },
    { label: 'Chrome', opts: { channel: 'chrome' } },
    { label: 'Edge', opts: { channel: 'msedge' } },
  ];
  for (const a of attempts) {
    try {
      return { browser: await chromium.launch({ headless: true, ...a.opts }), label: a.label };
    } catch {
      // not installed; try the next
    }
  }
  return null;
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const dirs = lookupDirs(opts.from);
  const pw = load(['playwright', '@playwright/test', 'playwright-core'], dirs);
  if (!pw) {
    console.log(`SKIPPED: Playwright not found (looked in ${dirs.join(', ')}). Install it in the project with: ${INSTALL}`);
    return;
  }
  let axeSource = null;
  if (opts.a11y) {
    const axe = load(['axe-core/package.json'], dirs);
    if (!axe) console.log(`SKIPPED accessibility: axe-core not found. Install it with: ${INSTALL}`);
    else axeSource = fs.readFileSync(path.join(path.dirname(axe.req.resolve('axe-core/package.json')), 'axe.min.js'), 'utf8');
  }
  const launched = await launch(pw.mod.chromium);
  if (!launched) {
    console.log('SKIPPED: no browser found (Playwright Chromium, Chrome or Edge). Install one with: npx playwright install chromium');
    return;
  }
  console.log(`Browser: ${launched.label} (via ${pw.name})`);
  fs.mkdirSync(opts.out, { recursive: true });
  if (axeSource) fs.mkdirSync(opts.a11y, { recursive: true });
  try {
    for (const vp of VIEWPORTS) {
      const context = await launched.browser.newContext({
        viewport: vp, deviceScaleFactor: 1, bypassCSP: true, reducedMotion: 'reduce',
      });
      for (const t of opts.targets) {
        const page = await context.newPage();
        const name = `${t.screen}-${vp.width}`;
        try {
          await page.goto(t.url, { waitUntil: 'load' });
          await page.addStyleTag({ content: STILL });
          await page.evaluate(() => (document.fonts ? document.fonts.ready.then(() => true) : true));
          await page.screenshot({ path: path.join(opts.out, `${name}.png`), fullPage: false });
          let note = '';
          if (axeSource) {
            await page.evaluate(axeSource);
            const result = await page.evaluate((tags) => window.axe.run(document, { runOnly: { type: 'tag', values: tags } }), WCAG);
            fs.writeFileSync(path.join(opts.a11y, `${name}.json`), JSON.stringify(result, null, 1));
            const count = (impact) => result.violations.filter((v) => v.impact === impact).length;
            note = ` · a11y critical ${count('critical')}, serious ${count('serious')}, moderate ${count('moderate')}, minor ${count('minor')}`;
          }
          console.log(`ok ${name}${note}`);
        } catch (err) {
          console.log(`FAILED ${name}: ${err.message.split('\n')[0]}`);
          process.exitCode = 1;
        } finally {
          await page.close();
        }
      }
      await context.close();
    }
  } finally {
    await launched.browser.close();
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().catch((err) => {
    console.error(`capture: ${err.message}`);
    process.exit(2);
  });
}
