const appState = {
  visibility: 'private',
  archiveSource: 'spotify',
  archiveFilter: 'all',
  searchQuery: '',
  fxModes: ['FLYBY', 'SABER', 'LIGHTNING'],
  fxIndex: 0,
  lastSectorId: 'sector-01',
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
// 1. 60FPS BROWSER-FRIENDLY STARFIELD & COSMIC DUST ENGINE
// -------------------------------------------------------------------------
function initGalacticCanvas() {
  const canvas = document.getElementById('galacticCanvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  let width = (canvas.width = window.innerWidth);
  let height = (canvas.height = window.innerHeight);

  // Sparse, crisp starry dust particles (110 stars for 60fps efficiency)
  const stars = Array.from({ length: 110 }, () => ({
    x: Math.random() * width,
    y: Math.random() * height,
    r: Math.random() * 1.5 + 0.3,
    alpha: Math.random() * 0.75 + 0.15,
    twinkleSpeed: Math.random() * 0.015 + 0.004,
    parallax: Math.random() * 0.35 + 0.05
  }));

  window.addEventListener('resize', () => {
    width = canvas.width = window.innerWidth;
    height = canvas.height = window.innerHeight;
  });

  function renderFrame() {
    if (!document.hidden) {
      ctx.clearRect(0, 0, width, height);
      const isLight = document.body.classList.contains('light-polarity');
      const scrollY = window.scrollY || 0;

      for (const s of stars) {
        s.alpha += s.twinkleSpeed;
        if (s.alpha > 0.95 || s.alpha < 0.15) s.twinkleSpeed = -s.twinkleSpeed;
        const drawY = (s.y - scrollY * s.parallax) % height;
        const finalY = drawY < 0 ? drawY + height : drawY;

        ctx.beginPath();
        ctx.arc(s.x, finalY, s.r, 0, Math.PI * 2);
        ctx.fillStyle = isLight
          ? `rgba(15, 23, 42, ${s.alpha * 0.25})`
          : `rgba(255, 255, 255, ${s.alpha})`;
        ctx.fill();
      }
    }
    requestAnimationFrame(renderFrame);
  }
  requestAnimationFrame(renderFrame);
}

// -------------------------------------------------------------------------
// 2. LIGHTSABER KYBER ACCENT & POLARITY ENGINE
// -------------------------------------------------------------------------
function setSaberColor(hex, glow, soft) {
  document.documentElement.style.setProperty('--accent', hex);
  document.documentElement.style.setProperty('--accent-glow', glow);
  document.documentElement.style.setProperty('--accent-soft', soft);
  localStorage.setItem('nexus_v21_saber', JSON.stringify({ hex, glow, soft }));

  document.querySelectorAll('.kyber-crystal').forEach(btn => {
    btn.classList.toggle('active', btn.getAttribute('onclick').includes(hex));
  });
}

function togglePolarity() {
  const isLight = document.body.classList.toggle('light-polarity');
  localStorage.setItem('nexus_v21_polarity', isLight ? 'light' : 'dark');
  const btn = document.getElementById('polarityBtn');
  if (btn) btn.textContent = isLight ? '☀ HANGAR LANDED' : '◐ SPACE MODE';
}

// -------------------------------------------------------------------------
// 3. SCREEN TRANSITION FX (FLYBY / SABER SLASH / FORCE LIGHTNING)
// -------------------------------------------------------------------------
function cycleTransitionFxMode() {
  appState.fxIndex = (appState.fxIndex + 1) % appState.fxModes.length;
  const mode = appState.fxModes[appState.fxIndex];
  document.getElementById('fxModeBtn').textContent = `FX // ${mode}`;
  triggerTransitionFx(mode);
}

function triggerTransitionFx(forcedMode) {
  const overlay = document.getElementById('transitionFxOverlay');
  if (!overlay) return;
  const mode = forcedMode || appState.fxModes[appState.fxIndex];

  if (mode === 'FLYBY') {
    const el = document.createElement('div');
    el.className = 'flyby-ship';
    el.innerHTML = `
      <svg viewBox="0 0 280 80" width="280" height="80" fill="none">
        <line x1="0" y1="40" x2="210" y2="40" stroke="var(--accent)" stroke-width="3" stroke-dasharray="14 6"/>
        <polygon points="180,25 275,40 180,55 198,40" fill="#ffffff" stroke="var(--accent)" stroke-width="2"/>
        <circle cx="195" cy="40" r="6" fill="var(--accent)"/>
      </svg>
    `;
    overlay.appendChild(el);
    setTimeout(() => el.remove(), 900);
  } else if (mode === 'SABER') {
    const el = document.createElement('div');
    el.className = 'saber-slash-fx';
    overlay.appendChild(el);
    setTimeout(() => el.remove(), 700);
  } else if (mode === 'LIGHTNING') {
    const el = document.createElement('div');
    el.className = 'lightning-svg-fx';
    el.innerHTML = `
      <svg viewBox="0 0 1200 400" preserveAspectRatio="none" width="100%" height="100%" fill="none">
        <polyline points="0,180 210,120 390,230 580,95 790,240 980,130 1200,190" stroke="#ffffff" stroke-width="3.5"/>
        <polyline points="210,120 310,60 460,110" stroke="var(--accent)" stroke-width="2"/>
        <polyline points="580,95 690,290 860,260" stroke="var(--accent)" stroke-width="2"/>
      </svg>
    `;
    overlay.appendChild(el);
    setTimeout(() => el.remove(), 700);
  }
}

// -------------------------------------------------------------------------
// 4. SCROLL-LINKED STAGE & BACKGROUND SWITCHER
// -------------------------------------------------------------------------
function initScrollTransitions() {
  const stages = document.querySelectorAll('.cinematic-stage');
  const breakers = document.querySelectorAll('.sector-breaker');
  const navLinks = document.querySelectorAll('.hud-link');
  const bgArts = document.querySelectorAll('.sector-bg-art');

  const stageObserver = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('in-view');
        const id = entry.target.getAttribute('id');
        const bgId = entry.target.getAttribute('data-bg');

        if (id && id !== appState.lastSectorId) {
          appState.lastSectorId = id;
          triggerTransitionFx();
          localStorage.setItem('nexus_v2_sector', id);
          history.replaceState(null, '', `#${id}`);

          navLinks.forEach(link => {
            link.classList.toggle('active', link.getAttribute('data-sector') === id);
          });

          bgArts.forEach(art => {
            art.classList.toggle('active', art.getAttribute('id') === bgId);
          });
        }
      }
    });
  }, { threshold: 0.28 });

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
// 5. SPOTIFY LOGIN, SWITCH ACCOUNT & DISCONNECT (UNLINK)
// -------------------------------------------------------------------------
async function handleSpotifyConnect() {
  try {
    const res = await apiFetch('/api/v1/spotify/login');
    if (res.ok) {
      const data = await res.json();
      if (data.auth_url || data.url) {
        window.location.href = data.auth_url || data.url;
        return;
      }
    }
    window.location.href = '/api/v1/spotify/login';
  } catch (e) {
    window.location.href = '/api/v1/spotify/login';
  }
}

async function handleSpotifyDisconnect() {
  try {
    const res = await apiFetch('/api/v1/spotify/disconnect', { method: 'POST' });
    if (res.ok) {
      await loadAllArchives();
    }
  } catch (e) {}
}

// -------------------------------------------------------------------------
// 6. RELOAD BUTTON & GLOBAL TELEMETRY REFRESH
// -------------------------------------------------------------------------
async function triggerGlobalReload() {
  const icon = document.getElementById('reloadIcon');
  const reticle = document.getElementById('brandReticle');
  if (icon) {
    icon.classList.remove('spin-anim');
    void icon.offsetWidth;
    icon.classList.add('spin-anim');
  }
  if (reticle) {
    reticle.classList.remove('spin-anim');
    void reticle.offsetWidth;
    reticle.classList.add('spin-anim');
  }
  await Promise.all([loadAllArchives(), fetchTelemetry()]);
}

// -------------------------------------------------------------------------
// 7. SECTOR 01: UNIVERSAL TRANSMITTER
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
    label.textContent = 'AWAITING TRANSMISSION COORDINATES';
    return;
  }
  if (text.includes('youtube.com/') || text.includes('youtu.be/')) {
    const isList = text.includes('list=') || text.includes('/playlist');
    label.textContent = isList ? 'DETECTED // YOUTUBE PLAYLIST' : 'DETECTED // YOUTUBE SINGLE TRACK';
  } else if (text.includes('spotify.com/playlist/') || /^[a-zA-Z0-9]{22}$/.test(text)) {
    label.textContent = 'DETECTED // SPOTIFY PLAYLIST';
  } else {
    label.textContent = 'COORDINATES READY';
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
  feedback.textContent = '[ LOCKING HYPERDRIVE SIGNAL... ]';

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
      }, 400);
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
      }, 400);
    }
  } catch (err) {
    feedback.textContent = `[ FAILED: ${err.message.toUpperCase()} ]`;
  } finally {
    btn.disabled = false;
    btn.textContent = 'IGNITE TRANSMISSION ↵';
  }
}

// -------------------------------------------------------------------------
// 8. SECTOR 02: LIVE TELEMETRY & QUEUE MATRIX
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
      activeEl.innerHTML = `<div class="stream-slate" style="color:var(--fg-muted); font-family:var(--font-mono); font-size:12px;">[ NO ACTIVE TRANSCODING STREAMS ]</div>`;
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
            <span style="word-break:break-all;">#${String(idx + 1).padStart(2, '0')} // ${p.title || p.url}</span>
            <span style="color:var(--accent); margin-left:8px;">QUEUED</span>
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
            <span style="font-family:var(--font-mono); font-size:10px; color:${h.status === 'completed' ? 'var(--accent)' : '#ff1e1e'};">
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
// 9. SECTOR 03: HOLOCRON ARCHIVES & PLAYLIST DOWNLOAD SWITCH
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
      const hudBtn = document.getElementById('hudSpotifyBtn');
      const unlinkBtn = document.getElementById('hudSpotifyUnlinkBtn');
      const secText = document.getElementById('sectorSpotifyStatusText');
      const secConnBtn = document.getElementById('sectorSpotifyConnectBtn');
      const secDiscBtn = document.getElementById('sectorSpotifyDisconnectBtn');

      if (st.connected) {
        hudBtn.textContent = `🟢 SPOTIFY: LINKED`;
        unlinkBtn.style.display = 'inline-flex';
        secText.textContent = `CONNECTED // SPOTIFY ID: ${st.spotify_id || 'ACTIVE'}`;
        secConnBtn.textContent = '🔄 SWITCH SPOTIFY ACCOUNT';
        secDiscBtn.style.display = 'inline-flex';
      } else {
        hudBtn.textContent = `⚪ CONNECT SPOTIFY`;
        unlinkBtn.style.display = 'none';
        secText.textContent = 'NOT LINKED // CONNECT OAUTH OR USE IMPORTED LINKS';
        secConnBtn.textContent = '🔗 CONNECT SPOTIFY OAUTH';
        secDiscBtn.style.display = 'none';
      }
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
    container.innerHTML = `<div style="padding:50px 0; font-family:var(--font-mono); color:var(--fg-muted); letter-spacing:0.2em;">[ NO ARCHIVES MATCHING CURRENT SECTOR PARAMETERS ]</div>`;
    return;
  }

  container.innerHTML = filtered.map((item, idx) => {
    const id = item.spotify_id || item.spotify_playlist_id || item.id || '';
    const name = item.name || item.title || 'UNTITLED ARCHIVE';
    const cover = item.cover_url || item.image_url || '';
    const owner = (item.owner_username || item.owner || 'alvish').toUpperCase();
    const total = item.total_tracks ?? item.tracks_total ?? 0;
    const dl = item.downloaded_tracks ?? item.on_disk_count ?? 0;
    const pct = total > 0 ? Math.min(100, Math.round((dl / total) * 100)) : 0;
    const isSynced = Boolean(item.is_synced);
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
        <div class="holocron-owner" style="font-family:var(--font-mono); font-size:11px; letter-spacing:0.12em; color:var(--fg-muted);">
          👤 ${owner}
        </div>
        <div class="holocron-progress-col">
          <div style="display:flex; justify-content:space-between; font-family:var(--font-mono); font-size:11px; margin-bottom:6px;">
            <span>${dl} / ${total}</span>
            <span style="color:var(--accent);">${pct}%</span>
          </div>
          <div class="stream-bar-track">
            <div class="stream-bar-fill" style="width:${pct}%;"></div>
          </div>
        </div>

        <!-- PLAYLIST DOWNLOAD SWITCH BUTTON (SYNC ON/OFF) -->
        <div>
          <div class="saber-switch-wrap ${isSynced ? 'synced' : ''}" onclick="togglePlaylistSyncSwitch('${id}', ${!isSynced}, '${vis}', '${slug}')" title="Toggle Automatic Playlist Download Sync">
            <div class="saber-switch-track">
              <div class="saber-switch-knob"></div>
            </div>
            <span class="saber-switch-label" style="color:${isSynced ? 'var(--accent)' : 'var(--fg-muted)'};">
              ${isSynced ? 'SYNC ON' : 'SYNC OFF'}
            </span>
          </div>
        </div>

        <div class="holocron-vis">
          <button class="hud-btn" onclick="flipArchiveVis('${id}', ${isSynced}, '${vis}', '${slug}')">
            ${vis === 'public' ? '🌍 PUBLIC' : '🔒 PRIVATE'}
          </button>
        </div>

        <div style="display:flex; justify-content:flex-end; gap:6px;">
          <button class="hud-btn accent-outline" onclick="syncArchiveNow('${id}')" title="Force Sync Playlist Now">
            ⚡ SYNC
          </button>
          ${appState.archiveSource === 'imported' ? `
            <button class="hud-btn" style="border-color:#ff4d4d; color:#ff4d4d;" onclick="deleteImportedArchive('${id}')" title="Delete Imported Playlist">
              ✕
            </button>
          ` : ''}
        </div>
      </div>
    `;
  }).join('');
}

async function togglePlaylistSyncSwitch(spotifyId, nextSyncedState, currentVis, slug) {
  if (!spotifyId) return;
  await apiFetch(`/api/v1/playlists/${spotifyId}/configure`, {
    method: 'POST',
    body: JSON.stringify({
      is_synced: nextSyncedState,
      visibility: currentVis,
      folder_slug: slug === 'unindexed' ? '' : slug
    })
  });
  if (nextSyncedState) {
    await apiFetch(`/api/v1/playlists/${spotifyId}/sync`, { method: 'POST' });
  }
  await loadAllArchives();
  await fetchTelemetry();
}

async function syncArchiveNow(spotifyId) {
  if (!spotifyId) return;
  await apiFetch(`/api/v1/playlists/${spotifyId}/sync`, { method: 'POST' });
  triggerTransitionFx('SABER');
  await fetchTelemetry();
}

async function flipArchiveVis(spotifyId, isSynced, currentVis, slug) {
  if (!spotifyId) return;
  const nextVis = currentVis === 'public' ? 'private' : 'public';
  await apiFetch(`/api/v1/playlists/${spotifyId}/configure`, {
    method: 'POST',
    body: JSON.stringify({
      is_synced: isSynced,
      visibility: nextVis,
      folder_slug: slug === 'unindexed' ? '' : slug
    })
  });
  await loadAllArchives();
}

async function deleteImportedArchive(spotifyId) {
  if (!spotifyId) return;
  await apiFetch(`/api/v1/playlists/imported/${spotifyId}`, { method: 'DELETE' });
  await loadAllArchives();
}

// -------------------------------------------------------------------------
// 10. INTERACTIVE R2-D2 ASTROMECH CHIRP
// -------------------------------------------------------------------------
function chirpR2D2() {
  const phrases = [
    'BEEP-BOOP-WHEEE // HYPERDRIVE READY!',
    'CHIRP-BEEP // NAVIDROME SUBSONIC ONLINE!',
    'WHEEE-DOO // DEATH STAR TELEMETRY LOCKED!',
    'BOOP-BEEP // ALL TRACKS ENCODED AT 320KBPS!'
  ];
  const bubble = document.getElementById('r2SpeechBubble');
  if (bubble) {
    bubble.textContent = phrases[Math.floor(Math.random() * phrases.length)];
  }
  triggerTransitionFx('LIGHTNING');
}

// -------------------------------------------------------------------------
// 11. AUTHENTICATION & BOOTSTRAP
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
  initGalacticCanvas();

  try {
    const savedSaber = JSON.parse(localStorage.getItem('nexus_v21_saber'));
    if (savedSaber && savedSaber.hex) {
      setSaberColor(savedSaber.hex, savedSaber.glow, savedSaber.soft);
    }
  } catch (e) {}

  if (localStorage.getItem('nexus_v21_polarity') === 'light') {
    document.body.classList.add('light-polarity');
    const btn = document.getElementById('polarityBtn');
    if (btn) btn.textContent = '☀ HANGAR LANDED';
  }

  const savedSource = localStorage.getItem('nexus_v2_source') || 'spotify';
  switchArchiveSource(savedSource);

  initScrollTransitions();
  loadAllArchives();
  fetchTelemetry();
  setInterval(fetchTelemetry, 2500);

  const targetSector = window.location.hash.replace('#', '') || localStorage.getItem('nexus_v2_sector');
  if (targetSector && document.getElementById(targetSector)) {
    setTimeout(() => {
      document.getElementById(targetSector).scrollIntoView({ behavior: 'instant' });
    }, 120);
  }
});