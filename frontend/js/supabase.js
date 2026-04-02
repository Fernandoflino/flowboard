// ============================================================
// supabase.js — Cliente Supabase + Utilitários globais
// ============================================================

// ── CONFIGURAÇÃO ─────────────────────────────────────────────
// Substitua pelos valores do seu projeto (Passo 10 do guia)
const SUPABASE_URL  = 'https://rdsnjeqrywetelhosyuk.supabase.co';
const SUPABASE_KEY  = 'sb_publishable_NpUk4qAGDMiBRz80zwTclQ_TQP1lkcg';

const { createClient } = supabase;
const db = createClient(SUPABASE_URL, SUPABASE_KEY);

// ── ESTADO GLOBAL ────────────────────────────────────────────
const App = {
  user:      null,
  profile:   null,
  workspace: null,   // workspace ativo
};

// ── AUTENTICAÇÃO ─────────────────────────────────────────────
async function getSession() {
  const { data: { session } } = await db.auth.getSession();
  return session;
}

async function requireAuth() {
  const session = await getSession();
  if (!session) {
    window.location.href = '/login.html';
    return null;
  }
  App.user = session.user;
  const { data: profile } = await db
    .from('profiles')
    .select('*')
    .eq('id', session.user.id)
    .single();
  App.profile = profile;
  return session;
}

async function signOut() {
  await db.auth.signOut();
  window.location.href = '/login.html';
}

// ── TOAST ─────────────────────────────────────────────────────
function toast(msg, type = 'info', duration = 3500) {
  let container = document.getElementById('toast-container');
  if (!container) {
    container = document.createElement('div');
    container.id = 'toast-container';
    document.body.appendChild(container);
  }
  const icons = { success: '✓', error: '✕', info: 'ℹ' };
  const t = document.createElement('div');
  t.className = `toast toast-${type}`;
  t.innerHTML = `<span>${icons[type]}</span><span>${msg}</span>`;
  container.appendChild(t);
  setTimeout(() => { t.style.opacity = '0'; t.style.transform = 'translateX(40px)';
    t.style.transition = 'all .3s'; setTimeout(() => t.remove(), 300); }, duration);
}

// ── MODAL ─────────────────────────────────────────────────────
function openModal(id)  { document.getElementById(id)?.classList.add('open'); }
function closeModal(id) { document.getElementById(id)?.classList.remove('open'); }
// Fechar ao clicar fora
document.addEventListener('click', e => {
  if (e.target.classList.contains('modal-overlay')) {
    e.target.classList.remove('open');
  }
});

// ── DROPDOWN ──────────────────────────────────────────────────
document.addEventListener('click', e => {
  const trigger = e.target.closest('[data-dropdown]');
  if (trigger) {
    e.stopPropagation();
    const menu = document.getElementById(trigger.dataset.dropdown);
    menu?.closest('.dropdown')?.classList.toggle('open');
    return;
  }
  document.querySelectorAll('.dropdown.open').forEach(d => d.classList.remove('open'));
});

// ── FORMATAÇÃO DE DATA ────────────────────────────────────────
function fmtDate(iso) {
  if (!iso) return '—';
  return new Date(iso).toLocaleDateString('pt-BR', { day:'2-digit', month:'short', year:'numeric' });
}
function fmtDateTime(iso) {
  if (!iso) return '—';
  return new Date(iso).toLocaleString('pt-BR', { day:'2-digit', month:'short', hour:'2-digit', minute:'2-digit' });
}
function timeAgo(iso) {
  const diff = Date.now() - new Date(iso);
  const m = Math.floor(diff / 60000);
  if (m < 1) return 'agora';
  if (m < 60) return `${m}m atrás`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h atrás`;
  return fmtDate(iso);
}

// ── AVATAR ────────────────────────────────────────────────────
function avatarHtml(name, url = null, size = '') {
  const initials = (name || '?').split(' ').slice(0,2).map(w => w[0]).join('').toUpperCase();
  const cls = `avatar ${size}`;
  if (url) return `<div class="${cls}"><img src="${url}" alt="${name}"></div>`;
  return `<div class="${cls}" title="${name}">${initials}</div>`;
}

// ── BADGE STATUS ──────────────────────────────────────────────
function statusBadge(status) {
  const map = {
    active:    ['badge-blue',   'Ativo'],
    completed: ['badge-green',  'Concluído'],
    overdue:   ['badge-red',    'Atrasado'],
    archived:  ['badge-gray',   'Arquivado'],
  };
  const [cls, label] = map[status] || ['badge-gray', status];
  return `<span class="badge ${cls}">${label}</span>`;
}

// ── INICIALIZAR TOPBAR ────────────────────────────────────────
async function initTopbar(activeWorkspaceId = null) {
  const session = await requireAuth();
  if (!session) return;

  const topbar = document.getElementById('topbar');
  if (!topbar) return;

  // Busca workspaces do usuário
  const { data: memberships } = await db
    .from('workspace_members')
    .select('workspace_id, role, workspaces(id, name)')
    .eq('user_id', App.user.id);

  const workspaces = memberships?.map(m => m.workspaces) || [];
  const current = workspaces.find(w => w.id === activeWorkspaceId) || workspaces[0];
  if (current) App.workspace = current;

  const wsOptions = workspaces.map(w =>
    `<div class="dropdown-item" onclick="switchWorkspace('${w.id}')">
       <span>🏢</span> ${w.name}
     </div>`
  ).join('');

  topbar.innerHTML = `
    <div class="topbar-logo">FLOW<span>BOARD</span></div>
    <div class="dropdown">
      <button class="btn btn-ghost btn-sm" data-dropdown="ws-menu" style="gap:6px">
        🏢 ${current?.name || 'Workspace'} <span style="opacity:.5">▾</span>
      </button>
      <div class="dropdown-menu" id="ws-menu">
        ${wsOptions}
        <div class="dropdown-sep"></div>
        <div class="dropdown-item" onclick="openModal('modal-new-workspace')">
          <span>＋</span> Novo workspace
        </div>
      </div>
    </div>
    <input class="topbar-search" placeholder="🔍  Buscar cartões..." id="global-search"
           onkeydown="if(event.key==='Enter') globalSearch(this.value)">
    <div class="topbar-right">
      <a href="/pages/dashboard.html" class="btn btn-ghost btn-sm btn-icon" title="Home">⊞</a>
      <div class="dropdown">
        <button data-dropdown="user-menu" style="background:none;border:none;cursor:pointer">
          ${avatarHtml(App.profile?.full_name)}
        </button>
        <div class="dropdown-menu" id="user-menu">
          <div style="padding:12px 14px;border-bottom:1px solid var(--border)">
            <div style="font-weight:600">${App.profile?.full_name}</div>
            <div class="text-sm text-muted">${App.user.email}</div>
            ${App.profile?.global_role === 'MASTER' ? '<span class="badge badge-yellow" style="margin-top:4px">MASTER</span>' : ''}
          </div>
          <a class="dropdown-item" href="/pages/profile.html"><span>👤</span> Meu perfil</a>
          <div class="dropdown-sep"></div>
          <div class="dropdown-item danger" onclick="signOut()"><span>⇤</span> Sair</div>
        </div>
      </div>
    </div>
  `;
}

function switchWorkspace(id) {
  localStorage.setItem('activeWorkspace', id);
  window.location.href = `/pages/dashboard.html?ws=${id}`;
}

function globalSearch(q) {
  if (q.trim()) window.location.href = `/pages/dashboard.html?search=${encodeURIComponent(q)}`;
}
