const $ = id => document.getElementById(id);
const incoming = location.hash.slice(1);
if (incoming) { sessionStorage.setItem('reviewToken', incoming); history.replaceState(null, '', '/'); }
const token = sessionStorage.getItem('reviewToken');
let puzzles = [], reports = [], selected = null, dirty = false, saving = false;
async function api(path, data) {
  const response = await fetch(path, {method: data ? 'POST' : 'GET', headers: {Authorization: `Bearer ${token}`, 'Content-Type': 'application/json'}, body: data ? JSON.stringify(data) : undefined});
  const result = await response.json();
  if (!response.ok) throw Error(result.error);
  return result;
}
function tell(message) { $('message').textContent = message; }
function renderList() {
  const search = $('search').value.toLowerCase(), filter = $('filter').value;
  const visible = puzzles.filter(p => `${p.answer} ${p.id} ${p.generationWeek || ''}`.toLowerCase().includes(search) &&
    (filter === 'all' || (filter === 'retired' && p.retired) || (filter === 'active' && !p.retired) || (filter === 'reported' && reports.some(r => r.riddleId === p.id && r.status === 'open'))));
  $('count').textContent = `${visible.length} of ${puzzles.length} puzzles`;
  $('list').replaceChildren(...visible.map(p => {
    const button = document.createElement('button'); button.className = 'puzzle'; button.textContent = p.answer;
    button.setAttribute('aria-current', String(p.id === selected?.id));
    const note = document.createElement('small');
    const count = reports.filter(r => r.riddleId === p.id && r.status === 'open').length;
    note.textContent = `${p.retired ? 'Retired' : (p.difficulty || 'Not labeled')} · ${count} open reports`;
    button.append(note); button.onclick = () => { if (!saving && (!dirty || confirm('Discard unsaved changes?'))) choose(p); }; return button;
  }));
}
function choose(p) {
  selected = p; dirty = false; $('empty').hidden = true; $('editor').hidden = false;
  $('title').textContent = p.answer; $('identity').textContent = p.id; $('batch').textContent = p.generationWeek ? `Weekly batch · ${p.generationWeek}` : 'Original library';
  $('image').src = p.photoUrl;
  for (const name of ['answer', 'explanation', 'photoUrl']) $(name).value = p[name];
  for (let i = 0; i < 3; i++) $(`hint${i}`).value = p.hints[i] || '';
  $('difficulty').value = p.difficulty || ''; $('retired').checked = !!p.retired;
  $('reports').replaceChildren();
  const relevant = reports.filter(r => r.riddleId === p.id);
  if (!relevant.length) $('reports').textContent = 'No reports for this puzzle.';
  for (const report of relevant) {
    const article = document.createElement('article'), heading = document.createElement('strong'), text = document.createElement('p'), button = document.createElement('button');
    heading.textContent = `${{answer:'My answer should count',hint:'Confusing hint',image:'Image problem'}[report.reason] || report.reason} · ${report.status}`;
    text.textContent = `${report.answer ? `Player answer: ${report.answer}. ` : ''}${report.details || 'No additional details.'}`;
    button.textContent = report.status === 'open' ? 'Mark resolved' : 'Reopen report';
    button.onclick = async () => {
      button.disabled = true;
      try { await api('/api/report', {id: report.id, status: report.status === 'open' ? 'resolved' : 'open'}); await load(); }
      catch (error) { tell(error.message); button.disabled = false; }
    };
    article.append(heading, text, button); $('reports').append(article);
  }
  renderList();
}
async function load() {
  const data = await api('/api/data'); puzzles = data.puzzles.sort((a,b) => a.answer.localeCompare(b.answer)); reports = data.reports;
  renderList(); if (selected) choose(puzzles.find(p => p.id === selected.id));
  tell(`Loaded ${puzzles.length} puzzles and ${reports.length} reports${reports.length === data.reportLimit ? ' (latest 500)' : ''}.`);
}
$('form').oninput = () => { dirty = true; };
$('form').onsubmit = async event => {
  event.preventDefault(); if (saving) return;
  saving = true; $('save').disabled = true;
  try {
    await api('/api/puzzle', {id: selected.id, revision: selected.revision, answer: $('answer').value, explanation: $('explanation').value,
      hints: [0,1,2].map(i => $(`hint${i}`).value), difficulty: $('difficulty').value || null, photoUrl: $('photoUrl').value, retired: $('retired').checked});
    dirty = false; await load(); tell('Changes saved to Firebase.');
  } catch (error) { tell(error.message); }
  finally { saving = false; $('save').disabled = false; }
};
$('search').oninput = renderList; $('filter').onchange = renderList;
$('reload').onclick = () => { if (!saving && (!dirty || confirm('Discard unsaved changes?'))) load().catch(error => tell(error.message)); };
window.addEventListener('beforeunload', event => { if (dirty) { event.preventDefault(); event.returnValue = ''; } });
load().catch(error => tell(error.message));
