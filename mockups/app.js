/* Typeface/Off UX study. Rendering and geometric rankings use real fonts.
   Weight suggestions are illustrative. Everything stays in memory. No analytics or remote assets. */
'use strict';

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const escapeHTML = value => String(value).replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const clone = value => structuredClone(value);
const clamp = (n, min, max) => Math.min(max, Math.max(min, n));
const fmt = (n, digits = 1) => Number(n).toFixed(digits).replace(/\.0$/, '');
const glyphs = text => [...new Intl.Segmenter('en', {granularity:'grapheme'}).segment(text)].map(x => x.segment);
const DATA = window.FONT_DATA;
const SAMPLES = {
  // Public-domain excerpts, transcribed from Project Gutenberg ebooks 11 and 12.
  reading: {label:'ALICE IN WONDERLAND', title:'Down the Rabbit-Hole', paragraphs:[
    'Alice was beginning to get very tired of sitting by her sister on the bank, and of having nothing to do: once or twice she had peeped into the book her sister was reading, but it had no pictures or conversations in it, “and what is the use of a book,” thought Alice “without pictures or conversations?”',
    'So she was considering in her own mind (as well as she could, for the hot day made her feel very sleepy and stupid), whether the pleasure of making a daisy-chain would be worth the trouble of getting up and picking the daisies, when suddenly a White Rabbit with pink eyes ran close by her.'
  ], foot:'Lewis Carroll · Alice’s Adventures in Wonderland'},
  poetry: {label:'JABBERWOCKY', title:'Jabberwocky', paragraphs:[
    '’Twas brillig, and the slithy toves\n    Did gyre and gimble in the wabe;\nAll mimsy were the borogoves,\n    And the mome raths outgrabe.',
    '“Beware the Jabberwock, my son!\n    The jaws that bite, the claws that catch!\nBeware the Jubjub bird, and shun\n    The frumious Bandersnatch!”',
    'He took his vorpal sword in hand:\n    Long time the manxome foe he sought—\nSo rested he by the Tumtum tree,\n    And stood awhile in thought.'
  ], foot:'Lewis Carroll · Through the Looking-Glass'},
  alphabet: {label:'ALPHABET & LETTERFORMS', title:'Aa Bb Cc', paragraphs:['abcdefghijklmnopqrstuvwxyz','ABCDEFGHIJKLMNOPQRSTUVWXYZ','a g e s r t f j y\nG R Q M W K J','Il1  O0  rn m  cl d  vv w'], foot:'Hamburgefontsiv\nThe quick brown fox jumps over the lazy dog.'},
  numerals: {label:'NUMERALS & PUNCTUATION', title:'0123456789', paragraphs:['$1,234.56   €789.00\n£42.50   ¥8,900','10:24:08   09/18/2026\n1/2  3/4  5/8  7/16','“Quotation” ‘apostrophe’\n(Parentheses) [brackets]\n& @ # % * + = / — …'], foot:'1,111.11\n8,888.88\n0,000.00'}
};
const FEATURE_NAMES = {
  kern:'Kerning', liga:'Standard ligatures', dlig:'Discretionary ligatures', calt:'Contextual alternates',
  case:'Case-sensitive forms', cpsp:'Capital spacing', frac:'Fractions', zero:'Slashed zero',
  tnum:'Tabular numerals', pnum:'Proportional numerals', lnum:'Lining numerals', onum:'Oldstyle numerals',
  ordn:'Ordinals', sups:'Superscript', subs:'Subscript', sinf:'Scientific inferiors',
  numr:'Numerators', dnom:'Denominators', salt:'Stylistic alternates', aalt:'Access all alternates',
  ccmp:'Glyph composition', locl:'Localized forms', rlig:'Required ligatures', mark:'Mark positioning',
  mkmk:'Mark-to-mark positioning', init:'Initial forms', medi:'Medial forms', fina:'Final forms', isol:'Isolated forms'
};
const AUTOMATIC = new Set(['ccmp','locl','rlig','mark','mkmk','init','medi','fina','isol']);
const NUMBER_FEATURES = new Set(['tnum','pnum','lnum','onum','ordn','sups','subs','sinf','numr','dnom','frac','zero']);
const FEATURE_SAMPLES = {liga:'fi fl',dlig:'st',calt:'r →',zero:'0',tnum:'1820',pnum:'1820',frac:'1/2',aalt:'!?',salt:'ag',case:'(A)',cpsp:'ABC',ss01:'ag',ss02:'Il',ss03:'012',ss04:'ag'};
const RESET_ICON = '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M4 6a7 7 0 1 1-1 6M4 2v4h4"/></svg>';
let ranking = {key:null, scores:[], pending:false}, rankingTimer, rankingVersion = 0;
const rankingCache = new Map();
let state, history = [], inputTransaction = null, toastTimer, drawFrame, loadVersion = 0;
const scrollPositions = {a:0,b:0};
const measurementCache = new Map();
const fontBuffers = new Map();
const configuredFonts = new Map();
const characterNames = new Map();
const glyphFrameCache = new Map();
let configuredFontID = 0;

function createFont(id) {
  const font = DATA[id];
  const style = font.faces.regular ? 'regular' : Object.keys(font.faces)[0];
  const axes = Object.fromEntries(font.faces[style].axes.map(axis => [axis.tag, axis.default]));
  return {id, style, axes, size:22, tracking:0, features:{}};
}
function face(config) { return DATA[config.id].faces[config.style]; }
function weight(config) { return config.axes.wght ?? face(config).weight; }
function featureValue(config, tag) { return config.features[tag] ?? (['kern','liga','calt'].includes(tag) ? 1 : 0); }
function fontSize(config) { return config.size * 4 / 3; }
function configuredFamily(config) {
  const f = face(config), buffer = fontBuffers.get(f.family);
  if (!buffer) return f.family;
  const key = JSON.stringify([f.family,config.axes,config.features]);
  if (!configuredFonts.has(key)) {
    const family = 'tfo-shaped-' + (++configuredFontID);
    const axis = f.axes.find(a => a.tag === 'wght');
    const configured = new FontFace(family, buffer, {
      weight:axis ? `${axis.min} ${axis.max}` : '400',
      featureSettings:Object.entries(config.features).map(([tag,value]) => `"${tag}" ${value}`).join(', ') || 'normal',
      variationSettings:Object.entries(config.axes).map(([tag,value]) => `"${tag}" ${value}`).join(', ') || 'normal'
    });
    document.fonts.add(configured);
    configuredFonts.set(key,configured);
    if (configuredFonts.size > 200) {
      const visibleFamilies = new Set($$('[style]').map(el=>el.style.fontFamily.replaceAll('"','')));
      const oldest = [...configuredFonts.keys()].find(k=>!visibleFamilies.has(configuredFonts.get(k).family)&&k!==key);
      if(oldest){document.fonts.delete(configuredFonts.get(oldest));configuredFonts.delete(oldest);}
    }
  }
  const configured = configuredFonts.get(key);
  configuredFonts.delete(key); configuredFonts.set(key,configured);
  return configured.family;
}
function fontStyle(config, pixels = fontSize(config)) {
  const variation = Object.entries(config.axes).map(([tag,value]) => `"${tag}" ${value}`).join(', ') || 'normal';
  const features = Object.entries(config.features).map(([tag,value]) => `"${tag}" ${value}`).join(', ') || 'normal';
  return `font-family:"${configuredFamily(config)}";font-size:${pixels}px;font-weight:${config.axes.wght ?? 400};font-style:normal;font-synthesis:none;font-optical-sizing:none;font-kerning:${config.features.kern===0?'none':'normal'};font-variation-settings:${variation};font-feature-settings:${features};letter-spacing:${config.tracking}em;`;
}
function support(config, text) {
  const coverage = face(config).coverage;
  return [...text].every(char => /\s/u.test(char) || [0x200d,0xfe0f,0xfe0e].includes(char.codePointAt(0)) || coverage.some(([start,end]) => char.codePointAt(0) >= start && char.codePointAt(0) <= end));
}
function snapshot() { history.push(clone(state)); if (history.length > 60) history.shift(); updateUndo(); }
function updateUndo() { $('#undo').disabled = !history.length; }
function toast(message) { const el = $('#toast'); el.textContent = message; el.classList.add('visible'); clearTimeout(toastTimer); toastTimer = setTimeout(() => el.classList.remove('visible'), 2500); }

function configureFonts() {
  const css = Object.values(DATA).flatMap(font => Object.values(font.faces).map(f => {
    const axis = f.axes.find(a => a.tag === 'wght');
    return `@font-face{font-family:"${f.family}";src:url("${f.url}");font-weight:${axis ? `${axis.min} ${axis.max}` : '400'};font-style:normal;font-display:block;}`;
  })).join('\n');
  const style = document.createElement('style'); style.textContent = css; document.head.append(style);
}
async function ensureFonts() {
  const version = ++loadVersion;
  try {
    await Promise.all([state.a,state.b].filter(Boolean).map(c => document.fonts.load(`${c.axes.wght ?? 400} 20px "${face(c).family}"`)));
    if (version === loadVersion) { measurementCache.clear(); renderCenter(); updateMetrics(); }
  } catch (error) { toast('A font could not be loaded. Check the local server.'); console.error(error); }
}

function sample() { return state.sample === 'custom' ? {label:'YOUR TEXT', title:'', paragraphs:state.custom.split(/\n\n/),foot:''} : SAMPLES[state.sample]; }
function fullSample() { const s = sample(); return [s.title,...s.paragraphs,s.foot].filter(Boolean).join('\n\n'); }
function describeGlyph(char) {
  if (/^[a-z]$/.test(char)) return 'Lowercase ' + char;
  if (/^[A-Z]$/.test(char)) return 'Capital ' + char;
  if (/^[0-9]$/.test(char)) return 'Digit ' + char;
  return ({'&':'Ampersand','@':'At sign','!':'Exclamation mark','?':'Question mark',' ':'Space'})[char] || 'Character';
}
function codepoints(char) { return [...char].map(c => 'U+' + c.codePointAt(0).toString(16).toUpperCase().padStart(4,'0')).join(' '); }
async function renderCharacterName(char){
  if(!characterNames.has(char)){
    try {
      const response=await fetch('/character-names?text='+encodeURIComponent(char));
      if(!response.ok)throw new Error('Character names unavailable');
      characterNames.set(char,(await response.json()).map(item=>`${item.codepoint} ${item.name}`).join(' · '));
    } catch(error){return;}
  }
  if(state.mode!=='glyph'||state.selected!==char)return;
  const el=$('.glyph-name');if(!el)return;
  el.textContent=characterNames.get(char);el.title=el.textContent;
}

function rankingCandidates() {
  return [...new Set([...Array.from({length:94},(_,i)=>String.fromCodePoint(33+i)),...glyphs(fullSample())])]
    .filter(char=>!/^\s+$/u.test(char)&&support(state.a,char)&&support(state.b,char)).sort();
}
function requestRankings() {
  if(!state.b){clearTimeout(rankingTimer);rankingVersion++;ranking={key:null,scores:[],pending:false};return;}
  const candidates=rankingCandidates();
  // A common size change doesn't affect shape or em-normalized spacing.
  const a={...clone(state.a),size:22},b={...clone(state.b),size:22*state.b.size/state.a.size};
  const key=JSON.stringify([a,b,candidates]);
  if(key===ranking.key)return;
  clearTimeout(rankingTimer);const version=++rankingVersion;
  if(rankingCache.has(key)){ranking={key,scores:rankingCache.get(key),pending:false};return;}
  ranking={key,scores:[],pending:true};
  rankingTimer=setTimeout(()=>{
    const scores=[];let index=0;
    const step=()=>{
      if(version!==rankingVersion)return;
      const deadline=performance.now()+10;
      do {
        scores.push(GlyphDifferences.compare(candidates[index++],a,b,{measure,family:configuredFamily}));
      } while(index<candidates.length&&performance.now()<deadline);
      if(index<candidates.length){rankingTimer=setTimeout(step,0);return;}
      rankingCache.set(key,scores);
      if(rankingCache.size>8)rankingCache.delete(rankingCache.keys().next().value);
      ranking={key,scores,pending:false};finishRankings();
    };
    if(candidates.length)step();else{ranking={key,scores:[],pending:false};finishRankings();}
  },100);
}
function finishRankings(){rememberScroll();if(state.mode==='text')renderText();renderDifferences();}
function rankedDifferences(){return GlyphDifferences.rank(ranking.scores,state.highlights);}
function navigationGlyphs(){const ranked=rankedDifferences();return ranked.length?ranked.map(item=>item.char):glyphs('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789&@');}
function spacingAlignment(){return state.highlights.spacing&&!state.highlights.shape;}
function highlightedCharacters(){
  const present=new Set(glyphs(fullSample())),selected=new Map();
  for(const kind of ['shape','spacing']){
    if(!state.highlights[kind])continue;
    const top=GlyphDifferences.rank(ranking.scores,{[kind]:true}).filter(item=>present.has(item.char)&&item[kind]>1e-9).slice(0,8);
    for(const item of top)selected.set(item.char,[...(selected.get(item.char)??[]),kind]);
  }
  return selected;
}
function syncSizeControl(force=false){
  const input=$('#text-size'),mixed=state.b&&state.a.size!==state.b.size;
  input.placeholder=mixed?'Mixed':'';
  if(force||document.activeElement!==input)input.value=mixed?'':state.a.size;
  input.setAttribute('aria-label',mixed?'Mixed text sizes. Set both fonts in points':'Shared text size in points');
}

function rangeControl(slot, key, label, value, min, max, step, unit = '') {
  const id = `${slot}-${key.replace('.','-')}`;
  return `<div class="control-row"><span class="control-name"><label for="${id}-number">${label}</label><button class="property-reset" data-reset-property="${key}" data-slot="${slot}" aria-label="Reset font ${slot.toUpperCase()} ${label}" title="Reset ${label.toLowerCase()}" ${value===propertyDefault(slot,key)?'disabled':''}>${RESET_ICON}</button></span><div class="control-value"><input id="${id}-number" data-slot="${slot}" data-param="${key}" type="number" value="${value}" min="${min}" max="${max}" step="${step}" aria-label="Font ${slot.toUpperCase()} ${label}"><span class="unit">${unit}</span></div></div><input id="${id}-range" data-slot="${slot}" data-param="${key}" type="range" value="${value}" min="${min}" max="${max}" step="${step}" aria-label="Font ${slot.toUpperCase()} ${label} slider" style="--fill:${(value-min)/(max-min)*100}%">`;
}
function propertyDefault(slot,key){return key.startsWith('axis.')?face(state[slot]).axes.find(a=>a.tag===key.slice(5)).default:key==='size'?22:0;}
function fontOptions(slot,config){
  return (slot==='b'?`<option value="" ${!config?'selected':''}>None</option>`:'')+Object.entries(DATA).map(([id,item])=>`<option value="${id}" ${id===config?.id?'selected':''} ${!item.available?'disabled':''}>${escapeHTML(item.name)}${!item.available?' — unavailable':''}</option>`).join('');
}
function lockButton(){
  return `<button class="appearance-lock" data-action="toggle-appearance-lock" aria-pressed="${state.appearanceLocked}" aria-label="${state.appearanceLocked?'Unlock':'Lock'} appearance" title="${state.appearanceLocked?'Unlock':'Lock'} appearance" ${!state.b?'disabled':''}><svg viewBox="0 0 20 20"><rect x="4" y="8" width="12" height="10" rx="2"/><path d="${state.appearanceLocked?'M6 8V5a4 4 0 0 1 8 0v3':'M6 8V5a4 4 0 0 1 7.5-2'}"/><path d="M10 12v2"/></svg></button>`;
}
function renderInspector(slot) {
  const config = state[slot], el = $(`#inspector-${slot}`);
  const groups = new Map($$('.feature-group',el).map(group=>[group.dataset.group,group.open]));
  if (!config) {
    el.innerHTML = `<div class="inspector-top"><label class="sr-only" for="font-b">Font B family</label><select class="font-select" id="font-b" data-font="b">${fontOptions('b',null)}</select></div>`;
    return;
  }
  const f = face(config), font = DATA[config.id];
  const options = fontOptions(slot,config);
  const axes = [...f.axes].sort((a,b)=>(b.tag==='wght')-(a.tag==='wght')).map(axis => rangeControl(slot,`axis.${axis.tag}`,axis.label,config.axes[axis.tag],axis.min,axis.max,1,axis.tag==='opsz'?'pt':'')).join('');
  el.innerHTML = `<div class="inspector-top"><label class="sr-only" for="font-${slot}">Font ${slot.toUpperCase()} family</label><select class="font-select" id="font-${slot}" data-font="${slot}" title="${escapeHTML(font.name)}">${options}</select><div class="style-row"><label class="sr-only" for="style-${slot}">Font ${slot.toUpperCase()} style</label><select id="style-${slot}" data-style="${slot}">${Object.entries(font.faces).map(([key,item])=>`<option value="${key}" ${config.style===key?'selected':''}>${item.label}</option>`).join('')}</select></div></div>
    <section class="inspector-section"><div class="section-heading"><h2>Appearance</h2><div class="section-actions"><button class="reset" data-reset="appearance" data-slot="${slot}" aria-label="Reset font ${slot.toUpperCase()} appearance" title="Reset appearance">${RESET_ICON}</button>${lockButton()}</div></div>${axes || `<div class="control-row"><span>Weight</span><span class="static-weight numeric">${f.weight}</span></div>`}
    ${rangeControl(slot,'size','Size',config.size,10,144,.1,'pt')}
    ${rangeControl(slot,'tracking','Tracking',config.tracking,-.12,.15,.001,'em')}
    </section><section class="features-section"><div class="section-heading"><h2>Typography</h2><button class="reset" data-reset="features" data-slot="${slot}" aria-label="Reset font ${slot.toUpperCase()} typography" title="Reset typography">${RESET_ICON}</button></div><div class="feature-list">${featureGroups(slot)}</div></section>
    <div class="inspector-bottom" id="metrics-${slot}"></div>`;
  $$('.feature-group',el).forEach(group=>{if(groups.has(group.dataset.group))group.open=groups.get(group.dataset.group);});
}
function featureGroups(slot) {
  const config = state[slot], features = face(config).features;
  const groups = [ ['Common', features.filter(f=>!AUTOMATIC.has(f.tag)&&!NUMBER_FEATURES.has(f.tag)&&!f.tag.startsWith('cv')&&!f.tag.startsWith('ss')&&!['aalt','salt'].includes(f.tag))],
    ['Character variants', features.filter(f=>f.tag.startsWith('cv')||['aalt','salt'].includes(f.tag))],
    ['Stylistic sets', features.filter(f=>f.tag.startsWith('ss'))],
    ['Numbers', features.filter(f=>NUMBER_FEATURES.has(f.tag))],
    ['Automatic shaping', features.filter(f=>AUTOMATIC.has(f.tag))] ];
  return groups.filter(([,items])=>items.length).map(([label,items])=>`<details class="feature-group" data-group="${label}" ${label==='Automatic shaping'?'':'open'}><summary>${label}</summary>${items.map(f=>featureRow(slot,f)).join('')}</details>`).join('') || '<p class="feature-absent">No adjustable features</p>';
}
function featureRow(slot, feature) {
  const config = state[slot], tag = feature.tag, label = feature.label || FEATURE_NAMES[tag] || (tag.startsWith('cv')?'Character variant '+Number(tag.slice(2)):tag.startsWith('ss')?'Stylistic set '+Number(tag.slice(2)):tag);
  const automatic = AUTOMATIC.has(tag), value = featureValue(config,tag), id = `feature-${slot}-${tag}`;
  const text = feature.sample || FEATURE_SAMPLES[tag] || (tag.startsWith('cv')?'ag':null);
  const before = clone(config), after = clone(config); before.features[tag]=0; after.features[tag]=value||1;
  return `<div class="feature"><div class="feature-main">${automatic?'<span class="engine-label">AUTO</span>':`<input type="checkbox" id="${id}" data-feature="${tag}" data-slot="${slot}" ${value?'checked':''}>`}<label ${automatic?'':`for="${id}"`}>${escapeHTML(label)}</label><span class="feature-tag" title="${feature.source}">${tag}</span></div>${feature.options?.length>1 ? `<select data-feature-option="${tag}" data-slot="${slot}" aria-label="Font ${slot.toUpperCase()} ${escapeHTML(label)} option"><option value="0">Default</option>${feature.options.map((option,i)=>`<option value="${i+1}" ${value===i+1?'selected':''}>${escapeHTML(option)}</option>`).join('')}</select>`:''}${text&&!automatic?`<div class="feature-example"><span style="${escapeHTML(fontStyle(before,23))}">${escapeHTML(text)}</span><span class="arrow">→</span><span style="${escapeHTML(fontStyle(after,23))}">${escapeHTML(text)}</span></div>`:''}</div>`;
}

function updateMetrics() {
  syncSizeControl();
  for (const slot of ['a','b']) {
    const config = state[slot], el = $(`#metrics-${slot}`); if (!config || !el) continue;
    const xHeight = measureUnits(config,'x').height;
    el.innerHTML = `<div class="metric-line"><span>Size</span><strong>${fmt(config.size,1)} pt</strong></div><div class="metric-line"><span>x-height</span><strong>${fmt(xHeight,0)} u</strong></div><div class="metric-line"><span>Units/em</span><strong>${face(config).upem}</strong></div>`;
  }
}
function markedText(text, config, highlights) {
  let html='', buffer='';
  const flush=()=>{html+=escapeHTML(buffer);buffer='';};
  for (const char of glyphs(text)) {
    if (!support(config,char)) { flush(); html+=`<span class="missing-char" title="Missing in ${escapeHTML(DATA[config.id].name)}: ${escapeHTML(codepoints(char))}" aria-label="Missing character ${escapeHTML(codepoints(char))}">${escapeHTML(codepoints(char))}</span>`; }
    else if(state.b&&highlights.has(char)) { flush(); html+=`<span class="difference-char" data-glyph="${escapeHTML(char)}" data-differences="${highlights.get(char).join(' ')}" title="${escapeHTML(describeGlyph(char))} · ${highlights.get(char).join(' + ')}">${escapeHTML(char)}</span>`; }
    else buffer+=char;
  }
  flush(); return html;
}
function rememberScroll() { if(!$('#text-view').hidden)$$('.text-pane').forEach(p=>scrollPositions[p.dataset.slot]=p.scrollTop); }
function renderText() {
  const s=sample(),highlights=highlightedCharacters();
  $('#text-view').innerHTML=['a','b'].filter(slot=>state[slot]).map(slot=>{
    const config=state[slot], missing=[...new Set(glyphs(fullSample()).filter(c=>!support(config,c)))];
    return `<article class="text-pane" data-slot="${slot}" tabindex="0" aria-label="Font ${slot.toUpperCase()} text specimen">${missing.length?`<div class="missing-notice">${missing.length} unavailable character${missing.length===1?'':'s'}</div>`:''}<div class="specimen-text" style="${escapeHTML(fontStyle(config))}">${s.title?`<h2>${markedText(s.title,config,highlights)}</h2>`:''}${s.paragraphs.map(p=>`<p class="${state.sample==='alphabet'?'alphabet-line':''}">${markedText(p,config,highlights)}</p>`).join('')}${s.foot?`<p class="small-sample">${markedText(s.foot,config,highlights)}</p>`:''}</div></article>`;
  }).join('');
  $$('.text-pane').forEach(p=>{
    p.scrollTop=scrollPositions[p.dataset.slot];
    p.addEventListener('scroll',()=>{
      scrollPositions[p.dataset.slot]=p.scrollTop;
      const other=$(`.text-pane[data-slot="${p.dataset.slot==='a'?'b':'a'}"]`);
      if(!other)return;
      const fraction=p.scrollTop/Math.max(1,p.scrollHeight-p.clientHeight);
      const target=fraction*(other.scrollHeight-other.clientHeight);
      if(Math.abs(other.scrollTop-target)>1)other.scrollTop=target;
    });
  });
}
function renderDifferences() {
  const drawer=$('#difference-drawer');
  drawer.hidden=!state.b;
  if(!state.b){drawer.innerHTML='';return;}
  const scroll=$('.glyph-strip',drawer)?.scrollLeft??0,ranked=rankedDifferences();
  const focused=drawer.contains(document.activeElement)?document.activeElement:null;
  const kinds=['shape','spacing'].filter(key=>state.highlights[key]);
  if(!kinds.length)kinds.push('shape','spacing');
  const max=Object.fromEntries(kinds.map(key=>[key,Math.max(...ranked.map(item=>item[key]),1e-9)]));
  drawer.innerHTML=`<div class="difference-top"><div class="difference-heading">Differences${ranking.pending?'<span class="ranking-progress" role="status" aria-label="Comparing glyphs"></span>':''}</div><div class="difference-actions" role="group" aria-label="Highlight differences">${['shape','spacing'].map(kind=>`<label class="highlight-toggle"><input type="checkbox" id="highlight-${kind}" data-highlight="${kind}" ${state.highlights[kind]?'checked':''}>${kind==='shape'?'Shape':'Spacing'}</label>`).join('')}</div></div><div class="glyph-strip" role="group" aria-label="Characters ranked by difference" aria-busy="${ranking.pending}">${ranked.map(({char,shape,spacing},i)=>`<button class="glyph-chip" data-glyph="${escapeHTML(char)}" title="${escapeHTML(describeGlyph(char))} · #${i+1} · Shape ${fmt(shape*100)}% · Spacing ${fmt(spacing,3)} em" aria-label="Inspect ${escapeHTML(describeGlyph(char))}" aria-pressed="${state.mode==='glyph'&&state.selected===char}"><span class="chip-letter" style="${escapeHTML(fontStyle(state.a,34))}">${escapeHTML(char)}</span>${kinds.map(key=>`<span class="chip-bar ${key}" aria-hidden="true"><i style="width:${({shape,spacing})[key]/max[key]*100}%"></i></span>`).join('')}</button>`).join('')}</div>`;
  $('.glyph-strip',drawer).scrollLeft=scroll;
  if(focused?.id)document.getElementById(focused.id)?.focus({preventScroll:true});
  else if(focused?.dataset.glyph)$$('.glyph-chip',drawer).find(el=>el.dataset.glyph===focused.dataset.glyph)?.focus({preventScroll:true});
}
function renderGlyph() {
  const name=characterNames.get(state.selected)??codepoints(state.selected);
  $('#glyph-view').innerHTML=`<div class="glyph-toolbar"><div class="glyph-navigation"><button class="nav-button" data-nav="-1" aria-label="Previous character">‹</button><label class="sr-only" for="glyph-input">Character to inspect</label><input class="glyph-input" id="glyph-input" value="${escapeHTML(state.selected)}" autocomplete="off" spellcheck="false"><button class="nav-button" data-nav="1" aria-label="Next character">›</button></div><span class="glyph-name" title="${escapeHTML(name)}">${escapeHTML(name)}</span></div><div class="glyph-stage">${(state.b?['a','overlay','b']:['a']).map(slot=>`<div class="glyph-cell" data-cell="${slot}"><div class="glyph-cell-label ${slot==='overlay'?'center-label':''}">${slot==='overlay'?'Overlay':`${escapeHTML(DATA[state[slot].id].short)}<span>${face(state[slot]).upem} units/em</span>`}</div><svg data-svg="${slot}" role="img" aria-label="${slot==='overlay'?`${escapeHTML(DATA[state.a.id].name)} in red, ${escapeHTML(DATA[state.b.id].name)} in blue, shared areas in black`:escapeHTML(DATA[state[slot].id].name)} for ${escapeHTML(describeGlyph(state.selected))}"></svg><div class="glyph-cell-metrics" data-glyph-metric="${slot}"></div></div>`).join('')}</div>`;
  renderCharacterName(state.selected);scheduleDraw();
}
function renderCenter() {
  rememberScroll();
  requestRankings();
  $('.comparison').classList.toggle('single',!state.b);
  $('#text-view').hidden=state.mode!=='text'; $('#glyph-view').hidden=state.mode!=='glyph';
  $$('.mode-control button').forEach(b=>b.setAttribute('aria-pressed',b.dataset.mode===state.mode));
  if(state.mode==='text')renderText(); else renderGlyph();
  renderDifferences();
}
function renderAll() {
  const oldScroll={a:$('#inspector-a').scrollTop,b:$('#inspector-b').scrollTop};
  renderInspector('a');renderInspector('b');
  for(const slot of ['a','b'])$(`#inspector-${slot}`).scrollTop=oldScroll[slot];
  $('#workspace').classList.toggle('hide-a',!state.showA);$('#workspace').classList.toggle('hide-b',!state.showB);
  $('#toggle-a').setAttribute('aria-pressed',state.showA);$('#toggle-b').setAttribute('aria-pressed',state.showB);
  syncSizeControl();$('#sample').value=state.sample;
  $('#match').disabled=!state.b;$('#swap').disabled=!state.b;
  $('#preset').value=state.preset;
  renderCenter();updateMetrics();updateUndo();
  ensureFonts();
}

// FontFace descriptors bake the selected axes and features into a configured
// face shared by DOM, SVG, and Canvas. Canvas can then measure actual ink bounds
// for variants too; SVG getBBox() measures the font cell, not the glyph's ink.
const measuringContext=document.createElement('canvas').getContext('2d');
function measure(config,text,pixels=fontSize(config)) {
  const key=JSON.stringify([config,text,pixels]);
  if(measurementCache.has(key))return measurementCache.get(key);
  measuringContext.font=`${config.axes.wght ?? 400} ${pixels}px "${configuredFamily(config)}"`;
  measuringContext.fontKerning=config.features.kern===0?'none':'normal';
  measuringContext.letterSpacing=`${config.tracking*pixels}px`;
  const m=measuringContext.measureText(text);
  const result={x:-m.actualBoundingBoxLeft,y:-m.actualBoundingBoxAscent,width:m.actualBoundingBoxLeft+m.actualBoundingBoxRight,height:m.actualBoundingBoxAscent+m.actualBoundingBoxDescent,advance:m.width};
  if(measurementCache.size>1000)measurementCache.clear();measurementCache.set(key,result);return result;
}
// At unitsPerEm CSS pixels, one pixel maps to one font design unit. Exclude
// specimen size and added tracking; preserve actual axes and substitutions.
function measureUnits(config,text){return measure({...config,tracking:0},text,face(config).upem);}
function scheduleDraw(){cancelAnimationFrame(drawFrame);drawFrame=requestAnimationFrame(drawGlyphs);}
function glyphFrame(slots){
  // One shared envelope for the specimen, independent of the selected character.
  // Reserve accents and descenders even when the reading sample lacks them.
  const candidates=[...new Set([...Array.from({length:94},(_,i)=>String.fromCodePoint(33+i)),...glyphs('ÁÅÉgj'+fullSample())])].filter(c=>!/^\s+$/u.test(c));
  const key=JSON.stringify([slots.map(s=>({...state[s],size:state[s].size/state.a.size})),candidates]);
  if(glyphFrameCache.has(key))return glyphFrameCache.get(key);
  const frame={width:20,ascent:50,descent:20};
  for(const slot of slots){
    const config=state[slot],pixels=100*config.size/state.a.size;
    for(const char of candidates){
      if(!support(config,char))continue;
      const m=measure(config,char,pixels);
      frame.width=Math.max(frame.width,m.width,m.advance);
      frame.ascent=Math.max(frame.ascent,-m.y);
      frame.descent=Math.max(frame.descent,m.y+m.height);
    }
  }
  if(glyphFrameCache.size>=12)glyphFrameCache.delete(glyphFrameCache.keys().next().value);
  glyphFrameCache.set(key,frame);return frame;
}
function glyphMetrics(config,char){
  const m=measureUnits(config,char),upem=face(config).upem;
  const values=[['Advance',m.advance],['LSB',m.x],['RSB',m.advance-m.x-m.width]];
  return `<table aria-label="${escapeHTML(DATA[config.id].name)} glyph metrics"><tbody>${values.map(([label,value])=>`<tr><th scope="row">${label}</th><td>${fmt(value,0)} u</td><td>${fmt(value/upem,3)} em</td></tr>`).join('')}</tbody></table>`;
}
function drawGlyphs(){
  if(state?.mode!=='glyph')return;
  const slots=['a','b'].filter(s=>state[s]);
  const boxes=slots.map(s=>$(`[data-svg="${s}"]`).getBoundingClientRect());
  if(!boxes[0]?.height)return;
  const width=Math.min(...boxes.map(b=>b.width)),height=Math.min(...boxes.map(b=>b.height));
  const frame=glyphFrame(slots),baseline=Math.round(height*.74);
  const factor=Math.max(.01,Math.min((width-24)/frame.width,(baseline-24)/frame.ascent,(height-baseline-24)/frame.descent,3.4));
  const sizes=Object.fromEntries(slots.map(s=>[s,100*state[s].size/state.a.size*factor]));
  const metrics=Object.fromEntries(slots.map(s=>[s,measure(state[s],state.selected,sizes[s])]));
  const maxInk=Math.max(...slots.map(s=>metrics[s].width));
  const maxAdvance=Math.max(...slots.map(s=>metrics[s].advance));
  for(const svg of $$('[data-svg]')){
    const slot=svg.dataset.svg,w=svg.getBoundingClientRect().width;
    svg.setAttribute('viewBox',`0 0 ${w} ${height}`);
    const applicable=slot==='overlay'?slots:[slot];
    const isOverlay=slot==='overlay';
    const textMarkup=(s,fill)=>{
      if(!support(state[s],state.selected))return '';
      const m=metrics[s],x=!spacingAlignment()?(w-(isOverlay?maxInk:m.width))/2-m.x:(w-(isOverlay?maxAdvance:m.advance))/2;
      return `<text x="${x}" y="${baseline}" fill="${fill}" style="${escapeHTML(fontStyle(state[s],sizes[s]))}">${escapeHTML(state.selected)}</text>`;
    };
    let contents='';
    contents+=`<path class="baseline-guide" d="M0 ${baseline}H${w}" stroke="#c0c4cb" stroke-width=".8"/><text x="3" y="${baseline+15}" fill="#626872" style="font:11px -apple-system,sans-serif">baseline</text>`;
    for(const s of applicable){
      const xheight=measure(state[s],'x',sizes[s]).height,y=baseline-xheight;
      contents+=`<path d="M0 ${y}H${w}" stroke="${s==='a'?'#c1595550':'#467dab50'}" stroke-dasharray="3 4" stroke-width=".8"/>`;
      if(s===applicable[0])contents+=`<text x="3" y="${y-6}" fill="#626872" style="font:11px -apple-system,sans-serif">x-height</text>`;
      if(state.highlights.spacing){
        const start=spacingAlignment()?(w-(isOverlay?maxAdvance:metrics[s].advance))/2:(w-(isOverlay?maxInk:metrics[s].width))/2-metrics[s].x;
        contents+=`<path d="M${start} 18V${height-10}M${start+metrics[s].advance} 18V${height-10}" stroke="${s==='a'?'#c1595580':'#467dab80'}" stroke-dasharray="2 4" stroke-width=".8"/>`;
      }
    }
    if(isOverlay){
      const both=slots.every(s=>support(state[s],state.selected));
      contents+=`<defs><mask id="mask-a" maskUnits="userSpaceOnUse" x="0" y="0" width="${w}" height="${height}">${textMarkup('a','white')}</mask><mask id="mask-b" maskUnits="userSpaceOnUse" x="0" y="0" width="${w}" height="${height}">${textMarkup('b','white')}</mask></defs><rect width="${w}" height="${height}" fill="#c15955" mask="url(#mask-a)"/><rect width="${w}" height="${height}" fill="#467dab" mask="url(#mask-b)"/><g mask="url(#mask-a)"><rect width="${w}" height="${height}" fill="#242527" mask="url(#mask-b)"/></g>`;
      if(!both)contents+=`<text x="${w/2}" y="${height-10}" text-anchor="middle" class="glyph-missing">Missing from ${!support(state.a,state.selected)?'A':'B'}</text>`;
    }else if(!support(state[slot],state.selected)){
      contents+=`<text x="${w/2}" y="${height/2}" text-anchor="middle" class="glyph-missing">Character unavailable</text>`;
    }else contents+=textMarkup(slot,'#27282b');
    svg.innerHTML=contents;
    const footer=$(`[data-glyph-metric="${slot}"]`);
    if(isOverlay)footer.textContent='';
    else footer.innerHTML=support(state[slot],state.selected)?glyphMetrics(state[slot],state.selected):'';
  }
}

function setMode(mode){rememberScroll();state.mode=mode;renderCenter();}
function selectGlyph(char){state.selected=char;setMode('glyph');$$('.glyph-chip').find(el=>el.dataset.glyph===char)?.scrollIntoView({block:'nearest',inline:'nearest'});}
function setStyle(config,style){
  config.style=style;
  config.axes=Object.fromEntries(face(config).axes.map(axis=>[axis.tag,config.axes[axis.tag]??axis.default]));
  config.features=Object.fromEntries(Object.entries(config.features).filter(([tag])=>face(config).features.some(feature=>feature.tag===tag)));
}
function setWeight(config,value,italic=face(config).label.toLowerCase().includes('italic')){
  const axis=face(config).axes.find(axis=>axis.tag==='wght');
  if(axis){config.axes.wght=clamp(Math.round(value),axis.min,axis.max);return;}
  const faces=Object.entries(DATA[config.id].faces);
  const matching=faces.filter(([,f])=>f.label.toLowerCase().includes('italic')===italic);
  const options=matching.length?matching:faces;
  const current=options.find(([key])=>key===config.style)??options[0];
  const nearest=options.reduce((best,entry)=>Math.abs(entry[1].weight-value)<Math.abs(best[1].weight-value)?entry:best,current);
  if(nearest[0]!==config.style)setStyle(config,nearest[0]);
}
function captureAppearanceLink(){
  if(!state.b){state.appearanceLink=null;return;}
  state.appearanceLink={
    weight:weight(state.b)-weight(state.a),size:state.b.size/state.a.size,
    tracking:state.b.tracking-state.a.tracking,
    axes:Object.fromEntries(Object.keys(state.a.axes).filter(tag=>tag in state.b.axes).map(tag=>[tag,state.b.axes[tag]-state.a.axes[tag]]))
  };
}
function propertyValue(slot,key){return key.startsWith('axis.')?state[slot].axes[key.slice(5)]:state[slot][key];}
function setProperty(slot,key,value){
  if(key==='axis.wght'){setWeight(state[slot],value);return;}
  if(key.startsWith('axis.')){
    const tag=key.slice(5),axis=face(state[slot]).axes.find(axis=>axis.tag===tag);
    if(axis)state[slot].axes[tag]=clamp(value,axis.min,axis.max);
  }else if(key==='size')state[slot].size=clamp(Math.round(value*10)/10,10,144);
  else if(key==='tracking')state[slot].tracking=clamp(Math.round(value*1000)/1000,-.12,.15);
}
function syncLinkedProperty(slot,key,italic){
  if(!state.appearanceLocked||!state.b)return;
  const other=slot==='a'?'b':'a',sign=slot==='a'?1:-1,link=state.appearanceLink;
  if(key==='weight'||key==='axis.wght')setWeight(state[other],weight(state[slot])+sign*link.weight,italic);
  else if(key==='size')setProperty(other,key,state[slot].size*(slot==='a'?link.size:1/link.size));
  else if(key==='tracking')setProperty(other,key,state[slot].tracking+sign*link.tracking);
  else if(key.startsWith('axis.')){const tag=key.slice(5);if(tag in state[other].axes)setProperty(other,key,state[slot].axes[tag]+sign*(link.axes[tag]??0));}
}
function syncAppearanceControls(activeInput){
  for(const slot of ['a','b']){
    if(!state[slot])continue;
    const root=$(`#inspector-${slot}`),selector=$(`[data-style="${slot}"]`);
    if(selector.value!==state[slot].style){const scroll=root.scrollTop;renderInspector(slot);root.scrollTop=scroll;}
    $$('[data-param]',root).forEach(input=>{
      const value=propertyValue(slot,input.dataset.param);
      if(input!==activeInput)input.value=value;
      if(input.type==='range')input.style.setProperty('--fill',`${(value-Number(input.min))/(Number(input.max)-Number(input.min))*100}%`);
    });
    $$('[data-reset-property]',root).forEach(button=>button.disabled=propertyValue(slot,button.dataset.resetProperty)===propertyDefault(slot,button.dataset.resetProperty));
    const staticWeight=$('.static-weight',root);if(staticWeight)staticWeight.textContent=weight(state[slot]);
  }
}
function changeConfigInput(input){
  const slot=input.dataset.slot,key=input.dataset.param;if(!Number.isFinite(input.valueAsNumber))return;
  if(inputTransaction!==input){snapshot();inputTransaction=input;}
  const value=clamp(input.valueAsNumber,Number(input.min),Number(input.max));
  setProperty(slot,key,value);syncLinkedProperty(slot,key);syncAppearanceControls(input);
  renderCenter();updateMetrics();
}
function setFeature(slot,tag,value){
  snapshot();state[slot].features[tag]=value;
  if(value){const partner=({pnum:'tnum',tnum:'pnum',lnum:'onum',onum:'lnum',sups:'subs',subs:'sups'})[tag];if(partner)state[slot].features[partner]=0;}
  const scroll=$(`#inspector-${slot}`).scrollTop;
  renderInspector(slot);$(`#inspector-${slot}`).scrollTop=scroll;renderCenter();updateMetrics();
  $(`#feature-${slot}-${tag}`)?.focus({preventScroll:true});
}
function resetFont(slot,kind){
  snapshot();
  if(kind==='appearance'){
    for(const side of state.appearanceLocked&&state.b?['a','b']:[slot]){
      const config=state[side];config.size=22;config.tracking=0;config.axes=Object.fromEntries(face(config).axes.map(a=>[a.tag,a.default]));
      if(!face(config).axes.length)setStyle(config,'regular');
    }
    captureAppearanceLink();
  }else state[slot].features={};
  renderAll();
}
function resetProperty(slot,key){snapshot();setProperty(slot,key,propertyDefault(slot,key));syncLinkedProperty(slot,key);renderAll();}
function chooseFont(slot,id){
  snapshot();
  if(!id&&slot==='b'){state.removedB=clone(state.b);state.b=null;}
  else if(slot==='b'&&!state.b&&state.removedB?.id===id)state.b=clone(state.removedB);
  else{
    const previous=state[slot]??(state.appearanceLocked?state.a:null),next=createFont(id);
    if(previous){
      next.size=previous.size;next.tracking=previous.tracking;
      for(const axis of face(next).axes)next.axes[axis.tag]=clamp(previous.axes[axis.tag]??axis.default,axis.min,axis.max);
      setWeight(next,weight(previous),face(previous).label.toLowerCase().includes('italic'));
    }
    state[slot]=next;
  }
  captureAppearanceLink();renderAll();
}
function applyPreset(preset){
  const ids=preset==='variable'?['inter','atkinson']:['helvetica','arial'];
  if(ids.some(id=>!DATA[id].available)){toast('This pair needs its fonts installed locally.');$('#preset').value=state.preset;return;}
  snapshot();state.a=createFont(ids[0]);state.b=createFont(ids[1]);state.preset=preset;state.showA=state.showB=true;captureAppearanceLink();renderAll();
}
function undo(){if(!history.length)return;state=history.pop();inputTransaction=null;renderAll();toast('Last change undone');}

function proposal(choices){
  const b=clone(state.b),a=state.a;
  if(choices.weight){
    const axis=face(b).axes.find(x=>x.tag==='wght');
    setWeight(b,weight(a)*(axis && a.id !== b.id ? 0.95 : 1));
  }
  if(choices.xheight){
    const ratio=(measureUnits(a,'x').height/face(a).upem)/(measureUnits(b,'x').height/face(b).upem);
    b.size=clamp(Math.round(a.size*ratio*10)/10,10,144);
  }
  if(choices.tracking){
    const text=fullSample().replace(/\s+/g,' ').trim(),count=Math.max(1,glyphs(text).length-1);
    if(text)b.tracking=clamp(Math.round((b.tracking+(measure(a,text).advance-measure(b,text).advance)/count/fontSize(b))*1000)/1000,-.12,.15);
  }
  return b;
}
function matchChoices(){return Object.fromEntries(['weight','xheight','tracking'].map(key=>[key,$(`#match-${key}`).checked]));}
function updateMatchPreview(){
  const choices=matchChoices(),b=proposal(choices);
  $('#preview-a').setAttribute('style',fontStyle(state.a,29));$('#preview-b').setAttribute('style',fontStyle(b,29*b.size/state.a.size));
  $('#apply-match').disabled=!Object.values(choices).some(Boolean);
  $('#preview-detail-b').textContent=`${weight(b)} · ${fmt(b.size,1)} pt`;
  const all={};
  for(const key of ['weight','xheight','tracking'])all[key]=proposal({...choices,[key]:true});
  const variable=face(state.b).axes.some(axis=>axis.tag==='wght');
  const oldWeight=variable?weight(state.b):face(state.b).label,newWeight=variable?weight(all.weight):face(all.weight).label;
  $('#match-weight-value').textContent=oldWeight===newWeight?newWeight:`${oldWeight} → ${newWeight}`;
  $('#match-xheight-value').textContent=`${fmt(state.b.size)} → ${fmt(all.xheight.size)} pt`;
  $('#match-tracking-value').textContent=`${fmt(state.b.tracking,3)} → ${fmt(all.tracking.tracking,3)} em`;
}
function openMatch(){
  if(!state.b)return;
  $('#match-dialog').innerHTML=`<div class="dialog-heading"><h2 id="match-title">Match</h2><button class="close-button" id="cancel-match-x" aria-label="Cancel matching">×</button></div><div class="match-reference"><strong>${escapeHTML(DATA[state.a.id].short)}</strong><span class="match-arrow">→</span><strong>${escapeHTML(DATA[state.b.id].short)}</strong></div><div class="match-options">
    <div class="match-option"><div class="match-option-top"><input id="match-weight" type="checkbox" checked><label for="match-weight">Weight</label><span class="match-option-value" id="match-weight-value"></span></div></div>
    <div class="match-option"><div class="match-option-top"><input id="match-xheight" type="checkbox"><label for="match-xheight">x-height</label><span class="match-option-value" id="match-xheight-value"></span></div></div>
    <div class="match-option"><div class="match-option-top"><input id="match-tracking" type="checkbox"><label for="match-tracking">Tracking</label><span class="match-option-value" id="match-tracking-value"></span></div></div></div>
    <div class="match-preview"><div><div class="preview-label">${weight(state.a)} · ${fmt(state.a.size,1)} pt</div><div class="match-preview-sample" id="preview-a">Hamburg</div></div><div><div class="preview-label" id="preview-detail-b"></div><div class="match-preview-sample" id="preview-b">Hamburg</div></div></div><div class="dialog-actions"><button id="cancel-match">Cancel</button><button class="primary-button" id="apply-match">Apply</button></div>`;
  updateMatchPreview();$('#match-dialog').showModal();
}
function openEditor(){ $('#custom-text').value=state.sample==='custom'?state.custom:fullSample();$('#text-dialog').showModal();$('#custom-text').focus(); }

document.addEventListener('click',event=>{
  const button=event.target.closest('button');const char=event.target.closest('[data-glyph]');
  if(char){selectGlyph(char.dataset.glyph);return;}
  if(!button||button.disabled)return;
  if(button.dataset.mode)setMode(button.dataset.mode);
  if(button.dataset.reset)resetFont(button.dataset.slot,button.dataset.reset);
  if(button.dataset.resetProperty)resetProperty(button.dataset.slot,button.dataset.resetProperty);
  if(button.dataset.nav){const list=navigationGlyphs();let index=list.indexOf(state.selected);selectGlyph(list[(Math.max(0,index)+Number(button.dataset.nav)+list.length)%list.length]);}
  if(button.dataset.action==='toggle-appearance-lock'){snapshot();state.appearanceLocked=!state.appearanceLocked;if(state.appearanceLocked)captureAppearanceLink();renderAll();}
  if(button.id==='undo')undo();
  if(button.id==='toggle-a'||button.id==='toggle-b'){const side=button.id.slice(-1);state[side==='a'?'showA':'showB']=!state[side==='a'?'showA':'showB'];renderAll();}
  if(button.id==='swap'){snapshot();[state.a,state.b]=[state.b,state.a];captureAppearanceLink();renderAll();}
  if(button.id==='match')openMatch();
  if(['cancel-match','cancel-match-x'].includes(button.id))$('#match-dialog').close();
  if(button.id==='apply-match'){snapshot();state.b=proposal(matchChoices());captureAppearanceLink();$('#match-dialog').close();renderAll();}
  if(button.id==='edit-text')openEditor();
});
document.addEventListener('input',event=>{
  const el=event.target;
  if(el.dataset.param)changeConfigInput(el);
  if(el.id==='text-size'&&Number.isFinite(el.valueAsNumber)){if(inputTransaction!==el){snapshot();inputTransaction=el;}for(const slot of ['a','b'])if(state[slot])setProperty(slot,'size',el.valueAsNumber);captureAppearanceLink();syncAppearanceControls(el);renderCenter();updateMetrics();}
});
document.addEventListener('change',event=>{
  const el=event.target;inputTransaction=null;
  if(el.dataset.param){const key=el.dataset.param;el.value=key.startsWith('axis.')?state[el.dataset.slot].axes[key.slice(5)]:state[el.dataset.slot][key];}
  if(el.id==='text-size')syncSizeControl(true);
  if(el.dataset.font)chooseFont(el.dataset.font,el.value);
  if(el.dataset.style){snapshot();const slot=el.dataset.style;setStyle(state[slot],el.value);syncLinkedProperty(slot,'weight',face(state[slot]).label.toLowerCase().includes('italic'));renderAll();}
  if(el.dataset.feature)setFeature(el.dataset.slot,el.dataset.feature,el.checked?1:0);
  if(el.dataset.featureOption)setFeature(el.dataset.slot,el.dataset.featureOption,Number(el.value));
  if(el.id==='preset')applyPreset(el.value);
  if(el.id==='sample'){if(el.value==='custom'){el.value=state.sample;openEditor();}else{snapshot();state.sample=el.value;scrollPositions.a=scrollPositions.b=0;$$('.text-pane').forEach(p=>p.scrollTop=0);renderCenter();}}
  if(el.dataset.highlight){state.highlights[el.dataset.highlight]=el.checked;renderCenter();}
  if(el.id==='glyph-input'){const char=glyphs(el.value)[0];if(char)selectGlyph(char);else el.value=state.selected;}
  if(['match-weight','match-xheight','match-tracking'].includes(el.id))updateMatchPreview();
});
$('#custom-form').addEventListener('submit',event=>{
  if(event.submitter?.value!=='save')return;
  snapshot();state.custom=$('#custom-text').value;state.sample='custom';scrollPositions.a=scrollPositions.b=0;$$('.text-pane').forEach(p=>p.scrollTop=0);renderAll();
});
document.addEventListener('keydown',event=>{
  const editing=event.target.matches('input,textarea,select,[contenteditable]');
  if((event.metaKey||event.ctrlKey)&&event.key.toLowerCase()==='z'&&!editing&&!$('dialog[open]')){event.preventDefault();undo();}
  if(event.key==='Enter'&&event.target.id==='glyph-input'){event.preventDefault();const char=glyphs(event.target.value)[0];if(char)selectGlyph(char);}
  if(state?.mode==='glyph'&&!editing&&!$('dialog[open]')&&['ArrowLeft','ArrowRight'].includes(event.key)){event.preventDefault();$(`[data-nav="${event.key==='ArrowLeft'?-1:1}"]`)?.click();}
});
new ResizeObserver(()=>scheduleDraw()).observe($('#specimen-area'));

async function init(){
  if(!DATA||!DATA.helvetica.available||!DATA.arial.available){$('#workspace').innerHTML='<div class="load-error">The mockup needs its local font server and the installed Helvetica Neue and Arial fonts.<br>Start with <code>python3 mockups/server.py</code>, then open <code>http://127.0.0.1:8765</code>.</div>';return;}
  configureFonts();
  await Promise.all(Object.values(DATA).flatMap(font=>Object.values(font.faces).map(async f=>{
    const response=await fetch(f.url);if(!response.ok)throw new Error('Font unavailable: '+f.family);
    fontBuffers.set(f.family,await response.arrayBuffer());
  })));
  state={a:createFont('helvetica'),b:createFont('arial'),removedB:null,preset:'classic',mode:'text',sample:'reading',custom:'',selected:'a',highlights:{shape:true,spacing:false},showA:true,showB:true,appearanceLocked:true,appearanceLink:null};
  captureAppearanceLink();
  $('#preset option[value="variable"]').disabled=!DATA.inter.available||!DATA.atkinson.available;
  renderAll();await document.fonts.ready;measurementCache.clear();renderCenter();updateMetrics();
  $('.window').inert=false;$('.window').setAttribute('aria-busy','false');
  window.typefaceoff={getState:()=>clone(state),getHistoryLength:()=>history.length,getRankings:()=>clone({...ranking,ranked:rankedDifferences()}),measure:(slot,text)=>measure(state[slot],text),measureUnits:(slot,text)=>measureUnits(state[slot],text),support:(slot,text)=>support(state[slot],text)};
}
init().catch(error=>{
  console.error(error);
  $('#workspace').innerHTML='<div class="load-error">A local font could not be loaded. Check that the mockup server is running, then reload this page.</div>';
});
