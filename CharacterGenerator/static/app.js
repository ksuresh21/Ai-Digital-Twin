const setupScreen = document.querySelector('#setup-screen');
const promptScreen = document.querySelector('#prompt-screen');
const reviewScreen = document.querySelector('#review-screen');
const buildScreen = document.querySelector('#build-screen');
const form = document.querySelector('#setup-form');
const folderInput = document.querySelector('#folder-input');
let sessionId = null;
let latestState = null;
let latestPrompts = null;
let reimportRequested = false;
const animationTimers = new Map();

function show(screen) {
  [setupScreen, promptScreen, reviewScreen, buildScreen].forEach(el => { el.hidden = el !== screen; });
  window.scrollTo({top: 0, behavior: 'instant'});
}

function selectedSubject() {
  return document.querySelector('input[name="subject-type"]:checked').value;
}

document.querySelectorAll('input[name="subject-type"]').forEach(input => input.addEventListener('change', () => {
  document.querySelectorAll('[data-subject-fields]').forEach(group => {
    group.hidden = group.dataset.subjectFields !== selectedSubject();
  });
}));

document.querySelectorAll('[data-clip]').forEach(box => box.addEventListener('change', updateEstimate));
function updateEstimate() {
  const count = [...document.querySelectorAll('[data-clip]')].filter(box => box.checked).length;
  document.querySelector('#estimate').textContent = `${count + 1} images total`;
}

function currentSheet() {
  const sheet = {};
  document.querySelector(`[data-subject-fields="${selectedSubject()}"]`).querySelectorAll('[data-sheet]').forEach(input => {
    if (input.value.trim()) sheet[input.dataset.sheet] = input.value.trim();
  });
  return sheet;
}

form.addEventListener('submit', async event => {
  event.preventDefault();
  const errorBox = document.querySelector('#setup-error');
  errorBox.hidden = true;
  const clips = [...document.querySelectorAll('[data-clip]')].filter(box => box.checked).map(box => box.dataset.clip);
  if (!clips.includes('idle')) clips.unshift('idle');
  try {
    const response = await fetch('/api/setup', {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({
        name: document.querySelector('#pack-name').value,
        height: Number(document.querySelector('#height').value),
        subjectType: selectedSubject(), sheet: currentSheet(), clips
      })
    });
    const state = await response.json();
    if (!response.ok) throw new Error(state.error || 'Could not prepare prompts');
    sessionId = state.id;
    latestState = state;
    await loadPrompts();
    show(promptScreen);
  } catch (error) {
    errorBox.textContent = error.message;
    errorBox.hidden = false;
  }
});

async function loadPrompts() {
  const response = await fetch(`/api/sessions/${sessionId}/prompts`);
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || 'Could not load prompts');
  latestPrompts = data;
  renderPrompts(latestState, data);
}

function renderPrompts(state, prompts) {
  document.querySelector('#prompt-name').textContent = state.config.name;
  document.querySelector('#reference-prompt').value = prompts.reference;
  const selected = Object.values(state.clips).filter(item => item.status !== 'skipped');
  document.querySelector('#prompt-progress').textContent = `1 reference + ${selected.length} clip sheet${selected.length === 1 ? '' : 's'}`;
  const grid = document.querySelector('#prompt-grid');
  grid.innerHTML = selected.map((item, index) => {
    const id = `prompt-${item.name}`;
    return `<article class="prompt-card compact-prompt">
      <div class="prompt-card-heading"><div><span class="prompt-number">${String(index + 2).padStart(2, '0')}</span><div><h2>${esc(item.name)}</h2><code>${esc(prompts.files.clips[item.name])}</code></div></div><button class="copy-button" data-copy="${id}">Copy prompt</button></div>
      <details><summary>View full prompt</summary><textarea id="${id}" class="prompt-text" readonly spellcheck="false">${esc(prompts.clips[item.name])}</textarea></details>
    </article>`;
  }).join('');
  const names = [prompts.files.reference, ...selected.map(item => prompts.files.clips[item.name])];
  document.querySelector('#expected-files').textContent = `${names.length} expected images`;
  document.querySelector('#filename-list').innerHTML = names.map(name => `<code>${esc(name)}</code>`).join('');
  wireCopyButtons();
}

function wireCopyButtons() {
  document.querySelectorAll('[data-copy]').forEach(button => button.addEventListener('click', async () => {
    const target = document.getElementById(button.dataset.copy);
    const original = button.textContent;
    try {
      await navigator.clipboard.writeText(target.value);
    } catch (_) {
      target.focus(); target.select(); document.execCommand('copy');
    }
    button.textContent = 'Copied ✓';
    setTimeout(() => { button.textContent = original; }, 1400);
  }));
}

folderInput.addEventListener('change', () => {
  const count = folderInput.files.length;
  document.querySelector('#folder-label').textContent = count ? `${count} files selected` : 'Choose generated-images folder';
  document.querySelector('#import-button').disabled = !count;
  if (reimportRequested && count) processFolder();
});

document.querySelector('#import-button').addEventListener('click', processFolder);
async function processFolder() {
  if (!folderInput.files.length || !sessionId) return;
  const button = document.querySelector('#import-button');
  const errorBox = document.querySelector('#import-error');
  errorBox.hidden = true;
  button.disabled = true;
  button.textContent = 'Removing backgrounds and slicing…';
  const body = new FormData();
  [...folderInput.files].forEach(file => body.append('files', file, file.webkitRelativePath || file.name));
  try {
    const response = await fetch(`/api/sessions/${sessionId}/import`, {method: 'POST', body});
    const state = await response.json();
    if (!response.ok) throw new Error(state.error || 'Could not process the selected folder');
    latestState = state;
    renderReview(state);
    show(reviewScreen);
  } catch (error) {
    errorBox.textContent = error.message;
    errorBox.hidden = false;
    if (reimportRequested) show(promptScreen);
  } finally {
    reimportRequested = false;
    button.disabled = !folderInput.files.length;
    button.innerHTML = 'Process selected folder <span>→</span>';
  }
}

function esc(value) {
  const div = document.createElement('div');
  div.textContent = value ?? '';
  return div.innerHTML;
}

function renderReview(state) {
  latestState = state;
  document.querySelector('#review-name').textContent = state.config.name;
  const items = Object.values(state.clips).filter(item => item.status !== 'skipped');
  const ready = items.filter(item => item.status === 'ready').length;
  const failed = items.filter(item => item.status === 'failed').length;
  const missing = items.filter(item => item.status === 'awaiting').length;
  document.querySelector('#progress-text').textContent = `${ready} of ${items.length} ready · ${missing} missing · ${failed} failed`;
  const imported = state.lastImport;
  document.querySelector('#import-summary').textContent = imported?.warnings?.length ? imported.warnings.join(' · ') : 'Folder processed locally';
  const runError = document.querySelector('#run-error');
  runError.hidden = !state.runError;
  runError.textContent = state.runError || '';
  renderReferenceSummary(state);
  animationTimers.forEach(timer => clearInterval(timer));
  animationTimers.clear();
  const grid = document.querySelector('#clip-grid');
  grid.innerHTML = '';
  items.forEach(item => {
    const card = document.createElement('article');
    card.className = 'clip-card';
    card.dataset.card = item.name;
    card.innerHTML = cardMarkup(item, state.lastImport?.importedAt || state.createdAt);
    grid.appendChild(card);
    wireCard(card, item);
  });
  const idleReady = state.clips.idle.status === 'ready' && state.clips.idle.included;
  document.querySelector('#build-button').disabled = !idleReady;
  document.querySelector('#build-hint').textContent = idleReady ? 'Build now, exclude flagged clips, or re-import corrected sheets.' : 'Import a usable idle.png before building.';
}

function renderReferenceSummary(state) {
  const box = document.querySelector('#reference-cleanup');
  if (!state.reference) { box.innerHTML = ''; return; }
  const cleanup = state.referenceCleanup || {};
  const description = cleanup.warning || (cleanup.changed ? `Removed ${Math.round((cleanup.removedFraction || 0) * 100)}% edge-connected background.` : 'Existing transparency preserved.');
  box.innerHTML = `<div><img src="${state.reference}?v=${state.lastImport?.importedAt || ''}" alt="Processed reference"><div><p class="eyebrow">PROCESSED REFERENCE</p><strong>reference.png</strong><span>${esc(description)}</span></div></div><details><summary>Show uploaded original</summary><img src="${state.referenceSource}?v=${state.lastImport?.importedAt || ''}" alt="Original uploaded reference"></details>`;
}

function cardMarkup(item, version) {
  const frames = item.frames || [];
  const qa = (item.qa || []).map(check => `<span class="badge ${check.passed ? 'pass' : 'warn'}" title="${esc(check.reason)}">${check.passed ? '✓' : '!'} ${esc(check.label)}</span>`).join('');
  const frameImages = frames.map((url, i) => `<figure><img src="${url}?v=${version}" alt="${item.name} frame ${i + 1}"><figcaption>${i + 1}</figcaption></figure>`).join('');
  const drift = frames.map(url => `<img src="${url}?v=${version}" alt="">`).join('');
  const failure = item.error ? `<p class="card-error">${esc(item.error)}</p>` : '';
  const waiting = item.status === 'awaiting' ? '<div class="waiting stopped"><span class="stopped-icon" aria-hidden="true">!</span><p>Sheet missing from folder</p></div>' : '<div class="waiting stopped"><span class="stopped-icon" aria-hidden="true">×</span><p>Could not process sheet</p></div>';
  return `<div class="card-title"><div><h2>${esc(item.name)}</h2><span class="status ${item.status}">${esc(item.status === 'awaiting' ? 'missing' : item.status)}</span></div><span class="backend-label">manual</span></div>
    ${failure}
    ${frames.length ? `<div class="frame-strip">${frameImages}</div><div class="previews"><div><small>ANIMATED · 8 FPS</small><div class="animation-stage"><img data-animation src="${frames[0]}?v=${version}"></div></div><div><small>DRIFT VIEW</small><div class="drift-stage">${drift}</div></div></div>` : waiting}
    <div class="badges">${qa}</div>
    ${item.sourceSheet ? `<details><summary>Show uploaded original</summary><img class="original" src="${item.sourceSheet}?v=${version}" alt="Original ${item.name} sheet"></details>` : ''}
    ${item.sheet ? `<details><summary>Show background-cleaned sheet</summary><img class="original checker" src="${item.sheet}?v=${version}" alt="Cleaned ${item.name} sheet"></details>` : ''}
    <div class="card-actions"><span class="processing-note">${esc(item.split?.method || 'waiting for import')}</span><label class="toggle"><input class="include" type="checkbox" ${item.included ? 'checked' : ''} ${item.name === 'idle' || item.status !== 'ready' ? 'disabled' : ''}><span></span> Include</label></div>`;
}

function wireCard(card, item) {
  const include = card.querySelector('.include');
  if (include) include.addEventListener('change', async () => {
    const response = await fetch(`/api/sessions/${sessionId}/clips/${item.name}/include`, {
      method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({included: include.checked})
    });
    const state = await response.json();
    if (response.ok) renderReview(state);
  });
  if (item.frames?.length) {
    let index = 0;
    const image = card.querySelector('[data-animation]');
    animationTimers.set(item.name, setInterval(() => {
      index = (index + 1) % item.frames.length;
      if (image) image.src = `${item.frames[index]}?v=${latestState.lastImport?.importedAt || ''}`;
    }, 125));
  }
}

document.querySelector('#reimport-button').addEventListener('click', () => {
  reimportRequested = true;
  folderInput.value = '';
  folderInput.click();
});

document.querySelector('#build-button').addEventListener('click', async () => {
  const button = document.querySelector('#build-button');
  button.disabled = true;
  button.textContent = 'Building…';
  const response = await fetch(`/api/sessions/${sessionId}/build`, {method: 'POST'});
  const data = await response.json();
  button.innerHTML = 'Build pack <span>↓</span>';
  if (!response.ok) { alert(data.error || 'Build failed'); renderReview(latestState); return; }
  document.querySelector('#download-link').href = data.zip;
  const excluded = data.summary.excluded.map(item => `<li><b>No ${esc(item.clip)}</b> — ${esc(item.fallback)}</li>`).join('');
  document.querySelector('#build-summary').innerHTML = `<p><b>${data.summary.included.length} clips · ${data.summary.frameCount} frames</b> on one ${data.summary.canvas[0]}×${data.summary.canvas[1]} canvas</p>${excluded ? `<h3>Left out</h3><ul>${excluded}</ul>` : '<p>All clips are included.</p>'}<p><a href="${data.report}">Download build report</a></p>`;
  show(buildScreen);
  document.querySelector('#download-link').click();
});

document.querySelector('#back-review').addEventListener('click', () => { renderReview(latestState); show(reviewScreen); });

document.querySelectorAll('.new-character').forEach(button => button.addEventListener('click', async () => {
  await fetch('/api/new', {method: 'POST'});
  sessionId = null; latestState = null; latestPrompts = null; reimportRequested = false;
  animationTimers.forEach(timer => clearInterval(timer)); animationTimers.clear();
  form.reset(); folderInput.value = ''; document.querySelector('#folder-label').textContent = 'Choose generated-images folder';
  document.querySelectorAll('[data-subject-fields]').forEach(group => { group.hidden = group.dataset.subjectFields !== 'human'; });
  updateEstimate(); show(setupScreen);
}));

(async function resume() {
  try {
    const response = await fetch('/api/current');
    const state = await response.json();
    if (!state?.id) return;
    sessionId = state.id; latestState = state;
    if (state.stage === 'review') { renderReview(state); show(reviewScreen); }
    else if (state.stage === 'build' && state.build) { renderReview(state); show(reviewScreen); }
    else { await loadPrompts(); show(promptScreen); }
  } catch (_) {}
})();
