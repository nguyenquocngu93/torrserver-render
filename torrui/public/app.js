// TorrUI v2 - NZB360-style Frontend with Jackett Search
const API = "/api";
let allTorrents = [];
let currentPage = "dashboard";

// ============ Init ============
document.addEventListener("DOMContentLoaded", () => {
  checkConnection();
  loadTorrents();
  document.getElementById("searchInput")?.addEventListener("keypress", (e) => {
    if (e.key === "Enter") performSearch();
  });
});

// ============ API ============
async function api(endpoint, options = {}) {
  const res = await fetch(`${API}${endpoint}`, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  return res.json();
}

// ============ Connection ============
async function checkConnection() {
  try {
    const data = await api("/echo");
    document.getElementById("connectionStatus").textContent = `v${data.version}`;
    document.getElementById("torrserverVersion").textContent = `v${data.version} - San sang`;
    document.getElementById("statusBadge").classList.add("connected");
    document.getElementById("infoVersion").textContent = data.version;
    document.getElementById("infoStatus").textContent = "Online";
    document.getElementById("settingsUrl").value = data.url;
  } catch (err) {
    document.getElementById("connectionStatus").textContent = "Mat ket noi";
    document.getElementById("torrserverVersion").textContent = "Khong ket noi duoc";
    document.getElementById("infoStatus").textContent = "Offline";
  }
}

async function testConnection() {
  await checkConnection();
  showToast("Da kiem tra ket noi", "success");
}

// ============ Navigation ============
function showPage(page) {
  currentPage = page;
  document.querySelectorAll(".page").forEach((p) => p.classList.remove("active"));
  const target = document.getElementById(`page-${page}`);
  if (target) target.classList.add("active");
  document.querySelectorAll(".nav-item").forEach((n) => n.classList.remove("active"));
  const navItem = document.querySelector(`.nav-item[data-page="${page}"]`);
  if (navItem) navItem.classList.add("active");
  if (page === "downloads") refreshDownloads();
  if (page === "torrents") loadTorrents();
}

function goBack() { showPage("dashboard"); }

// ============ Jackett Search (Discover) ============
function showSearch() {
  document.getElementById("searchOverlay").classList.add("active");
  document.getElementById("searchInput").focus();
}

function hideSearch() {
  document.getElementById("searchOverlay").classList.remove("active");
  document.getElementById("searchResults").innerHTML = "";
}

async function performSearch() {
  const query = document.getElementById("searchInput").value.trim();
  const container = document.getElementById("searchResults");
  if (!query) return;
  
  container.innerHTML = '<div style="text-align:center;padding:40px"><div class="spinner"></div><p style="margin-top:12px;color:#999">Dang tim tren Jackett...</p></div>';
  
  try {
    const results = await api(`/jackett?q=${encodeURIComponent(query)}`);
    
    if (!results || results.length === 0) {
      container.innerHTML = `<div class="empty-state-small"><p>Khong tim thay "${query}"</p><p style="font-size:12px;color:#666">Kiem tra Jackett da chay chua</p></div>`;
      return;
    }

    // Try to get TMDB posters
    const posterPromises = results.slice(0, 20).map(async (r) => {
      try {
        const movieData = await fetch(`https://api.themoviedb.org/3/search/multi?query=${encodeURIComponent(r.title)}&api_key=demo`);
        // TMDB demo won't work, so we skip poster for now
        r.poster = null;
      } catch(e) {
        r.poster = null;
      }
      return r;
    });
    
    container.innerHTML = results.map((r) => `
      <div class="search-result-card">
        <div class="result-main">
          <div class="result-title">${escHtml(r.title)}</div>
          <div class="result-meta">
            <span class="meta-size">${formatSize(r.size)}</span>
            <span class="meta-seed ${r.seeders > 0 ? 'has-seed' : 'no-seed'}">
              ${r.seeders > 0 ? `▲ ${r.seeders}` : '▲ 0'}
            </span>
            ${r.peers > r.seeders ? `<span class="meta-peer">▼ ${r.peers - r.seeders}</span>` : ''}
            ${r.indexer ? `<span class="meta-indexer">${escHtml(r.indexer)}</span>` : ''}
          </div>
        </div>
        <div class="result-actions">
          <button class="btn-add-torr" onclick="addToTorrServer('${escAttr(r.magnet)}', '${escAttr(r.title)}')">
            + Them vao TorrServer
          </button>
        </div>
      </div>
    `).join("");
  } catch (err) {
    container.innerHTML = `<div class="empty-state-small"><p>Loi tim kiem</p><p style="font-size:12px;color:#666">${err.message}</p></div>`;
  }
}

async function addToTorrServer(link, title) {
  try {
    await api("/add", {
      method: "POST",
      body: JSON.stringify({ link, title, save: true }),
    });
    showToast(`Da them: ${title}`, "success");
    loadTorrents();
  } catch (err) {
    showToast("Loi khi them torrent", "error");
  }
}

// ============ Torrents ============
async function loadTorrents() {
  try {
    const data = await api("/torrents", { method: "POST", body: JSON.stringify({ action: "list" }) });
    allTorrents = Array.isArray(data) ? data : [];
    document.getElementById("infoTotal").textContent = allTorrents.length;
    renderRecentTorrents();
    renderMoviesGrid();
    renderTVShowsGrid();
    renderAllTorrents();
  } catch (err) { console.error("Load error:", err); }
}

function renderRecentTorrents() {
  const c = document.getElementById("recentTorrents");
  const recent = allTorrents.slice(-5).reverse();
  if (!recent.length) { c.innerHTML = '<div class="empty-state-small"><p>Chua co torrent nao</p></div>'; return; }
  c.innerHTML = recent.map((t) => createTorrentItem(t)).join("");
}

function renderMoviesGrid() {
  const c = document.getElementById("moviesGrid");
  const movies = allTorrents.filter((t) => !isTVShow(t));
  if (!movies.length) {
    c.innerHTML = '<div class="empty-state"><div class="empty-icon">🎬</div><p>Chua co phim nao</p><button class="btn-primary" onclick="showSearch()">Tim phim</button></div>';
    return;
  }
  c.innerHTML = movies.map((t) => createPosterCard(t)).join("");
}

function renderTVShowsGrid() {
  const c = document.getElementById("tvshowsGrid");
  const tv = allTorrents.filter((t) => isTVShow(t));
  if (!tv.length) {
    c.innerHTML = '<div class="empty-state"><div class="empty-icon">📺</div><p>Chua co phim bo nao</p><button class="btn-primary" onclick="showSearch()">Tim phim bo</button></div>';
    return;
  }
  c.innerHTML = tv.map((t) => createPosterCard(t)).join("");
}

function renderAllTorrents() {
  const c = document.getElementById("allTorrentsList");
  if (!allTorrents.length) {
    c.innerHTML = '<div class="empty-state"><div class="empty-icon">📋</div><p>Chua co torrent nao</p></div>';
    return;
  }
  c.innerHTML = [...allTorrents].reverse().map((t) => createTorrentItem(t)).join("");
}

function createTorrentItem(t) {
  return `<div class="torrent-item" onclick="showTorrentDetail('${t.Hash}')">
    <div class="torrent-icon">${isTVShow(t) ? "📺" : "🎬"}</div>
    <div class="torrent-info">
      <div class="torrent-name">${escHtml(t.Title || t.Hash.substring(0, 12))}</div>
      <div class="torrent-meta">${t.TorrentSize ? formatSize(t.TorrentSize) : "Chua tai"}</div>
    </div>
    <div class="torrent-actions">
      <button class="btn-primary btn-small" onclick="event.stopPropagation(); playTorrent('${t.Hash}')">▶</button>
      <button class="btn-secondary btn-small" onclick="event.stopPropagation(); removeTorrent('${t.Hash}')">✕</button>
    </div>
  </div>`;
}

function createPosterCard(t) {
  const poster = t.Poster || `data:image/svg+xml,${encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 300"><rect fill="#1e1e1e" width="200" height="300"/><text x="100" y="150" text-anchor="middle" fill="#666" font-size="48">🎬</text></svg>')}`;
  return `<div class="poster-card" onclick="showTorrentDetail('${t.Hash}')">
    <img class="poster-img" src="${poster}" alt="" onerror="this.style.display='none'">
    <div class="poster-info">
      <div class="poster-title">${escHtml(t.Title || "Chua co ten")}</div>
      <div class="poster-meta">${t.TorrentSize ? formatSize(t.TorrentSize) : "N/A"}</div>
    </div>
  </div>`;
}

function isTVShow(t) {
  const name = (t.Title || "").toLowerCase();
  return name.includes("s0") || name.includes("season") || name.includes("episode") || /\b\d{1,2}x\d{1,2}\b/.test(name);
}

// ============ Torrent Actions ============
async function addTorrent(save = true) {
  const link = document.getElementById("addMagnet").value.trim();
  const title = document.getElementById("addTitle").value.trim();
  const poster = document.getElementById("addPoster").value.trim();
  if (!link) { showToast("Nhap magnet link", "error"); return; }
  try {
    await api("/add", { method: "POST", body: JSON.stringify({ link, title: title || undefined, poster: poster || undefined, save }) });
    showToast(save ? "Da them & luu" : "Da them torrent", "success");
    document.getElementById("addMagnet").value = "";
    document.getElementById("addTitle").value = "";
    document.getElementById("addPoster").value = "";
    loadTorrents();
    showPage("dashboard");
  } catch (err) { showToast("Loi khi them torrent", "error"); }
}

async function removeTorrent(hash) {
  if (!confirm("Xoa torrent nay?")) return;
  try {
    await api("/torrents", { method: "POST", body: JSON.stringify({ action: "rem", hash }) });
    showToast("Da xoa torrent", "success");
    loadTorrents();
  } catch (err) { showToast("Loi khi xoa", "error"); }
}

async function showTorrentDetail(hash) {
  const torrent = allTorrents.find((t) => t.Hash === hash);
  if (!torrent) return;
  try {
    const data = await api("/torrents", { method: "POST", body: JSON.stringify({ action: "get", hash }) });
    if (data?.Torrent?.Files) showFileList(hash, torrent.Title || "Torrent", data.Torrent.Files);
    else playTorrent(hash);
  } catch (err) { playTorrent(hash); }
}

function showFileList(hash, title, files) {
  const page = document.createElement("div");
  page.className = "page active";
  page.id = "page-files";
  page.innerHTML = `<div class="page-header">
    <button class="icon-btn" onclick="this.closest('.page').remove(); showPage('${currentPage}');">
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M19 12H5M12 19l-7-7 7-7"/></svg>
    </button>
    <h1 style="flex:1;margin-left:8px;font-size:18px;">${escHtml(title)}</h1>
  </div>
  <div class="torrent-list">
    ${files.map((f) => `<div class="torrent-item" onclick="playFile('${hash}',${f.Id},'${escAttr(f.Name)}')">
      <div class="torrent-icon">${getFileIcon(f.Name)}</div>
      <div class="torrent-info"><div class="torrent-name">${escHtml(f.Name)}</div><div class="torrent-meta">${formatSize(f.Length)}</div></div>
      <button class="btn-primary btn-small">▶</button>
    </div>`).join("")}
  </div>`;
  document.getElementById("mainContent").appendChild(page);
  document.querySelectorAll(".page").forEach((p) => p.classList.remove("active"));
  page.classList.add("active");
}

function getFileIcon(name) {
  const ext = name.split(".").pop().toLowerCase();
  if (["mp4","mkv","avi","mov","wmv"].includes(ext)) return "🎬";
  if (["mp3","flac","wav","aac","ogg"].includes(ext)) return "🎵";
  if (["srt","sub","ass","idx"].includes(ext)) return "📝";
  return "📄";
}

// ============ Player ============
function playTorrent(hash) {
  const t = allTorrents.find((x) => x.Hash === hash);
  document.getElementById("playerTitle").textContent = t?.Title || "Dang phat...";
  document.getElementById("videoPlayer").src = `${API}/stream/play?link=${hash}&index=0&play`;
  document.getElementById("playerModal").classList.add("active");
}

function playFile(hash, fileId, fileName) {
  document.getElementById("playerTitle").textContent = fileName;
  document.getElementById("videoPlayer").src = `${API}/stream/play?link=${hash}&index=${fileId}&play`;
  document.getElementById("playerModal").classList.add("active");
}

function closePlayer() {
  const v = document.getElementById("videoPlayer");
  v.pause(); v.src = "";
  document.getElementById("playerModal").classList.remove("active");
}

// ============ Downloads ============
async function refreshDownloads() {
  const c = document.getElementById("downloadList");
  c.innerHTML = '<div class="spinner"></div>';
  try {
    const data = await api("/torrents", { method: "POST", body: JSON.stringify({ action: "list" }) });
    const t = Array.isArray(data) ? data : [];
    if (!t.length) { c.innerHTML = '<div class="empty-state"><div class="empty-icon">📥</div><p>Khong co tai nao dang chay</p></div>'; return; }
    c.innerHTML = t.map((x) => `<div class="download-item">
      <div class="download-header"><div class="download-name">${escHtml(x.Title || x.Hash.substring(0,12))}</div>
      <button class="btn-secondary btn-small" onclick="playTorrent('${x.Hash}')">▶</button></div>
      <div class="download-progress"><div class="download-bar" style="width:100%"></div></div>
      <div class="download-stats"><span>${x.TorrentSize ? formatSize(x.TorrentSize) : "N/A"}</span><span>San sang phat</span></div>
    </div>`).join("");
  } catch (err) { c.innerHTML = '<div class="empty-state-small"><p>Loi tai du lieu</p></div>'; }
}

// ============ Filters ============
function filterMovies(q) {
  const c = document.getElementById("moviesGrid");
  const f = allTorrents.filter((t) => !isTVShow(t) && (t.Title||"").toLowerCase().includes(q.toLowerCase()));
  c.innerHTML = f.length ? f.map(createPosterCard).join("") : '<div class="empty-state-small"><p>Khong tim thay</p></div>';
}
function filterTVShows(q) {
  const c = document.getElementById("tvshowsGrid");
  const f = allTorrents.filter((t) => isTVShow(t) && (t.Title||"").toLowerCase().includes(q.toLowerCase()));
  c.innerHTML = f.length ? f.map(createPosterCard).join("") : '<div class="empty-state-small"><p>Khong tim thay</p></div>';
}
function filterAllTorrents(q) {
  const c = document.getElementById("allTorrentsList");
  const f = allTorrents.filter((t) => (t.Title||"").toLowerCase().includes(q.toLowerCase()) || (t.Hash||"").includes(q));
  c.innerHTML = f.length ? [...f].reverse().map(createTorrentItem).join("") : '<div class="empty-state-small"><p>Khong tim thay</p></div>';
}

// ============ Upload ============
async function handleUpload(input) {
  const file = input.files[0];
  if (!file) return;
  const fd = new FormData();
  fd.append("file", file);
  fd.append("title", file.name.replace(".torrent",""));
  try {
    const r = await fetch(`${API}/torrent/upload`, { method: "POST", body: fd });
    if (r.ok) { showToast("Da upload file .torrent", "success"); loadTorrents(); showPage("dashboard"); }
    else showToast("Loi upload file", "error");
  } catch (err) { showToast("Loi upload file", "error"); }
  input.value = "";
}

// ============ Utils ============
function formatSize(b) {
  if (!b || b === 0) return "0 B";
  const u = ["B","KB","MB","GB","TB"];
  const i = Math.floor(Math.log(b) / Math.log(1024));
  return (b / Math.pow(1024, i)).toFixed(1) + " " + u[i];
}
function showToast(msg, type = "success") {
  const t = document.getElementById("toast");
  t.textContent = msg;
  t.className = `toast ${type} show`;
  setTimeout(() => t.classList.remove("show"), 3000);
}
function showAddTorrent() { showPage("add"); }
function escHtml(s) { const d = document.createElement("div"); d.textContent = s; return d.innerHTML; }
function escAttr(s) { return (s||"").replace(/'/g, "\\'").replace(/"/g, "&quot;"); }
