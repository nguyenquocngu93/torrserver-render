// TorrUI v2 - NZB360-style Frontend
const API = "/api";
let allTorrents = [];
let currentPage = "dashboard";

// Initialize
document.addEventListener("DOMContentLoaded", () => {
  checkConnection();
  loadTorrents();
  
  // Enter key for search
  document.getElementById("searchInput")?.addEventListener("keypress", (e) => {
    if (e.key === "Enter") performSearch();
  });
});

// ============ API Helpers ============
async function api(endpoint, options = {}) {
  try {
    const res = await fetch(`${API}${endpoint}`, {
      headers: { "Content-Type": "application/json" },
      ...options,
    });
    return await res.json();
  } catch (err) {
    console.error("API Error:", err);
    throw err;
  }
}

// ============ Connection ============
async function checkConnection() {
  try {
    const data = await api("/echo");
    document.getElementById("connectionStatus").textContent = `v${data.version}`;
    document.getElementById("torrserverVersion").textContent = `v${data.version} - Sẵn sàng`;
    document.getElementById("statusBadge").classList.add("connected");
    document.getElementById("infoVersion").textContent = data.version;
    document.getElementById("infoStatus").textContent = "✅ Online";
    document.getElementById("settingsUrl").value = data.url;
  } catch (err) {
    document.getElementById("connectionStatus").textContent = "Mất kết nối";
    document.getElementById("torrserverVersion").textContent = "Không kết nối được";
    document.getElementById("infoVersion").textContent = "...";
    document.getElementById("infoStatus").textContent = "❌ Offline";
  }
}

async function testConnection() {
  await checkConnection();
  showToast("Đã kiểm tra kết nối", "success");
}

// ============ Navigation ============
function showPage(page) {
  currentPage = page;
  
  // Hide all pages
  document.querySelectorAll(".page").forEach((p) => p.classList.remove("active"));
  
  // Show target page
  const targetPage = document.getElementById(`page-${page}`);
  if (targetPage) targetPage.classList.add("active");
  
  // Update nav
  document.querySelectorAll(".nav-item").forEach((n) => n.classList.remove("active"));
  const navItem = document.querySelector(`.nav-item[data-page="${page}"]`);
  if (navItem) navItem.classList.add("active");
  
  // Load data for page
  if (page === "downloads") refreshDownloads();
  if (page === "torrents") loadTorrents();
}

function goBack() {
  showPage("dashboard");
}

// ============ Search ============
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
  
  container.innerHTML = '<div class="spinner"></div>';
  
  try {
    // Search in local torrents
    const results = allTorrents.filter(
      (t) => (t.Title || "").toLowerCase().includes(query.toLowerCase()) ||
             (t.Hash || "").includes(query)
    );
    
    if (results.length === 0) {
      container.innerHTML = `
        <div class="empty-state-small">
          <p>Không tìm thấy "${query}"</p>
        </div>`;
      return;
    }
    
    container.innerHTML = results.map((t) => `
      <div class="torrent-item" onclick="playTorrent('${t.Hash}'); hideSearch();">
        <div class="torrent-icon">🎬</div>
        <div class="torrent-info">
          <div class="torrent-name">${t.Title || t.Hash.substring(0, 12)}</div>
          <div class="torrent-meta">${t.TorrentSize ? formatSize(t.TorrentSize) : "N/A"}</div>
        </div>
        <button class="btn-primary btn-small">▶</button>
      </div>
    `).join("");
  } catch (err) {
    container.innerHTML = '<div class="empty-state-small"><p>Lỗi tìm kiếm</p></div>';
  }
}

// ============ Torrents ============
async function loadTorrents() {
  try {
    const data = await api("/torrents", {
      method: "POST",
      body: JSON.stringify({ action: "list" }),
    });
    
    allTorrents = Array.isArray(data) ? data : [];
    document.getElementById("infoTotal").textContent = allTorrents.length;
    
    renderRecentTorrents();
    renderMoviesGrid();
    renderTVShowsGrid();
    renderAllTorrents();
  } catch (err) {
    console.error("Load error:", err);
  }
}

function renderRecentTorrents() {
  const container = document.getElementById("recentTorrents");
  const recent = allTorrents.slice(-5).reverse();
  
  if (recent.length === 0) {
    container.innerHTML = '<div class="empty-state-small"><p>Chưa có torrent nào</p></div>';
    return;
  }
  
  container.innerHTML = recent.map((t) => createTorrentItem(t)).join("");
}

function renderMoviesGrid() {
  const container = document.getElementById("moviesGrid");
  const movies = allTorrents.filter((t) => !isTVShow(t));
  
  if (movies.length === 0) {
    container.innerHTML = `
      <div class="empty-state">
        <div class="empty-icon">🎬</div>
        <p>Chưa có phim nào</p>
        <button class="btn-primary" onclick="showPage('add')">Thêm phim</button>
      </div>`;
    return;
  }
  
  container.innerHTML = movies.map((t) => createPosterCard(t)).join("");
}

function renderTVShowsGrid() {
  const container = document.getElementById("tvshowsGrid");
  const tvshows = allTorrents.filter((t) => isTVShow(t));
  
  if (tvshows.length === 0) {
    container.innerHTML = `
      <div class="empty-state">
        <div class="empty-icon">📺</div>
        <p>Chưa có phim bộ nào</p>
        <button class="btn-primary" onclick="showPage('add')">Thêm phim bộ</button>
      </div>`;
    return;
  }
  
  container.innerHTML = tvshows.map((t) => createPosterCard(t)).join("");
}

function renderAllTorrents() {
  const container = document.getElementById("allTorrentsList");
  
  if (allTorrents.length === 0) {
    container.innerHTML = `
      <div class="empty-state">
        <div class="empty-icon">📋</div>
        <p>Chưa có torrent nào</p>
        <button class="btn-primary" onclick="showPage('add')">Thêm torrent</button>
      </div>`;
    return;
  }
  
  container.innerHTML = [...allTorrents].reverse().map((t) => createTorrentItem(t)).join("");
}

function createTorrentItem(t) {
  return `
    <div class="torrent-item" onclick="showTorrentDetail('${t.Hash}')">
      <div class="torrent-icon">${isTVShow(t) ? "📺" : "🎬"}</div>
      <div class="torrent-info">
        <div class="torrent-name">${t.Title || t.Hash.substring(0, 12)}</div>
        <div class="torrent-meta">${t.TorrentSize ? formatSize(t.TorrentSize) : "Chưa tải"}</div>
      </div>
      <div class="torrent-actions">
        <button class="btn-primary btn-small" onclick="event.stopPropagation(); playTorrent('${t.Hash}')">▶</button>
        <button class="btn-secondary btn-small" onclick="event.stopPropagation(); removeTorrent('${t.Hash}')">✕</button>
      </div>
    </div>`;
}

function createPosterCard(t) {
  const poster = t.Poster || `data:image/svg+xml,${encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 300"><rect fill="#1e1e1e" width="200" height="300"/><text x="100" y="150" text-anchor="middle" fill="#666" font-size="48">🎬</text></svg>')}`;
  
  return `
    <div class="poster-card" onclick="showTorrentDetail('${t.Hash}')">
      <img class="poster-img" src="${poster}" alt="" onerror="this.src='data:image/svg+xml,${encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 300"><rect fill="#1e1e1e" width="200" height="300"/><text x="100" y="150" text-anchor="middle" fill="#666" font-size="48">🎬</text></svg>')}'">
      <div class="poster-info">
        <div class="poster-title">${t.Title || "Chưa có tên"}</div>
        <div class="poster-meta">${t.TorrentSize ? formatSize(t.TorrentSize) : "N/A"}</div>
      </div>
    </div>`;
}

function isTVShow(t) {
  const name = (t.Title || "").toLowerCase();
  return name.includes("s0") || name.includes("season") || name.includes("episode") ||
         /\b\d{1,2}x\d{1,2}\b/.test(name);
}

// ============ Torrent Actions ============
async function addTorrent(save = true) {
  const link = document.getElementById("addMagnet").value.trim();
  const title = document.getElementById("addTitle").value.trim();
  const poster = document.getElementById("addPoster").value.trim();
  
  if (!link) {
    showToast("Vui lòng nhập magnet link", "error");
    return;
  }
  
  try {
    await api("/torrents", {
      method: "POST",
      body: JSON.stringify({
        action: "add",
        link: link,
        title: title || undefined,
        poster: poster || undefined,
        save_to_db: save,
      }),
    });
    
    showToast(save ? "Đã thêm & lưu torrent" : "Đã thêm torrent", "success");
    document.getElementById("addMagnet").value = "";
    document.getElementById("addTitle").value = "";
    document.getElementById("addPoster").value = "";
    
    loadTorrents();
    showPage("dashboard");
  } catch (err) {
    showToast("Lỗi khi thêm torrent", "error");
  }
}

async function removeTorrent(hash) {
  if (!confirm("Xóa torrent này?")) return;
  
  try {
    await api("/torrents", {
      method: "POST",
      body: JSON.stringify({ action: "rem", hash: hash }),
    });
    
    showToast("Đã xóa torrent", "success");
    loadTorrents();
  } catch (err) {
    showToast("Lỗi khi xóa", "error");
  }
}

async function showTorrentDetail(hash) {
  const torrent = allTorrents.find((t) => t.Hash === hash);
  if (!torrent) return;
  
  try {
    const data = await api("/torrents", {
      method: "POST",
      body: JSON.stringify({ action: "get", hash: hash }),
    });
    
    if (data && data.Torrent && data.Torrent.Files) {
      showFileList(hash, torrent.Title || "Torrent", data.Torrent.Files);
    } else {
      playTorrent(hash);
    }
  } catch (err) {
    playTorrent(hash);
  }
}

function showFileList(hash, title, files) {
  // Create a temporary page for file list
  const page = document.createElement("div");
  page.className = "page active";
  page.id = "page-files";
  page.innerHTML = `
    <div class="page-header">
      <button class="icon-btn" onclick="this.closest('.page').remove(); showPage('${currentPage}');">
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M19 12H5M12 19l-7-7 7-7"/></svg>
      </button>
      <h1 style="flex:1; margin-left:8px; font-size:18px;">${title}</h1>
    </div>
    <div class="torrent-list">
      ${files.map((f, i) => `
        <div class="torrent-item" onclick="playFile('${hash}', ${f.Id}, '${f.Name.replace(/'/g, "\\'")}')">
          <div class="torrent-icon">${getFileIcon(f.Name)}</div>
          <div class="torrent-info">
            <div class="torrent-name">${f.Name}</div>
            <div class="torrent-meta">${formatSize(f.Length)}</div>
          </div>
          <button class="btn-primary btn-small">▶</button>
        </div>
      `).join("")}
    </div>`;
  
  document.getElementById("mainContent").appendChild(page);
  document.querySelectorAll(".page").forEach((p) => p.classList.remove("active"));
  page.classList.add("active");
}

function getFileIcon(name) {
  const ext = name.split(".").pop().toLowerCase();
  if (["mp4", "mkv", "avi", "mov", "wmv"].includes(ext)) return "🎬";
  if (["mp3", "flac", "wav", "aac", "ogg"].includes(ext)) return "🎵";
  if (["srt", "sub", "ass", "idx"].includes(ext)) return "📝";
  if (["jpg", "jpeg", "png", "gif"].includes(ext)) return "🖼";
  return "📄";
}

// ============ Player ============
function playTorrent(hash) {
  const torrent = allTorrents.find((t) => t.Hash === hash);
  const title = torrent?.Title || "Đang phát...";
  
  const modal = document.getElementById("playerModal");
  const video = document.getElementById("videoPlayer");
  
  document.getElementById("playerTitle").textContent = title;
  video.src = `${API}/stream/play?link=${hash}&index=0&play`;
  
  modal.classList.add("active");
}

function playFile(hash, fileId, fileName) {
  const modal = document.getElementById("playerModal");
  const video = document.getElementById("videoPlayer");
  
  document.getElementById("playerTitle").textContent = fileName;
  video.src = `${API}/stream/play?link=${hash}&index=${fileId}&play`;
  
  modal.classList.add("active");
}

function closePlayer() {
  const modal = document.getElementById("playerModal");
  const video = document.getElementById("videoPlayer");
  
  video.pause();
  video.src = "";
  modal.classList.remove("active");
}

// ============ Downloads ============
async function refreshDownloads() {
  const container = document.getElementById("downloadList");
  container.innerHTML = '<div class="spinner"></div>';
  
  try {
    const data = await api("/torrents", {
      method: "POST",
      body: JSON.stringify({ action: "list" }),
    });
    
    const torrents = Array.isArray(data) ? data : [];
    
    if (torrents.length === 0) {
      container.innerHTML = `
        <div class="empty-state">
          <div class="empty-icon">📥</div>
          <p>Không có tải nào đang chạy</p>
        </div>`;
      return;
    }
    
    container.innerHTML = torrents.map((t) => `
      <div class="download-item">
        <div class="download-header">
          <div class="download-name">${t.Title || t.Hash.substring(0, 12)}</div>
          <button class="btn-secondary btn-small" onclick="playTorrent('${t.Hash}')">▶</button>
        </div>
        <div class="download-progress">
          <div class="download-bar" style="width: 100%"></div>
        </div>
        <div class="download-stats">
          <span>${t.TorrentSize ? formatSize(t.TorrentSize) : "N/A"}</span>
          <span>Sẵn sàng phát</span>
        </div>
      </div>
    `).join("");
  } catch (err) {
    container.innerHTML = '<div class="empty-state-small"><p>Lỗi tải dữ liệu</p></div>';
  }
}

// ============ Filters ============
function filterMovies(query) {
  const container = document.getElementById("moviesGrid");
  const filtered = allTorrents.filter((t) => 
    !isTVShow(t) && (t.Title || "").toLowerCase().includes(query.toLowerCase())
  );
  container.innerHTML = filtered.length > 0 
    ? filtered.map((t) => createPosterCard(t)).join("")
    : '<div class="empty-state-small"><p>Không tìm thấy</p></div>';
}

function filterTVShows(query) {
  const container = document.getElementById("tvshowsGrid");
  const filtered = allTorrents.filter((t) => 
    isTVShow(t) && (t.Title || "").toLowerCase().includes(query.toLowerCase())
  );
  container.innerHTML = filtered.length > 0 
    ? filtered.map((t) => createPosterCard(t)).join("")
    : '<div class="empty-state-small"><p>Không tìm thấy</p></div>';
}

function filterAllTorrents(query) {
  const container = document.getElementById("allTorrentsList");
  const filtered = allTorrents.filter((t) => 
    (t.Title || "").toLowerCase().includes(query.toLowerCase()) ||
    (t.Hash || "").includes(query)
  );
  container.innerHTML = filtered.length > 0
    ? [...filtered].reverse().map((t) => createTorrentItem(t)).join("")
    : '<div class="empty-state-small"><p>Không tìm thấy</p></div>';
}

// ============ Upload ============
async function handleUpload(input) {
  const file = input.files[0];
  if (!file) return;
  
  const formData = new FormData();
  formData.append("file", file);
  formData.append("title", file.name.replace(".torrent", ""));
  
  try {
    const res = await fetch(`${API}/torrent/upload`, {
      method: "POST",
      body: formData,
    });
    
    if (res.ok) {
      showToast("Đã upload file .torrent", "success");
      loadTorrents();
      showPage("dashboard");
    } else {
      showToast("Lỗi upload file", "error");
    }
  } catch (err) {
    showToast("Lỗi upload file", "error");
  }
  
  input.value = "";
}

// ============ Utilities ============
function formatSize(bytes) {
  if (!bytes || bytes === 0) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return (bytes / Math.pow(1024, i)).toFixed(1) + " " + units[i];
}

function showToast(message, type = "success") {
  const toast = document.getElementById("toast");
  toast.textContent = message;
  toast.className = `toast ${type} show`;
  
  setTimeout(() => {
    toast.classList.remove("show");
  }, 3000);
}

// Alias for adding torrent
function showAddTorrent() {
  showPage("add");
}
