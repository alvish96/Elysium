
let fastPollCount = 0;
function triggerRapidTelemetryPoll() {
  fastPollCount = 35; // Poll every 400ms for the next 14 seconds
  fetchTelemetry();
}
setInterval(() => {
  if (fastPollCount > 0) {
    fastPollCount--;
    fetchTelemetry();
  }
}, 400);

async function handleSpotifyConnect() {
  const token = getToken();
  const feedback = document.getElementById('sectorSpotifyStatusText');
  if (feedback) feedback.textContent = 'Contacting Spotify OAuth relay...';

  try {
    const res = await apiFetch('/api/v1/spotify/login');
    if (res.ok) {
      const data = await res.json();
      const target = data.authorization_url || data.url || data.auth_url;
      if (target) {
        window.location.href = target;
        return;
      }
    }
  } catch (err) {
    console.warn("apiFetch error, attempting direct redirect:", err);
  }

  // Fallback: direct browser redirect passing token in query string
  if (token) {
    window.location.href = '/api/v1/spotify/login?token=' + encodeURIComponent(token);
  } else {
    if (feedback) feedback.textContent = 'Error: Not authenticated. Please sign in to Nexus first.';
    openAuthModal();
  }
}



async function handleSpotifyDisconnect() {
  try {
    const res = await apiFetch('/api/v1/spotify/disconnect', { method: 'POST' });
    if (res.ok) {
      await loadAllArchives();
    }
  } catch (e) {
    console.error("Disconnect error:", e);
  }
}


let telemetryTimer = null;

function setTelemetryInterval(ms) {
  if (telemetryTimer) clearInterval(telemetryTimer);
  telemetryTimer = setInterval(fetchTelemetry, ms);
}

const appState = {
  visibility: 'private',
  archiveSource: 'spotify',
  archiveFilter: 'all',
  searchQuery: '',
  fxModes: ['FLYBY', 'SABER', 'LIGHTNING'],
  fxIndex: 0,
  lastSectorId: 'sector-01',
  deletedIds: new Set(JSON.parse(localStorage.getItem('nexus_deleted_playlists') || '[]')),
  datasets: {
    spotify: [],
    imported: [],
    vault: []
  }
};

function getToken() {
  return (
    localStorage.getItem('nexus_token') ||
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
  const res = await fetch(path, Object.assign({ cache: 'no-store' }, options, { headers }));
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
  }, { rootMargin: '0px 0px -40px 0px', threshold: 0.02 });

  stages.forEach(s => stageObserver.observe(s));

  const breakerObserver = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('in-view');
      }
    });
  }, { rootMargin: '0px 0px -40px 0px', threshold: 0.01 });

  breakers.forEach(b => breakerObserver.observe(b));
}

// -------------------------------------------------------------------------
// 5. SPOTIFY LOGIN, SWITCH ACCOUNT & DISCONNECT (UNLINK)
// -------------------------------------------------------------------------




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
      triggerRapidTelemetryPoll();
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
    const res = await apiFetch('/api/v1/downloads/queue?_t=' + Date.now());
    if (!res.ok) return;
    const data = await res.json();

    const active = data.active || [];
    const pending = data.pending || [];
    const history = data.history || [];

    document.getElementById('statActiveCount').textContent = String(active.length).padStart(2, '0');
    if (active.length > 0) { setTelemetryInterval(650); } else { setTelemetryInterval(2500); }
    document.getElementById('statPendingCount').textContent = String(data.pending_count ?? pending.length).padStart(2, '0');
    document.getElementById('statCompletedCount').textContent = String(history.length).padStart(2, '0');

    const stateTag = document.getElementById('activeStreamStateTag');
    if (stateTag) {
      stateTag.textContent = active.length > 0
        ? `TRANSCODING ACTIVE // ${active.length} STREAM(S) LOCKED`
        : 'ORBITAL TRANSCODER // STANDBY';
      stateTag.style.color = active.length > 0 ? 'var(--accent)' : 'var(--fg-muted)';
    }

    const activeEl = document.getElementById('telemetryActiveList');
    if (active.length === 0) {
      activeEl.innerHTML = `
        <div class="idle-scanner-bar">
          <span>[ NO ACTIVE TRANSCODING STREAMS // AWAITING COORDINATES ]</span>
          <span style="color:var(--accent);">READY</span>
          <div class="idle-scanner-beam"></div>
        </div>
      `;
    } else {
      activeEl.innerHTML = active.map(t => {
        const taskId = t.id || t.task_id || t.title || '';
        return `
          <div class="active-stream-banner">
            <div style="display:flex; justify-content:space-between; align-items:center; gap:16px; flex-wrap:wrap;">
              <span style="font-weight:700; font-size:clamp(1.05rem, 1.8vw, 1.4rem); letter-spacing:-0.01em;">
                ${t.title || 'RESOLVING STREAM...'}
              </span>
              <div style="display:flex; align-items:center; gap:14px;">
                <span style="font-family:var(--font-mono); font-size:20px; color:var(--accent); font-weight:700; text-shadow:0 0 12px var(--accent-glow);">
                  ${Math.round(t.percent || 0)}%
                </span>
                <button class="hud-btn" style="border-color:#ff4d4d; color:#ff4d4d; padding:6px 12px;" onclick="cancelDownloadTask('${ String(taskId).replace(/'/g, "\'") }')" title="Cancel Active Download">
                  ✕ CANCEL
                </button>
              </div>
            </div>
            <div class="active-bar-track-lg">
              <div class="active-bar-fill-lg" style="width:${t.percent || 0}%;"></div>
            </div>
            <div class="breaker-meta" style="font-size:11px;">
              <span>TRANSFER RATE: <strong style="color:var(--fg);">${t.speed || '--'}</strong> // ETA: <strong style="color:var(--fg);">${t.eta || '--'}</strong></span>
              <span>OPERATOR // ${t.owner || 'ALVISH'}</span>
            </div>
          </div>
        `;
      }).join('');
    }

    const pendingEl = document.getElementById('telemetryPendingList');
    if (pending.length === 0) {
      pendingEl.innerHTML = `<div class="stream-slate" style="color:var(--fg-muted); font-family:var(--font-mono); font-size:12px;">[ QUEUE CLEAR // 0 PENDING ]</div>`;
    } else {
      pendingEl.innerHTML = pending.map((p, idx) => {
        const cancelKey = p.id || p.task_id || p.playlist_id || `idx-${idx}`;
        return `
          <div class="stream-slate">
            <div style="display:flex; justify-content:space-between; align-items:center; gap:10px; font-family:var(--font-mono); font-size:12px;">
              <span style="word-break:break-all;">#${String(idx + 1).padStart(2, '0')} // ${p.title || p.url}</span>
              <div style="display:flex; align-items:center; gap:8px; flex-shrink:0;">
                <span style="color:var(--accent); font-size:10px;">QUEUED</span>
                <button class="hud-btn" style="border-color:#ff4d4d; color:#ff4d4d; padding:4px 9px;" onclick="cancelDownloadTask('${ String(cancelKey).replace(/'/g, "\'") }')" title="Remove from Queue">
                  ✕ REMOVE
                </button>
              </div>
            </div>
          </div>
        `;
      }).join('');
    }

    const histEl = document.getElementById('telemetryHistoryList');
    if (history.length === 0) {
      histEl.innerHTML = `<div class="stream-slate" style="color:var(--fg-muted); font-family:var(--font-mono); font-size:12px;">[ NO RECENT ARCHIVES ]</div>`;
    } else {
      histEl.innerHTML = history.slice(0, 20).map(h => `
        <div class="stream-slate">
          <div style="display:flex; justify-content:space-between; align-items:center; gap:10px;">
            <span style="font-weight:600; font-size:13px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">
              ${h.artist ? h.artist + ' — ' : ''}${h.title}
            </span>
            <span style="font-family:var(--font-mono); font-size:10px; flex-shrink:0; color:${h.status === 'completed' ? 'var(--accent)' : '#ff1e1e'};">
              [${(h.status || 'DONE').toUpperCase()}]
            </span>
          </div>
          <div class="breaker-meta" style="font-size:10px;">
            <span style="white-space:nowrap; overflow:hidden; text-overflow:ellipsis; max-width:75%;">${h.file || '320KBPS MP3'}</span>
            <span>${h.completed_at ? new Date(h.completed_at).toLocaleTimeString([], {hour:'2-digit', minute:'2-digit'}) : ''}</span>
          </div>
        </div>
      `).join('');
    }
  } catch (e) {}
}

async function cancelDownloadTask(itemId) {
  if (!itemId) return;
  try {
    await apiFetch(`/api/v1/downloads/queue/${encodeURIComponent(itemId)}`, { method: 'DELETE' });
    triggerRapidTelemetryPoll();
  } catch (e) {
    console.error("Failed to cancel download:", e);
  }
}

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

  try {
    const delRes = await apiFetch('/api/v1/playlists/deleted');
    if (delRes.ok) {
      const delData = await delRes.json();
      appState.deletedIds = new Set(delData.deleted_ids || []);
      localStorage.setItem('nexus_deleted_playlists', JSON.stringify(Array.from(appState.deletedIds)));
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
  const deletedSet = appState.deletedIds || new Set();

  const visibleRaw = raw.filter(item => {
    const id = String(item.spotify_id || item.spotify_playlist_id || item.id || '');
    const slug = String(item.folder_slug || item.folder_path || '');
    return !deletedSet.has(id) && (!slug || !deletedSet.has(slug));
  });

  // Update active tab counter to reflect visible non-deleted items
  const badgeMap = { spotify: 'cntSpotify', imported: 'cntImported', vault: 'cntVault' };
  const activeBadge = document.getElementById(badgeMap[appState.archiveSource]);
  if (activeBadge) activeBadge.textContent = visibleRaw.length;

  const filtered = visibleRaw.filter(item => {
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
    const safeId = String(id).replace(/'/g, "\'");
    const safeSlug = String(slug).replace(/'/g, "\'");

    return `
      <div class="holocron-row">
        <div class="holocron-left-info">
          <div class="holocron-idx">${String(idx + 1).padStart(2, '0')}</div>
          ${cover ? `<img src="${cover}" class="holocron-art" loading="lazy" />` : `<div class="holocron-art"></div>`}
          <div class="holocron-title-wrap">
            <div class="holocron-title" title="${name.replace(/"/g, '&quot;')}">${name}</div>
            <div class="holocron-slug">/playlists/${slug}</div>
          </div>
        </div>

        <div class="holocron-right-actions">
          <div class="holocron-owner">👤 ${owner}</div>

          <div class="holocron-progress-col">
            <div style="display:flex; justify-content:space-between; font-family:var(--font-mono); font-size:11px; margin-bottom:6px;">
              <span>${dl} / ${total}</span>
              <span style="color:var(--accent);">${pct}%</span>
            </div>
            <div class="stream-bar-track">
              <div class="stream-bar-fill" style="width:${pct}%;"></div>
            </div>
          </div>

          <div class="saber-switch-wrap ${isSynced ? 'synced' : ''}" onclick="togglePlaylistSyncSwitch('${safeId}', ${!isSynced}, '${vis}', '${safeSlug}')" title="Toggle Automatic Playlist Download Sync">
            <div class="saber-switch-track">
              <div class="saber-switch-knob"></div>
            </div>
            <span class="saber-switch-label" style="color:${isSynced ? 'var(--accent)' : 'var(--fg-muted)'};">
              ${isSynced ? 'SYNC ON' : 'SYNC OFF'}
            </span>
          </div>

          <button class="hud-btn holocron-vis-btn" onclick="flipArchiveVis('${safeId}', ${isSynced}, '${vis}', '${safeSlug}')">
            ${vis === 'public' ? '🌍 PUBLIC' : '🔒 PRIVATE'}
          </button>

          <div class="holocron-sync-btn-group">
            <button class="hud-btn accent-outline" onclick="syncArchiveNow('${safeId}')" title="Force Sync Playlist Now">
              ⚡ SYNC
            </button>
            <button class="hud-btn" style="border-color:#ff4d4d; color:#ff4d4d; padding:8px 10px;" onclick="deleteArchiveFromProfile('${safeId}', '${safeSlug}')" title="Remove Playlist from Profile (Preserves Downloaded Songs)">
              ✕
            </button>
          </div>
        </div>
      </div>
    `;
  }).join('');
}

async function deleteArchiveFromProfile(playlistId, slug) {
  const targetKey = playlistId || slug;
  if (!targetKey) return;

  // 1. Optimistically remove from current UI view immediately
  if (!appState.deletedIds) appState.deletedIds = new Set();
  if (playlistId) appState.deletedIds.add(String(playlistId));
  if (slug && slug !== 'unindexed') appState.deletedIds.add(String(slug));
  localStorage.setItem('nexus_deleted_playlists', JSON.stringify(Array.from(appState.deletedIds)));
  renderArchives();

  try {
    // 2. Turn off auto-sync on the playlist if it has a Spotify ID
    if (playlistId) {
      await apiFetch(`/api/v1/playlists/${encodeURIComponent(playlistId)}/configure`, {
        method: 'POST',
        body: JSON.stringify({ is_synced: false, visibility: 'private', folder_slug: slug === 'unindexed' ? '' : slug })
      }).catch(() => {});

      // Also call imported delete endpoint if it was an imported playlist
      await apiFetch(`/api/v1/playlists/imported/${encodeURIComponent(playlistId)}`, {
        method: 'DELETE'
      }).catch(() => {});
    }

    // 3. Remove playlist from profile & delete .m3u8 folder (while preserving all .mp3 songs in /tracks)
    await apiFetch(`/api/v1/playlists/profile/${encodeURIComponent(targetKey)}?slug=${encodeURIComponent(slug || '')}`, {
      method: 'DELETE'
    });
  } catch (e) {
    console.error("Error removing playlist from profile:", e);
  }
}

async function restoreDeletedPlaylists() {
  try {
    await apiFetch('/api/v1/playlists/deleted/restore', { method: 'POST' });
    appState.deletedIds = new Set();
    localStorage.removeItem('nexus_deleted_playlists');
    await loadAllArchives();
  } catch (e) {}
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
  triggerRapidTelemetryPoll();
}

async function syncArchiveNow(spotifyId) {
  if (!spotifyId) return;
  await apiFetch(`/api/v1/playlists/${spotifyId}/sync`, { method: 'POST' });
  triggerTransitionFx('SABER');
  triggerRapidTelemetryPoll();
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
  setTelemetryInterval(3000);

  const targetSector = window.location.hash.replace('#', '') || localStorage.getItem('nexus_v2_sector');
  if (targetSector && document.getElementById(targetSector)) {
    setTimeout(() => {
      document.getElementById(targetSector).scrollIntoView({ behavior: 'instant' });
    }, 120);
  }
});