// Serbian Cards — frontend
// Single-file SPA. State machine + global hotkeys.

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

const state = {
  screen: 'home',
  config: null,
  session: null,            // {id, mode, card, hud, finished}
  flipped: false,           // back side shown?
  alphabet: 'both',         // 'cyr' | 'lat' | 'both'
  showTranslation: false,
  showExample: false,
  typingMode: false,
  typingResult: null,       // {distance, suggested_grade, ...}
  pendingPreview: null,     // for add-words flow
  refiningImage: new Set(), // word ids whose image is currently being refetched
  regenExample: new Set(),  // word ids whose example is currently being regenerated
  classifying: new Set(),   // word ids whose pos/verb_group is being recomputed
  conjugating: new Set(),   // word ids whose conjugations are being recomputed
  learnPanelOpen: false,
};

const PRONOUN_LABELS = {
  '1sg': 'ja',
  '2sg': 'ти',
  '3sg': 'он/она',
  '1pl': 'ми',
  '2pl': 'ви',
  '3pl': 'они/оне',
};

// ---- API helpers ----
async function api(method, url, body) {
  const opts = { method, headers: {} };
  if (body !== undefined) {
    if (body instanceof FormData) { opts.body = body; }
    else { opts.headers['Content-Type'] = 'application/json'; opts.body = JSON.stringify(body); }
  }
  const r = await fetch(url, opts);
  if (!r.ok) {
    const text = await r.text().catch(() => '');
    throw new Error(`${method} ${url} → ${r.status}: ${text}`);
  }
  return r.status === 204 ? null : r.json();
}

// ---- Screen routing ----
function showScreen(name) {
  $$('.screen').forEach(s => s.removeAttribute('data-active'));
  const el = $(`.screen[data-screen="${name}"]`);
  if (el) el.setAttribute('data-active', '');
  state.screen = name;
}

// ---- Toast ----
let toastTimer = null;
function toast(msg, ms = 2500) {
  const t = $('#toast');
  t.textContent = msg;
  t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.hidden = true, ms);
}

// ---- Home ----
async function loadHome() {
  try {
    const s = await api('GET', '/api/stats');
    $('#count-new').textContent = s.new;
    $('#count-due').textContent = s.due;
    $('#count-total').textContent = s.total;
  } catch (e) { toast('Не удалось загрузить статистику'); console.error(e); }
  try {
    const a = await api('GET', '/api/sessions/active');
    const row = $('#resume-banner');
    if (a.sessions?.length) {
      const s = a.sessions[0];
      state.resumeId = s.id;
      $('#resume-meta').textContent = `(${s.mode}, осталось ~${s.remaining})`;
      row.hidden = false;
    } else {
      row.hidden = true;
      state.resumeId = null;
    }
  } catch (e) { console.error(e); }
}

async function resumeSession() {
  if (!state.resumeId) return;
  try {
    const sess = await api('GET', `/api/sessions/${state.resumeId}`);
    state.session = sess;
    state.flipped = false;
    state.showTranslation = false;
    state.showExample = false;
    state.typingMode = state.config?.typing_mode_enabled || false;
    showScreen('session');
    renderCard();
  } catch (e) { toast('Не удалось продолжить: ' + e.message); }
}

// ---- Session ----
async function startSession(mode, size) {
  try {
    const body = { mode };
    if (size != null) body.size = size;
    const sess = await api('POST', '/api/sessions/start', body);
    state.session = sess;
    state.flipped = false;
    state.showTranslation = false;
    state.showExample = false;
    state.typingMode = state.config?.typing_mode_enabled || false;
    showScreen('session');
    renderCard();
  } catch (e) { toast(e.message); }
}

function renderCard() {
  const sess = state.session;
  if (!sess) return;
  // HUD
  $('#hud-good').textContent = sess.hud.good;
  $('#hud-again').textContent = sess.hud.again;
  $('#hud-acc').textContent = Math.round((sess.hud.accuracy || 0) * 100) + '%';
  $('#hud-pos').textContent = sess.hud.position;
  $('#hud-total').textContent = sess.hud.total;
  $('#hud-mode').textContent = sess.mode === 'learn' ? 'новые' : 'повтор';

  // Progress strip above the card (both modes)
  const lp = sess.hud.learn_progress;
  const strip = $('#learn-progress-strip');
  const eyeBtn = strip.querySelector('.hud-eye');
  if (sess.mode === 'learn' && lp) {
    const pct = lp.max_correct ? lp.total_correct / lp.max_correct * 100 : 0;
    $('#learn-streak-fill').style.width = pct.toFixed(1) + '%';
    $('#learn-streak-text').textContent =
      `${lp.total_correct} / ${lp.max_correct} правильных подряд · ` +
      `выучено ${lp.completed_words}/${lp.total_words} · ` +
      `осталось ${lp.remaining_words}`;
    if (eyeBtn) eyeBtn.hidden = false;
    strip.hidden = false;
    renderLearnPanel(lp);
  } else if (sess.mode === 'review' && sess.hud.total > 0) {
    const pos = sess.hud.position, tot = sess.hud.total;
    const pct = tot ? pos / tot * 100 : 0;
    $('#learn-streak-fill').style.width = pct.toFixed(1) + '%';
    const acc = Math.round((sess.hud.accuracy || 0) * 100);
    $('#learn-streak-text').textContent =
      `${pos} / ${tot} карточек · ` +
      `точность ${acc}% · ` +
      `осталось ${tot - pos}`;
    if (eyeBtn) eyeBtn.hidden = true;
    strip.hidden = false;
    state.learnPanelOpen = false;
    $('#learn-panel').hidden = true;
  } else {
    strip.hidden = true;
    state.learnPanelOpen = false;
    $('#learn-panel').hidden = true;
  }

  if (sess.finished || !sess.card) {
    finishSession();
    return;
  }

  const w = sess.card.word;

  // Alphabet display class on body
  document.body.classList.remove('alphabet-cyr', 'alphabet-lat', 'alphabet-both');
  document.body.classList.add('alphabet-' + state.alphabet);

  // Image is shared between front and back. Always update its src
  // (so refind-image reflects immediately, even if flipped).
  const cardImage = $('#card-image');
  if (w.image_url) {
    cardImage.src = w.image_url;
    cardImage.style.display = '';
  } else {
    cardImage.removeAttribute('src');
    cardImage.style.display = 'none';
  }

  // Spinner over the image when an in-flight refind/regen targets THIS word
  const spinner = $('#image-spinner');
  const spinnerText = $('#spinner-text');
  if (state.refiningImage.has(w.id)) {
    spinner.hidden = false;
    spinnerText.textContent = 'Ищу картинку…';
  } else if (state.regenExample.has(w.id)) {
    spinner.hidden = false;
    spinnerText.textContent = 'Генерирую пример…';
  } else {
    spinner.hidden = true;
  }

  // Front: translation under image
  $('#card-front-main').textContent = w.translation || '(нет перевода)';

  // Back: Serbian word under image
  $('#card-word').innerHTML = wordHtml(w);

  // Verb group tag (under Serbian word on the back)
  const verbTag = $('#verb-tag');
  if (w.pos === 'verb' && w.verb_group) {
    const isIrreg = w.verb_group === 'irregular';
    verbTag.classList.toggle('irregular', isIrreg);
    verbTag.innerHTML = isIrreg
      ? `глагол · <span class="grp">неправильный</span>`
      : `глагол · <span class="grp">${escape(w.verb_group)}</span> группа`;
    verbTag.hidden = false;
  } else {
    verbTag.hidden = true;
  }

  // Verb-classification controls
  const classifying = state.classifying.has(w.id);
  const conjugating = state.conjugating.has(w.id);
  $('#verb-spinner').hidden = !classifying;
  $('#conj-spinner').hidden = !conjugating;
  $$('#verb-controls .verb-btn').forEach(b => { b.disabled = classifying || conjugating; });
  // Regen-conjugations button only relevant for verbs
  $('#regen-conjugations-btn').hidden = !(w.pos === 'verb');

  // Conjugation table — side panel; only when flipped and word is a verb
  const cs = $('#conjugation-side');
  const ct = $('#conjugation-table');
  if (state.flipped && w.pos === 'verb' && w.conjugations) {
    renderConjugationTable(ct, w.conjugations);
    cs.hidden = false;
  } else {
    cs.hidden = true;
  }
  $('#text-translation').textContent = w.translation || '(нет перевода)';
  $('#text-example').textContent = exampleForAlphabet(w);
  $('#text-example-translation').textContent = w.example_translation || '';

  // Show/hide front/back text blocks (image stays put)
  $('#card-text-front').hidden = state.flipped;
  $('#card-text-back').hidden = !state.flipped;

  // Toggle states for translation/example on the back
  $('#meta-translation').hidden = !state.showTranslation;
  $('#meta-example').hidden = !state.showExample;

  // Typing box (only on front side, when typing mode is on)
  $('#typing-box').hidden = !(state.typingMode && !state.flipped);
  $('#typing-input').value = '';
  $('#typing-result').textContent = '';
  $('#typing-result').className = 'typing-result';

  // toolbar active states
  $$('.toolbar button').forEach(b => b.classList.remove('active'));
  if (state.showTranslation) $('button[data-action="toggle-translation"]').classList.add('active');
  if (state.showExample) $('button[data-action="toggle-example"]').classList.add('active');
  if (state.typingMode) $('button[data-action="toggle-typing"]').classList.add('active');
}

function wordHtml(w) {
  if (state.alphabet === 'cyr') return escape(w.word_cyr);
  if (state.alphabet === 'lat') return escape(w.word_lat);
  return `${escape(w.word_cyr)}<div class="alt">${escape(w.word_lat)}</div>`;
}

function exampleForAlphabet(w) {
  if (state.alphabet === 'cyr') return w.example_cyr || '';
  if (state.alphabet === 'lat') return w.example_lat || '';
  return (w.example_cyr || '') + (w.example_lat ? `\n${w.example_lat}` : '');
}

function escape(s) {
  return (s || '').replace(/[&<>"]/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[ch]));
}

function renderLearnPanel(lp) {
  const panel = $('#learn-panel');
  panel.hidden = !state.learnPanelOpen;
  if (panel.hidden) return;

  const list = $('#learn-panel-list');
  list.innerHTML = lp.words.map(w => {
    const pips = Array.from({length: lp.threshold}, (_, i) =>
      `<span class="pip ${i < w.correct_count ? 'filled' : ''}"></span>`
    ).join('');
    const thumb = w.image_url
      ? `<div class="thumb"><img src="${escape(w.image_url)}" loading="lazy" alt=""></div>`
      : `<div class="thumb"></div>`;
    return `
      <div class="learn-row${w.completed ? ' mastered' : ''}">
        ${thumb}
        <div class="name">${escape(w.word_cyr || w.word_lat)}<span class="tr">${escape(w.translation || '')}</span></div>
        <div class="pips">${pips}<span style="margin-left:6px;color:var(--fg-dim)">${w.correct_count}/${lp.threshold}</span></div>
      </div>
    `;
  }).join('');
}

function toggleLearnPanel() {
  state.learnPanelOpen = !state.learnPanelOpen;
  if (state.session?.hud?.learn_progress) {
    renderLearnPanel(state.session.hud.learn_progress);
  }
}

function flip() {
  if (!state.session?.card) return;
  state.flipped = true;
  // Defocus typing input so 1/2/3 hotkeys won't be eaten by it
  if (document.activeElement?.tagName === 'INPUT' || document.activeElement?.tagName === 'TEXTAREA') {
    document.activeElement.blur();
  }
  renderCard();
}

async function answer(grade) {
  if (!state.session?.card) return;
  try {
    const sess = await api('POST', `/api/sessions/${state.session.id}/answer`, {
      grade, direction: state.session.card.direction,
      typed_input: $('#typing-input')?.value || null,
    });
    state.session = sess;
    state.flipped = false;
    state.typingResult = null;
    renderCard();
  } catch (e) { toast(e.message); }
}

async function exitSession() {
  if (!state.session) { showScreen('home'); loadHome(); return; }
  try {
    const summary = await api('POST', `/api/sessions/${state.session.id}/end`);
    showSessionEnd(summary);
  } catch (e) {
    toast(e.message);
    showScreen('home'); loadHome();
  }
}

async function finishSession() {
  if (!state.session) return;
  await exitSession();
}

function showSessionEnd(summary) {
  const m = $('#end-main');
  const s = summary.summary;
  m.innerHTML = `
    <div class="end-stat"><span>Показано</span><span>${s.shown}</span></div>
    <div class="end-stat"><span>Угадано</span><span style="color:var(--good)">${s.good + s.hard}</span></div>
    <div class="end-stat"><span>Hard</span><span style="color:var(--hard)">${s.hard}</span></div>
    <div class="end-stat"><span>Не угадано</span><span style="color:var(--again)">${s.again}</span></div>
    <div class="end-stat"><span>Точность</span><span>${Math.round(s.accuracy*100)}%</span></div>
    <div class="end-stat"><span>Стало выученных</span><span>${s.new_mastered}</span></div>
    ${s.hardest?.length ? `
      <h3>Слова с ошибками</h3>
      <ul class="hardest-list">
        ${s.hardest.map(h => `<li>${escape(h.word_cyr)} <span style="color:var(--fg-dim)">/ ${escape(h.word_lat)}</span> — ${h.again_count}×</li>`).join('')}
      </ul>` : ''}
    <div class="end-actions">
      <button class="primary" id="end-again">Ещё одну сессию</button>
      <button class="back" id="end-home">На главный</button>
    </div>
  `;
  $('#end-again').onclick = () => startSession(summary.mode);
  $('#end-home').onclick = () => { state.session = null; showScreen('home'); loadHome(); };
  state.session = null;
  showScreen('session-end');
}

// ---- Toolbar actions ----
async function speak() {
  const w = state.session?.card?.word;
  if (!w?.audio_url) { toast('Аудио не сгенерировано'); return; }
  const a = new Audio(w.audio_url);
  a.play().catch(e => toast('Не удалось проиграть: ' + e.message));
}

function toggleTranslation() { state.showTranslation = !state.showTranslation; renderCard(); }
function toggleExample()     { state.showExample = !state.showExample; renderCard(); }
function toggleTyping()      { state.typingMode = !state.typingMode; renderCard(); }

function cycleAlphabet() {
  state.alphabet = state.alphabet === 'cyr' ? 'lat' : state.alphabet === 'lat' ? 'both' : 'cyr';
  toast('Алфавит: ' + state.alphabet);
  renderCard();
}

async function regenExample() {
  const w = state.session?.card?.word;
  if (!w) return;
  if (state.regenExample.has(w.id)) {
    toast('Уже генерирую пример для этого слова');
    return;
  }
  const wordId = w.id;
  state.regenExample.add(wordId);
  renderCard();
  try {
    const updated = await api('POST', `/api/words/${wordId}/regenerate-example`);
    if (state.session?.card?.word?.id === wordId) {
      Object.assign(state.session.card.word, updated);
      state.showExample = true;
      toast('Новый пример готов');
    } else {
      toast(`Пример для «${updated.word_lat}» обновлён в фоне`);
    }
  } catch (e) {
    toast(e.message);
  } finally {
    state.regenExample.delete(wordId);
    renderCard();
  }
}

function renderConjugationTable(table, conj) {
  const order = ['1sg', '2sg', '3sg', '1pl', '2pl', '3pl'];
  const rows = order.map(key => {
    const e = conj[key] || {cyr: '', lat: ''};
    let main, alt;
    if (state.alphabet === 'cyr') { main = e.cyr || e.lat; alt = null; }
    else if (state.alphabet === 'lat') { main = e.lat || e.cyr; alt = null; }
    else { main = e.cyr || e.lat; alt = (e.lat && e.cyr) ? e.lat : null; }
    // The form to speak: prefer Cyrillic if available (sr-RS voice handles both fine).
    const speakText = e.cyr || e.lat;
    const speakBtn = speakText
      ? `<button class="tts-btn" data-tts-text="${escape(speakText)}" data-tip="Озвучить">🔊</button>`
      : '';
    return `<tr>
      <td class="pronoun">${escape(PRONOUN_LABELS[key])}</td>
      <td class="form">${escape(main || '—')}${alt ? `<span class="form-alt">${escape(alt)}</span>` : ''}</td>
      <td class="tts-cell">${speakBtn}</td>
    </tr>`;
  }).join('');
  table.querySelector('tbody').innerHTML = rows;
}

async function playTts(text) {
  if (!text) return;
  try {
    const url = `/api/tts?text=${encodeURIComponent(text)}`;
    const a = new Audio(url);
    a.play().catch(e => toast('Не удалось проиграть: ' + e.message));
  } catch (e) { toast('TTS ошибка: ' + e.message); }
}

async function deleteCurrentWord() {
  const w = state.session?.card?.word;
  if (!w) return;
  const label = w.word_cyr ? `${w.word_cyr} / ${w.word_lat}` : w.word_lat;
  if (!confirm(`Удалить слово «${label}» из словаря?\nДействие необратимо — картинка и аудио тоже удалятся.`)) {
    return;
  }
  try {
    await api('DELETE', `/api/words/${w.id}`);
  } catch (e) {
    toast('Не удалось удалить: ' + e.message);
    return;
  }
  toast(`Удалено: ${w.word_lat}`);
  // Advance the session past this card
  if (state.session) {
    try {
      const sess = await api('POST', `/api/sessions/${state.session.id}/skip`);
      state.session = sess;
      state.flipped = false;
      renderCard();
    } catch (e) {
      // Fall back: leave the session as-is; renderCard will probably finish it
      console.error('skip after delete failed:', e);
    }
  }
}

async function regenConjugations() {
  const w = state.session?.card?.word;
  if (!w) return;
  if (state.conjugating.has(w.id)) return;
  const wordId = w.id;
  state.conjugating.add(wordId);
  renderCard();
  try {
    const updated = await api('POST', `/api/words/${wordId}/conjugate`);
    if (state.session?.card?.word?.id === wordId) {
      Object.assign(state.session.card.word, updated);
      toast('Спряжение обновлено');
    } else {
      toast('Спряжение обновлено в фоне');
    }
  } catch (e) {
    toast('Не удалось: ' + e.message);
  } finally {
    state.conjugating.delete(wordId);
    renderCard();
  }
}

async function classifyAsVerb() {
  const w = state.session?.card?.word;
  if (!w) return;
  if (state.classifying.has(w.id)) return;
  const wordId = w.id;
  state.classifying.add(wordId);
  renderCard();
  try {
    const updated = await api('POST', `/api/words/${wordId}/classify`);
    if (state.session?.card?.word?.id === wordId) {
      Object.assign(state.session.card.word, updated);
      const grpMsg = updated.verb_group ? `группа ${updated.verb_group}` : 'не глагол по мнению модели';
      toast(`Классифицировано: ${grpMsg}`);
    } else {
      toast('Классификация сохранена в фоне');
    }
  } catch (e) {
    toast('Не удалось: ' + e.message);
  } finally {
    state.classifying.delete(wordId);
    renderCard();
  }
}

async function markNonVerb() {
  const w = state.session?.card?.word;
  if (!w) return;
  if (state.classifying.has(w.id)) return;
  const wordId = w.id;
  state.classifying.add(wordId);
  renderCard();
  try {
    const updated = await api('POST', `/api/words/${wordId}/mark-non-verb`);
    if (state.session?.card?.word?.id === wordId) {
      Object.assign(state.session.card.word, updated);
      toast('Помечено: не глагол');
    } else {
      toast('Изменение сохранено в фоне');
    }
  } catch (e) {
    toast('Не удалось: ' + e.message);
  } finally {
    state.classifying.delete(wordId);
    renderCard();
  }
}

async function _batchProcess({listUrl, itemUrl, action, formatOk, btnSelector, label}) {
  let resp;
  try {
    resp = await api('GET', listUrl);
  } catch (e) {
    toast('Не удалось получить список: ' + e.message);
    return;
  }
  const ids = resp.ids || [];
  if (!ids.length) {
    toast(`Нечего ${label.toLowerCase()}: список пуст`);
    return;
  }
  const btn = $(btnSelector);
  if (btn) btn.disabled = true;

  const progress = $('#classify-progress');
  const text = $('#classify-progress-text');
  const fill = $('#classify-progress-fill');
  const log = $('#classify-progress-log');
  progress.hidden = false;
  log.innerHTML = '';
  fill.style.width = '0%';

  const CONCURRENCY = 10;
  let completed = 0;
  let nextIdx = 0;
  let done = 0;
  let err = 0;
  const inFlight = new Set();

  function update() {
    const flight = inFlight.size ? ` · в работе: ${inFlight.size}` : '';
    text.textContent = `${label}: ${completed}/${ids.length} (готово ${done}${err ? `, ошибок ${err}` : ''})${flight}`;
  }

  async function worker() {
    while (true) {
      const i = nextIdx++;
      if (i >= ids.length) return;
      const id = ids[i];
      inFlight.add(id);
      update();
      try {
        const r = await api('POST', itemUrl(id));
        done++;
        appendLog(log, formatOk(r), 'ok');
      } catch (ex) {
        err++;
        appendLog(log, `✗ ${id.slice(0, 8)} — ${ex.message}`, 'err');
      }
      inFlight.delete(id);
      completed++;
      fill.style.width = `${(completed / ids.length * 100).toFixed(1)}%`;
      update();
    }
  }
  const wc = Math.min(CONCURRENCY, ids.length);
  await Promise.all(Array.from({length: wc}, () => worker()));

  text.textContent = `Готово. ${label}: ${done}${err ? `, ошибок ${err}` : ''}.`;
  if (btn) btn.disabled = false;
}

function classifyAllMissing() {
  return _batchProcess({
    listUrl: '/api/words/unclassified',
    itemUrl: id => `/api/words/${id}/classify`,
    formatOk: r => `✓ ${r.word_lat} — ${r.pos || '?'}${r.verb_group ? ` (${r.verb_group})` : ''}`,
    btnSelector: 'button[data-action="classify-all-missing"]',
    label: 'Классификация',
  });
}

function conjugateAllMissing() {
  return _batchProcess({
    listUrl: '/api/words/missing-conjugations',
    itemUrl: id => `/api/words/${id}/conjugate`,
    formatOk: r => `✓ ${r.word_lat} — 1sg: ${r.conjugations?.['1sg']?.cyr || r.conjugations?.['1sg']?.lat || '?'}`,
    btnSelector: 'button[data-action="conjugate-all-missing"]',
    label: 'Спряжения',
  });
}

async function refindImage() {
  const w = state.session?.card?.word;
  if (!w) return;
  if (state.refiningImage.has(w.id)) {
    toast('Уже ищу картинку для этого слова');
    return;
  }
  const wordId = w.id;
  state.refiningImage.add(wordId);
  renderCard();
  try {
    const updated = await api('POST', `/api/words/${wordId}/refind-image`);
    if (updated.image_url) {
      updated.image_url = updated.image_url.split('?')[0] + '?t=' + Date.now();
    }
    // Only apply if the user is still on the same card.
    if (state.session?.card?.word?.id === wordId) {
      Object.assign(state.session.card.word, updated);
      toast('Новая картинка готова');
    } else {
      toast(`Картинка для «${updated.word_lat}» обновлена в фоне`);
    }
  } catch (e) {
    toast('Не удалось: ' + e.message);
  } finally {
    state.refiningImage.delete(wordId);
    renderCard();
  }
}

async function checkTyping() {
  const w = state.session?.card?.word;
  if (!w || !state.session) return;
  const typed = $('#typing-input').value;
  if (!typed.trim()) return;
  try {
    const r = await api('POST', `/api/sessions/${state.session.id}/typing-check`, { word_id: w.id, typed });
    state.typingResult = r;
    const el = $('#typing-result');
    el.className = 'typing-result ' + r.suggested_grade;
    if (r.distance === 0) el.textContent = '✓ точно';
    else if (r.suggested_grade === 'hard') el.textContent = `~ почти (расстояние ${r.distance}). Ожидалось: ${r.expected_lat}`;
    else el.textContent = `✗ ожидалось: ${r.expected_lat} (${r.expected_cyr})`;
    flip();
  } catch (e) { toast(e.message); }
}

// ---- Add words ----
function switchAddTab(name) {
  $$('.add-tabs .tab').forEach(t => t.classList.toggle('active', t.dataset.tab === name));
  $$('.add-pane').forEach(p => p.hidden = p.dataset.pane !== name);
}

async function parseListGpt() {
  const text = $('#words-textarea').value;
  if (!text.trim()) return;
  $('#parse-status').textContent = 'GPT извлекает…';
  try {
    const r = await api('POST', '/api/words/parse-text', { text });
    const dupCount = r.entries.filter(e => e.duplicate).length;
    $('#parse-status').textContent = `Найдено: ${r.entries.length}${dupCount ? `, дубликатов: ${dupCount}` : ''}`;
    showPreview(r.entries);
  } catch (e) {
    $('#parse-status').textContent = 'Ошибка: ' + e.message;
  }
}

function parseListNaive() {
  const lines = $('#words-textarea').value.split('\n').map(l => l.trim()).filter(Boolean);
  const entries = lines.map(l => {
    const [word, translation] = l.split('|').map(s => s?.trim());
    return { word, translation: translation || undefined, duplicate: false };
  });
  showPreview(entries);
}

async function ocrFromImage(file) {
  $('#ocr-status').textContent = 'Распознаю…';
  const fd = new FormData();
  fd.append('image', file);
  try {
    const r = await api('POST', '/api/words/from-screenshot', fd);
    $('#ocr-status').textContent = `Найдено слов: ${r.entries.length}`;
    showPreview(r.entries);
  } catch (e) {
    $('#ocr-status').textContent = 'Ошибка: ' + e.message;
  }
}

function showPreview(entries) {
  const tbody = $('#preview-body');
  tbody.innerHTML = '';
  entries.forEach((e, i) => {
    const tr = document.createElement('tr');
    const dup = e.duplicate ? ' <span style="color:var(--fg-dim); font-size:11px;">уже в базе</span>' : '';
    // Pre-uncheck duplicates
    const checked = e.duplicate ? '' : 'checked';
    tr.innerHTML = `
      <td><input type="checkbox" data-i="${i}" ${checked}></td>
      <td><input type="text" data-i="${i}" data-field="word" value="${escape(e.word || '')}">${dup}</td>
      <td><input type="text" data-i="${i}" data-field="translation" value="${escape(e.translation || '')}"></td>
    `;
    tbody.appendChild(tr);
  });
  state.pendingPreview = entries;
  $('#preview').hidden = false;
}

async function saveWords() {
  const rows = $$('#preview-body tr');
  const out = [];
  rows.forEach(tr => {
    const cb = $('input[type="checkbox"]', tr);
    if (!cb.checked) return;
    const word = $('input[data-field="word"]', tr).value.trim();
    const translation = $('input[data-field="translation"]', tr).value.trim();
    if (word) out.push({ word, translation: translation || undefined });
  });
  if (!out.length) { toast('Нечего сохранять'); return; }

  const btn = $('button[data-action="save-words"]');
  btn.disabled = true;
  $('#save-status').textContent = '';
  const progress = $('#add-progress');
  const text = $('#progress-text');
  const fill = $('#progress-fill');
  const log = $('#progress-log');
  const grid = $('#cards-grid');
  const cardsCount = $('#cards-count');
  progress.hidden = false;
  log.innerHTML = '';
  grid.innerHTML = '';
  cardsCount.textContent = '';
  fill.style.width = '0%';

  const CONCURRENCY = 10;
  let added = 0, dup = 0, err = 0;
  let completed = 0;
  let nextIdx = 0;
  const inFlight = new Set();

  function updateText() {
    const flightStr = inFlight.size ? ` · в работе: ${[...inFlight].map(w => `«${w}»`).join(', ')}` : '';
    text.textContent = `${completed}/${out.length} (added ${added}, dup ${dup}${err ? `, err ${err}` : ''})${flightStr}`;
  }

  async function worker() {
    while (true) {
      const i = nextIdx++;
      if (i >= out.length) return;
      const e = out[i];
      inFlight.add(e.word);
      updateText();
      try {
        const r = await api('POST', '/api/words/add-one', e);
        if (r.status === 'duplicate') {
          dup++;
          appendLog(log, `↺ ${e.word} — уже в базе`, 'dup');
        } else {
          added++;
          appendCard(grid, r.word);
          cardsCount.textContent = `(${added})`;
        }
      } catch (ex) {
        err++;
        appendLog(log, `✗ ${e.word} — ${ex.message}`, 'err');
      }
      inFlight.delete(e.word);
      completed++;
      fill.style.width = `${(completed / out.length * 100).toFixed(1)}%`;
      updateText();
    }
  }

  const workerCount = Math.min(CONCURRENCY, out.length);
  await Promise.all(Array.from({length: workerCount}, () => worker()));

  text.textContent = `Готово. Добавлено ${added}, дубликатов ${dup}${err ? `, ошибок ${err}` : ''}.`;
  $('#save-status').textContent = '';
  $('#preview').hidden = true;
  $('#words-textarea').value = '';
  toast(`Добавлено: ${added}${dup ? ` (+${dup} дубликатов)` : ''}${err ? ` (${err} ошибок)` : ''}`);
  loadHome();
  btn.disabled = false;
}

function appendLog(log, msg, cls) {
  const div = document.createElement('div');
  div.className = cls || '';
  div.textContent = msg;
  log.appendChild(div);
}

function appendCard(grid, w) {
  const card = document.createElement('div');
  card.className = 'preview-card';
  const img = w.image_url
    ? `<div class="img"><img src="${escape(w.image_url)}" loading="lazy" alt=""></div>`
    : `<div class="img"><span class="no-img">нет картинки</span></div>`;
  const example = w.example_lat
    ? `<div class="example">${escape(w.example_lat)}</div>`
    : '';
  card.innerHTML = `
    ${img}
    <div class="text">
      <div class="word">${escape(w.word_cyr)}<span class="lat">${escape(w.word_lat)}</span></div>
      <div class="translation">${escape(w.translation || '—')}</div>
      ${example}
    </div>
  `;
  grid.appendChild(card);
}

// ---- Settings ----
const SETTINGS_DEFS = [
  { key: 'mastered_threshold', label: 'Запоминание (правильных подряд)', type: 'range', min: 1, max: 7, step: 1 },
  { key: 'review_session_size', label: 'Размер сессии повтора', type: 'range', min: 10, max: 500, step: 10 },
  { key: 'error_factor_alpha', label: 'Агрессия по проблемным словам', type: 'range', min: 1, max: 10, step: 0.5 },
  { key: 'reverse_probability', label: 'Доля обратных карточек (0–1)', type: 'range', min: 0, max: 1, step: 0.05 },
  { key: 'forget_decay_alpha', label: 'Штраф за забывания', type: 'range', min: 0, max: 1, step: 0.05 },
  { key: 'hard_modifier', label: 'Hard-множитель к интервалу', type: 'range', min: 0.1, max: 1, step: 0.1 },
  { key: 'typing_mode_enabled', label: 'Режим ввода с клавиатуры', type: 'checkbox' },
  { key: 'typing_relaxed_diacritics', label: 'Не требовать диакритику', type: 'checkbox' },
  { key: 'typing_hard_levenshtein_threshold', label: 'Порог "почти" в режиме ввода', type: 'range', min: 1, max: 5, step: 1 },
  { key: 'always_regenerate_example', label: 'Всегда генерировать новый пример', type: 'checkbox' },
  { key: 'tts_voice', label: 'TTS голос', type: 'text' },
  { key: 'openai_model_text', label: 'OpenAI модель (текст)', type: 'text' },
  { key: 'openai_model_vision', label: 'OpenAI модель (vision)', type: 'text' },
  { key: 'openai_model_extract', label: 'OpenAI модель (извлечение/перевод)', type: 'text' },
  { key: 'image_search_lang', label: 'Язык для поиска картинок (Wiki)', type: 'text' },
  { key: 'default_alphabet_view', label: 'Алфавит по умолчанию (cyr/lat/both)', type: 'text' },
];

async function loadSettings() {
  const cfg = await api('GET', '/api/config');
  state.config = cfg;
  state.alphabet = cfg.default_alphabet_view || 'both';
  const main = $('#settings-main');
  main.innerHTML = '';
  for (const def of SETTINGS_DEFS) {
    const v = cfg[def.key];
    const row = document.createElement('div');
    row.className = 'setting-row';
    if (def.type === 'range') {
      row.innerHTML = `
        <label>${def.label}<span class="desc">${def.key}</span></label>
        <input type="range" min="${def.min}" max="${def.max}" step="${def.step}" value="${v}" data-key="${def.key}">
        <span class="value" data-value-of="${def.key}">${v}</span>
      `;
    } else if (def.type === 'checkbox') {
      row.innerHTML = `
        <label>${def.label}<span class="desc">${def.key}</span></label>
        <span></span>
        <input type="checkbox" data-key="${def.key}" ${v ? 'checked' : ''}>
      `;
    } else {
      row.innerHTML = `
        <label>${def.label}<span class="desc">${def.key}</span></label>
        <input type="text" data-key="${def.key}" value="${escape(String(v ?? ''))}">
        <span></span>
      `;
    }
    main.appendChild(row);
  }
  // listeners
  $$('input[data-key]', main).forEach(input => {
    input.addEventListener('change', persistSetting);
    if (input.type === 'range') input.addEventListener('input', e => {
      const k = e.target.dataset.key;
      const span = main.querySelector(`[data-value-of="${k}"]`);
      if (span) span.textContent = e.target.value;
    });
  });
}

async function persistSetting(e) {
  const input = e.target;
  const key = input.dataset.key;
  let value = input.type === 'checkbox' ? input.checked
    : input.type === 'range' ? Number(input.value)
    : input.value;
  const next = { ...state.config, [key]: value };
  state.config = await api('PUT', '/api/config', next);
  toast('Сохранено');
}

// ---- History ----
async function loadHistory() {
  const r = await api('GET', '/api/sessions');
  const main = $('#history-main');
  if (!r.sessions.length) { main.innerHTML = '<p class="hint">Сессий пока нет.</p>'; return; }
  main.innerHTML = r.sessions.slice().reverse().map(s => `
    <div class="session-row">
      <span class="ts">${(s.started_at || '').slice(0, 16).replace('T', ' ')}</span>
      <span>${s.mode}</span>
      <span>shown ${s.summary.shown}</span>
      <span>acc ${Math.round(s.summary.accuracy*100)}%</span>
      <span>+${s.summary.new_mastered} mastered</span>
    </div>
  `).join('');
}

// ---- Hotkeys ----
const HOTKEYS = {
  home: [
    { key: 'g', label: 'Новые', action: () => startSession('learn') },
    { key: 'r', label: 'Повтор', action: () => startSession('review') },
    { key: 'a', label: 'Добавить', action: () => { showScreen('add'); } },
    { key: ',', label: 'Настройки', action: () => { showScreen('settings'); loadSettings(); } },
    { key: 'h', label: 'История', action: () => { showScreen('history'); loadHistory(); } },
    { key: '?', label: 'Помощь', action: () => showOverlay() },
  ],
  session: [
    { key: ' ', label: 'Перевернуть', action: () => state.flipped ? null : flip() },
    { key: 'j', label: 'Не угадал', action: () => answer('again') },
    { key: 'k', label: 'Сложно', action: () => answer('hard') },
    { key: 'l', label: 'Угадал', action: () => answer('good') },
    { key: '1', label: 'Не угадал', action: () => answer('again') },
    { key: '2', label: 'Сложно', action: () => answer('hard') },
    { key: '3', label: 'Угадал', action: () => answer('good') },
    { key: 's', label: 'Озвучить', action: () => speak() },
    { key: 't', label: 'Перевод', action: () => toggleTranslation() },
    { key: 'e', label: 'Пример', action: (ev) => ev.shiftKey ? regenExample() : toggleExample() },
    { key: 'r', label: 'Перенайти картинку', action: () => refindImage() },
    { key: 'p', label: 'Прогресс по словам', action: () => toggleLearnPanel() },
    { key: 'c', label: 'Алфавит', action: () => cycleAlphabet() },
    { key: 'i', label: 'Ввод', action: () => toggleTyping() },
    { key: 'Escape', label: 'Выйти', action: () => exitSession() },
    { key: '?', label: 'Помощь', action: () => showOverlay() },
  ],
  add: [
    { key: 'Escape', label: 'Назад', action: () => { showScreen('home'); loadHome(); } },
  ],
  settings: [
    { key: 'Escape', label: 'Назад', action: () => { showScreen('home'); loadHome(); } },
  ],
  history: [
    { key: 'Escape', label: 'Назад', action: () => { showScreen('home'); loadHome(); } },
  ],
  'session-end': [
    { key: 'Escape', label: 'На главный', action: () => { showScreen('home'); loadHome(); } },
    { key: 'Enter', label: 'Ещё', action: () => $('#end-again')?.click() },
  ],
};

function showOverlay() {
  const list = HOTKEYS[state.screen] || [];
  $('#overlay-content').innerHTML = `
    <h2>Хоткеи (${state.screen})</h2>
    ${list.map(h => `<div class="row"><span>${h.label}</span><span class="kbd">${h.key === ' ' ? 'Пробел' : h.key}</span></div>`).join('')}
    <p class="hint">Esc / ? — закрыть</p>
  `;
  $('#hotkey-overlay').hidden = false;
}
function hideOverlay() { $('#hotkey-overlay').hidden = true; }

function isTextInputFocused() {
  const a = document.activeElement;
  if (!a) return false;
  if (a.tagName !== 'INPUT' && a.tagName !== 'TEXTAREA') return false;
  // Hidden / display:none inputs shouldn't block hotkeys
  if (a.offsetParent === null) return false;
  return true;
}

// Robust key matcher: handles ev.code for digits (numpad/layout-agnostic)
function keyMatches(ev, hKey) {
  if (ev.key === hKey) return true;
  if (ev.key && ev.key.toLowerCase() === hKey.toLowerCase()) return true;
  // Digits via ev.code in case of unexpected layouts/IMEs
  if (hKey === '1' && (ev.code === 'Digit1' || ev.code === 'Numpad1')) return true;
  if (hKey === '2' && (ev.code === 'Digit2' || ev.code === 'Numpad2')) return true;
  if (hKey === '3' && (ev.code === 'Digit3' || ev.code === 'Numpad3')) return true;
  return false;
}

document.addEventListener('keydown', (ev) => {
  // Overlay close
  if (!$('#hotkey-overlay').hidden) {
    if (ev.key === 'Escape' || ev.key === '?') { hideOverlay(); ev.preventDefault(); }
    return;
  }
  // Allow typing in inputs except for Escape and Enter (in typing-box)
  if (isTextInputFocused()) {
    if (ev.key === 'Enter' && document.activeElement?.id === 'typing-input') {
      checkTyping(); ev.preventDefault();
      return;
    }
    if (ev.key === 'Escape') document.activeElement.blur();
    return;
  }

  // If a button has focus from a previous click, blur it so Space/Enter
  // doesn't re-activate that button instead of running the hotkey.
  if (document.activeElement?.tagName === 'BUTTON') {
    document.activeElement.blur();
  }

  const handlers = HOTKEYS[state.screen] || [];
  for (const h of handlers) {
    if (keyMatches(ev, h.key)) {
      h.action(ev);
      ev.preventDefault();
      return;
    }
  }
});

// Defocus any button immediately after click — so the space bar doesn't
// re-trigger the focused button later. Must NOT blur INPUT/TEXTAREA.
document.addEventListener('click', (ev) => {
  const btn = ev.target.closest('button');
  if (btn) setTimeout(() => btn.blur(), 0);
});

// ---- Wire up DOM ----
function bindActions() {
  document.addEventListener('click', (ev) => {
    const t = ev.target.closest('[data-action]');
    if (!t) return;
    const a = t.dataset.action;
    switch (a) {
      case 'learn': startSession('learn'); break;
      case 'review': startSession('review'); break;
      case 'review-size': {
        const raw = t.dataset.size;
        const size = raw === 'all' ? 99999 : parseInt(raw, 10);
        startSession('review', size);
        break;
      }
      case 'resume': resumeSession(); break;
      case 'add': showScreen('add'); break;
      case 'settings': showScreen('settings'); loadSettings(); break;
      case 'history': showScreen('history'); loadHistory(); break;
      case 'back': showScreen('home'); loadHome(); break;
      case 'exit-session': exitSession(); break;
      case 'speak': speak(); break;
      case 'toggle-translation': toggleTranslation(); break;
      case 'toggle-example': toggleExample(); break;
      case 'regen-example': regenExample(); break;
      case 'refind-image': refindImage(); break;
      case 'classify-as-verb': classifyAsVerb(); break;
      case 'mark-non-verb': markNonVerb(); break;
      case 'regen-conjugations': regenConjugations(); break;
      case 'delete-word': deleteCurrentWord(); break;
      case 'classify-all-missing': classifyAllMissing(); break;
      case 'conjugate-all-missing': conjugateAllMissing(); break;
      case 'toggle-learn-panel': toggleLearnPanel(); break;
      case 'cycle-alphabet': cycleAlphabet(); break;
      case 'toggle-typing': toggleTyping(); break;
      case 'parse-list': parseListGpt(); break;
      case 'parse-list-naive': parseListNaive(); break;
      case 'save-words': saveWords(); break;
    }
  });

  // Card click flips
  $('#card').addEventListener('click', (ev) => {
    if (ev.target.closest('.grade')) return;
    if (!state.flipped) flip();
  });
  // TTS click delegation (works for any [data-tts-text] button)
  document.addEventListener('click', (ev) => {
    const btn = ev.target.closest('[data-tts-text]');
    if (!btn) return;
    ev.stopPropagation();
    playTts(btn.dataset.ttsText);
  });
  // grade clicks
  $$('.grade').forEach(b => b.addEventListener('click', () => answer(b.dataset.grade)));

  // Tabs
  $$('.add-tabs .tab').forEach(t => t.addEventListener('click', () => switchAddTab(t.dataset.tab)));

  // Drop zone
  const dz = $('#dropzone');
  dz.addEventListener('dragover', (e) => { e.preventDefault(); dz.classList.add('dragover'); });
  dz.addEventListener('dragleave', () => dz.classList.remove('dragover'));
  dz.addEventListener('drop', (e) => {
    e.preventDefault(); dz.classList.remove('dragover');
    const f = e.dataTransfer.files?.[0];
    if (f) ocrFromImage(f);
  });
  // paste from clipboard
  document.addEventListener('paste', (e) => {
    if (state.screen !== 'add') return;
    const items = e.clipboardData?.items || [];
    for (const it of items) {
      if (it.type.startsWith('image/')) {
        ocrFromImage(it.getAsFile());
        return;
      }
    }
  });
}

// ---- Init ----
async function init() {
  bindActions();
  try {
    const cfg = await api('GET', '/api/config');
    state.config = cfg;
    state.alphabet = cfg.default_alphabet_view || 'both';
    state.typingMode = !!cfg.typing_mode_enabled;
  } catch (e) { console.error(e); }
  showScreen('home');
  loadHome();
}

init();
