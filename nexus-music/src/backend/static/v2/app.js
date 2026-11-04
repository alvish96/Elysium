const appState = {
  visibility: 'private',
  archiveSource: 'spotify',
  archiveFilter: 'all',
  searchQuery: '',
  datasets: {
    spotify: [],
    imported: [],
    vault: []
  }
};

function getToken() {
  return (
    localStorage.getItem('nexus_token') ||
    localStorage.getItem('jwt_token') ||
    localStorage.getItem('token') ||
    localStorage.getItem('access_token') ||
    ''
  );
}

function saveToken(token, username) {
  localStorage.setItem('nexus_token', token);
  localStorage.setItem('jwt_token', token);
  localStorage.setItem('token', token);
  if (username) localStorage.setItem('nexus_username', username);
}

async function apiFetch(path, options = {}) {
  const token = getToken();
  const headers = Object.assign({ 'Content-Type': 'application/json' }, options.headers || {});
  if (token) headers['Authorization'] = `Bearer ${token}`;
  const res = await fetch(path, Object.assign({}, options, { headers }));
  if (res.status === 401 && !path.includes('/spotify/')) {
    document.getElementById('authModal').style.display = 'flex';
  }
  return res;
}

// -------------------------------------------------------------------------
// 1. CHANGEABLE KYBER ACCENT & POLARITY ENGINE
// -------------------------------------------------------------------------
function setAccent(hexColor) {
  document.documentElement.style.setProperty('--accent', hexColor);
  localStorage.setItem('nexus_v2_accent', hexColor);
  document.querySelectorAll('.kyber-crystal').forEach(btn => {
    btn.classList.toggle('active', btn.getAttribute('onclick').includes(hexColor));
  });
}

function togglePolarity() {
  const isLight = document.body.classList.toggle('light-polarity');
  localStorage.setItem('nexus_v2_polarity', isLight ? 'light' : 'dark');
}

// -------------------------------------------------------------------------
// 2. APPLE-STYLE SCROLL-TRIGGERED SCREEN TRANSITIONS & PERSISTENCE
// -------------------------------------------------------------------------
function initScrollTransitions() {
  const stages = document.querySelectorAll('.cinematic-stage');
  const breakers = document.querySelectorAll('.sector-breaker');
  const navLinks = document.querySelectorAll('.hud-link');

  const stageObserver = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('in-view');
        const id = entry.target.getAttribute('id');
        if (id) {
          localStorage.setItem('nexus_v2_sector', id);
          history.replaceState(null, '', `#${id}`);
          navLinks.forEach(link => {
            link.classList.toggle('active', link.getAttribute('data-sector') === id);
          });
        }
      }
    });
  }, { threshold: 0.22 });

  stages.forEach(s => stageObserver.observe(s));

  const breakerObserver = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('in-view');
      }
    });
  }, { threshold: 0.35 });

  breakers.forEach(b => breakerObserver.observe(b));
}

// -------------------------------------------------------------------------
// 3. SECTOR 01: UNIVERSAL TRANSMITTER (YOUTUBE & SPOTIFY)
// -------------------------------------------------------------------------
function setTransmissionVis(vis) {
  appState.visibility = vis;
  document.getElementById('visBtnPrivate').classList.toggle('active', vis === 'private');
  document.getElementById('visBtnPublic').classList.toggle('active', vis === 'public');
}

function detectCoordinateType(val) {
  const text = val.trim();
  const label = document.getElementById('protocolDetectorLabel');
  if (!text) {
    label.textContent = 'AWAITING COORDINATES';
    return;
  }
  if (text.includes('youtube.com/') || text.includes('youtu.be/')) {
    const isList = text.includes('list=') || text.includes('/playlist');
    label.textContent = isList ? 'DETECTED // YOUTUBE PLAYLIST' : 'DETECTED // YOUTUBE SINGLE TRACK';
  } else if (text.includes('spotify.com/playlist/') || /^[a-zA-Z0-9]{22}$/.test(text)) {
    label.textContent = 'DETECTED // SPOTIFY PLAYLIST';
  } else {
    label.textContent = 'COORDINATE FORMAT UNRECOGNIZED';
  }
}

async function fireTransmission() {
  const input = document.getElementById('universalUrlInput');
  const feedback = document.getElementById('transmissionFeedback');
  const btn = document.getElementById('btnInitiateTransmit');
  const url = input.value.trim();

  if (!url) {
    feedback.textContent = '[ ERROR: INPUT COORDINATES REQUIRED ]';
    return;
  }

  btn.disabled = true;
  btn.textContent = 'TRANSMITTING...';
  feedback.textContent = '[ LOCKING SIGNAL... ]';

  try {
    if (url.includes('youtube.com/') || url.includes('youtu.be/')) {
      const res = await apiFetch('/api/v1/downloads/youtube', {
        method: 'POST',
        body: JSON.stringify({ url: url, visibility: appState.visibility })
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.detail || 'Transmission rejected');
      feedback.textContent = `[ ✓ ${data.message.toUpperCase()} ]`;
      input.value = '';
      await fetchTelemetry();
      setTimeout(() => {
        document.getElementById('sector-02').scrollIntoView({ behavior: 'smooth' });
      }, 450);
    } else {
      const res = await apiFetch('/api/v1/playlists/import', {
        method: 'POST',
        body: JSON.stringify({ url_or_id: url, visibility: appState.visibility, auto_sync: true })
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.detail || 'Spotify import rejected');
      feedback.textContent = '[ ✓ SPOTIFY ARCHIVE IMPORTED ]';
      input.value = '';
      await loadAllArchives();
      setTimeout(() => {
        switchArchiveSource('imported');
        document.getElementById('sector-03').scrollIntoView({ behavior: 'smooth' });
      }, 450);
    }
  } catch (err) {
    feedback.textContent = `[ FAILED: ${err.message.toUpperCase()} ]`;
  } finally {
    btn.disabled = false;
    btn.textContent = 'INITIATE TRANSMISSION ↵';
  }
}

// -------------------------------------------------------------------------
// 4. SECTOR 02: LIVE TELEMETRY & QUEUE MATRIX
// -------------------------------------------------------------------------
async function fetchTelemetry() {
  try {
    const res = await apiFetch('/api/v1/downloads/queue');
    if (!res.ok) return;
    const data = await res.json();

    const active = data.active || [];
    const pending = data.pending || [];
    const history = data.history || [];

    document.getElementById('statActiveCount').textContent = String(active.length).padStart(2, '0');
    document.getElementById('statPendingCount').textContent = String(data.pending_count ?? pending.length).padStart(2, '0');
    document.getElementById('statCompletedCount').textContent = String(history.length).padStart(2, '0');

    const activeEl = document.getElementById('telemetryActiveList');
    if (active.length === 0) {
      activeEl.innerHTML = `<div class="stream-slate" style="color:var(--fg-muted); font-family:var(--font-mono); font-size:12px;">[ NO ACTIVE STREAMS ]</div>`;
    } else {
      activeEl.innerHTML = active.map(t => `
        <div class="stream-slate">
          <div style="display:flex; justify-content:space-between; align-items:center;">
            <span style="font-weight:700; font-size:15px;">${t.title || 'RESOLVING...'}</span>
            <span style="font-family:var(--font-mono); color:var(--accent); font-weight:700;">${Math.round(t.percent || 0)}%</span>
          </div>
          <div class="stream-bar-track">
            <div class="stream-bar-fill" style="width:${t.percent || 0}%;"></div>
          </div>
          <div class="breaker-meta" style="font-size:10px;">
            <span>SPEED: ${t.speed || '--'} // ETA: ${t.eta || '--'}</span>
            <span>CMD // ${t.owner || 'ALVISH'}</span>
          </div>
        </div>
      `).join('');
    }

    const pendingEl = document.getElementById('telemetryPendingList');
    if (pending.length === 0) {
      pendingEl.innerHTML = `<div class="stream-slate" style="color:var(--fg-muted); font-family:var(--font-mono); font-size:12px;">[ QUEUE CLEAR ]</div>`;
    } else {
      pendingEl.innerHTML = pending.map((p, idx) => `
        <div class="stream-slate">
          <div style="display:flex; justify-content:space-between; font-family:var(--font-mono); font-size:12px;">
            <span>#${String(idx + 1).padStart(2, '0')} // ${p.title || p.url}</span>
            <span style="color:var(--accent);">STANDBY</span>
          </div>
        </div>
      `).join('');
    }

    const histEl = document.getElementById('telemetryHistoryList');
    if (history.length === 0) {
      histEl.innerHTML = `<div class="stream-slate" style="color:var(--fg-muted); font-family:var(--font-mono); font-size:12px;">[ NO RECENT ARCHIVES ]</div>`;
    } else {
      histEl.innerHTML = history.slice(0, 8).map(h => `
        <div class="stream-slate">
          <div style="display:flex; justify-content:space-between; align-items:center;">
            <span style="font-weight:600; font-size:13px;">${h.artist ? h.artist + ' — ' : ''}${h.title}</span>
            <span style="font-family:var(--font-mono); font-size:10px; color:${h.status === 'completed' ? 'var(--accent)' : '#ff2a2a'};">
              [${(h.status || 'DONE').toUpperCase()}]
            </span>
          </div>
          <div class="breaker-meta" style="font-size:10px;">
            <span>${h.file || '320KBPS MP3'}</span>
            <span>${h.completed_at ? new Date(h.completed_at).toLocaleTimeString([], {hour:'2-digit', minute:'2-digit'}) : ''}</span>
          </div>
        </div>
      `).join('');
    }
  } catch (e) {}
}

// -------------------------------------------------------------------------
// 5. SECTOR 03: HOLOCRON VAULT PLAYLIST ARCHIVES
// -------------------------------------------------------------------------
async function loadAllArchives() {
  try {
    const meRes = await apiFetch('/api/v1/auth/me');
    if (meRes.ok) {
      const me = await meRes.json();
      document.getElementById('hudUserBtn').textContent = `CMD // ${(me.username || 'ALVISH').toUpperCase()}`;
    }
  } catch (e) {}

  try {
    const spRes = await apiFetch('/api/v1/spotify/status');
    if (spRes.ok) {
      const st = await spRes.json();
      document.getElementById('spotifyConnReadout').textContent = st.connected
        ? 'SPOTIFY OAUTH // ONLINE'
        : 'SPOTIFY OAUTH // OFFLINE';
    }
  } catch (e) {}

  const sources = [
    ['spotify', '/api/v1/spotify/playlists', 'cntSpotify'],
    ['imported', '/api/v1/playlists/imported', 'cntImported'],
    ['vault', '/api/v1/playlists/vault', 'cntVault']
  ];

  for (const [key, url, badgeId] of sources) {
    try {
      const res = await apiFetch(url);
      if (res.ok) {
        const data = await res.json();
        const list = Array.isArray(data) ? data : (data.items || data.playlists || []);
        appState.datasets[key] = list;
        document.getElementById(badgeId).textContent = list.length;
      }
    } catch (e) {}
  }

  renderArchives();
}

function switchArchiveSource(source) {
  appState.archiveSource = source;
  localStorage.setItem('nexus_v2_source', source);
  document.querySelectorAll('[data-source]').forEach(btn => {
    btn.classList.toggle('active', btn.getAttribute('data-source') === source);
  });
  renderArchives();
}

function setArchiveFilter(filter) {
  appState.archiveFilter = filter;
  renderArchives();
}

function filterArchives(q) {
  appState.searchQuery = q.trim().toLowerCase();
  renderArchives();
}

function renderArchives() {
  const container = document.getElementById('holocronArchiveList');
  const raw = appState.datasets[appState.archiveSource] || [];

  const filtered = raw.filter(item => {
    const name = (item.name || item.title || '').toLowerCase();
    const slug = (item.folder_slug || item.folder_path || '').toLowerCase();
    if (appState.searchQuery && !name.includes(appState.searchQuery) && !slug.includes(appState.searchQuery)) {
      return false;
    }
    const isSynced = Boolean(item.is_synced || item.sync_status === 'synced');
    const vis = (item.visibility || 'private').toLowerCase();
    if (appState.archiveFilter === 'synced' && !isSynced) return false;
    if (appState.archiveFilter === 'unsynced' && isSynced) return false;
    if (appState.archiveFilter === 'public' && vis !== 'public') return false;
    if (appState.archiveFilter === 'private' && vis !== 'private') return false;
    return true;
  });

  document.getElementById('vaultCountEyebrow').textContent = `${filtered.length} ARCHIVES IN SECTOR`;

  if (filtered.length === 0) {
    container.innerHTML = `<div style="padding:60px 0; font-family:var(--font-mono); color:var(--fg-muted); letter-spacing:0.2em;">[ NO ARCHIVES MATCHING CURRENT SECTOR PARAMETERS ]</div>`;
    return;
  }

  container.innerHTML = filtered.map((item, idx) => {
    const id = item.spotify_id || item.id || '';
    const name = item.name || item.title || 'UNTITLED ARCHIVE';
    const cover = item.cover_url || item.image_url || '';
    const owner = (item.owner_username || item.owner || 'alvish').toUpperCase();
    const total = item.total_tracks ?? item.tracks_total ?? 0;
    const dl = item.downloaded_tracks ?? item.on_disk_count ?? 0;
    const pct = total > 0 ? Math.min(100, Math.round((dl / total) * 100)) : 0;
    const vis = (item.visibility || 'private').toLowerCase();
    const slug = item.folder_slug || item.folder_path || 'unindexed';

    return `
      <div class="holocron-row">
        <div class="holocron-idx">${String(idx + 1).padStart(2, '0')}</div>
        <div>
          ${cover ? `<img src="${cover}" class="holocron-art" loading="lazy" />` : `<div class="holocron-art"></div>`}
        </div>
        <div>
          <div class="holocron-title">${name}</div>
          <div class="holocron-slug">/playlists/${slug}</div>
        </div>
        <div class="holocron-owner" style="font-family:var(--font-mono); font-size:11px; letter-spacing:0.14em; color:var(--fg-muted);">
          CMD // ${owner}
        </div>
        <div>
          <div style="display:flex; justify-content:space-between; font-family:var(--font-mono); font-size:11px; margin-bottom:6px;">
            <span>${dl} / ${total}</span>
            <span style="color:var(--accent);">${pct}%</span>
          </div>
          <div class="stream-bar-track">
            <div class="stream-bar-fill" style="width:${pct}%;"></div>
          </div>
        </div>
        <div class="holocron-vis">
          <button class="hud-btn" onclick="flipArchiveVis('${id}', '${vis}', '${slug}')">
            ${vis === 'public' ? '🌍 PUBLIC' : '🔒 PRIVATE'}
          </button>
        </div>
        <div style="text-align:right;">
          <button class="hud-btn" style="border-color:var(--fg);" onclick="syncArchiveNow('${id}')">
            [ SYNC ↻ ]
          </button>
        </div>
      </div>
    `;
  }).join('');
}

async function syncArchiveNow(spotifyId) {
  if (!spotifyId) return;
  await apiFetch(`/api/v1/playlists/${spotifyId}/sync`, { method: 'POST' });
  fetchTelemetry();
}

async function flipArchiveVis(spotifyId, currentVis, slug) {
  if (!spotifyId) return;
  const nextVis = currentVis === 'public' ? 'private' : 'public';
  await apiFetch(`/api/v1/playlists/${spotifyId}/configure`, {
    method: 'POST',
    body: JSON.stringify({ is_synced: true, visibility: nextVis, folder_slug: slug })
  });
  loadAllArchives();
}

// -------------------------------------------------------------------------
// 6. AUTHENTICATION & INITIALIZATION
// -------------------------------------------------------------------------
function openAuthModal() {
  document.getElementById('authModal').style.display = 'flex';
}

async function submitCommandAuth() {
  const username = document.getElementById('authUser').value.trim();
  const password = document.getElementById('authPass').value;
  const errEl = document.getElementById('authErr');
  errEl.style.display = 'none';

  try {
    const res = await fetch('/api/v1/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password })
    });
    const data = await res.json();
    if (res.ok && data.access_token) {
      saveToken(data.access_token, username);
      document.getElementById('authModal').style.display = 'none';
      loadAllArchives();
      fetchTelemetry();
    } else {
      errEl.textContent = `[ ACCESS DENIED: ${data.detail || 'INVALID CREDENTIALS'} ]`;
      errEl.style.display = 'block';
    }
  } catch (e) {
    errEl.textContent = '[ TRANSMISSION FAILURE ]';
    errEl.style.display = 'block';
  }
}

window.addEventListener('DOMContentLoaded', () => {
  // Restore saved Kyber Accent & Polarity
  const savedAccent = localStorage.getItem('nexus_v2_accent') || '#00f0ff';
  setAccent(savedAccent);

  if (localStorage.getItem('nexus_v2_polarity') === 'light') {
    document.body.classList.add('light-polarity');
  }

  const savedSource = localStorage.getItem('nexus_v2_source') || 'spotify';
  switchArchiveSource(savedSource);

  initScrollTransitions();
  loadAllArchives();
  fetchTelemetry();
  setInterval(fetchTelemetry, 2500);

  // Restore scroll sector on reload
  const targetSector = window.location.hash.replace('#', '') || localStorage.getItem('nexus_v2_sector');
  if (targetSector && document.getElementById(targetSector)) {
    setTimeout(() => {
      document.getElementById(targetSector).scrollIntoView({ behavior: 'instant' });
    }, 120);
  }
});