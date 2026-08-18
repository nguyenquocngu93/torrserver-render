// TorrUI Frontend
const API = "/api";
let currentTorrents = [];
let allTorrents = [];

// Initialize
document.addEventListener("DOMContentLoaded", () => {
  checkConnection();
  loadTorrentList();
  
  // File upload handler
  document.getElementById("torrentFile").addEventListener("change", handleFileUpload);
});

// API helpers
async function apiCall(endpoint, options = {}) {
  try {
    const response = await fetch(`${API}${endpoint}`, {
      headers: { "Content-Type": "application/json" },
      ...options,
    });
    return await response.json();
  } catch (err) {
    console.error("API Error:", err);
    throw err;
  }
}

// Connection check
async function checkConnection() {
  try {
    const data = await apiCall("/echo");
    document.getElementById("statusDot").classList.add("connected");
    document.getElementById("statusText").textContent = `v${data.version}`;
    document.getElementById("serverUrl").textContent = data.url;
    document.getElementById("settingsVersion").textContent = data.version;
    document.getElementById("settingsStatus").textContent = "✅ Kết nối OK";
    document.getElementById("settingsUrl").value = data.url;
  } catch (err) {
    document.getElementById("statusDot").classList.remove("connected");
    document.getElementById("statusText").textContent = "Mất kết nối";
    document.getElementById("settingsStatus").textContent = "❌ Không kết nối được";
  }
}

// Sidebar toggle
function toggleSidebar() {
  document.getElementById("sidebar").classList.toggle("open");
  document.getElementById("overlay").classList.toggle("active");
}

// Page navigation
function showPage(page) {
  document.querySelectorAll(".page").forEach((p) => p.classList.remove("active"));
  document.querySelectorAll(".nav-item").forEach((n) => n.classList.remove("active"));
  
  document.getElementById(`page-${page}`).classList.add("active");
  document.querySelector(`[data-page="${page}"]`).classList.add("active");
  
  toggleSidebar();
  
  if (page === "list") refreshList();
}

// Load torrent list
async function refreshList() {
  const container = document.getElementById("torrentList");
  container.innerHTML = '<div class="empty-state"><div class="spinner"></div><p>Đang tải...</p></div>';
  
  try {
    const data = await apiCall("/torrents", {
      method: "POST",
      body: JSON.stringify({ action: "list" }),
    });
    
    allTorrents = Array.isArray(data) ? data : [];
    currentTorrents = [...allTorrents];
    renderTorrentList();
    updateStats();
  } catch (err) {
    container.innerHTML = '<div class="empty-state"><p>❌ Không thể tải danh sách</p></div>';
  }
}

function loadTorrentList() {
  refreshList();
}

// Render torrent list
function renderTorrentList() {
  const container = document.getElementById("torrentList");
  
  if (currentTorrents.length === 0) {
    container.innerHTML = `
      <div class="empty-state">
        <p>Chưa có torrent nào</p>
        <button class="btn btn-primary" onclick="showPage('add')">Thêm torrent</button>
      </div>`;
    return;
  }
  
  container.innerHTML = currentTorrents.map((t) => `
    <div class="torrent-item" onclick="showTorrentDetail('${t.Hash}')">
      <img class="torrent-item-icon" 
           src="${t.Poster || 'data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><rect fill=%22%231e2433%22 width=%22100%22 height=%22100%22/><text x=%2250%22 y=%2255%22 text-anchor=%22middle%22 fill=%22%239aa0a6%22 font-size=%2240%22>🎬</text></svg>'}" 
           alt="">
      <div class="torrent-item-info">
        <div class="torrent-item-title">${t.Title || t.Hash.substring(0, 12) + "..."}</div>
        <div class="torrent-item-meta">${t.TorrentSize ? formatSize(t.TorrentSize) : "Chưa tải"}</div>
      </div>
      <div class="torrent-item-actions">
        <button class="btn btn-small btn-primary" onclick="event.stopPropagation();playTorrent('${t.Hash}')">▶</button>
        <button class="btn btn-small btn-danger" onclick="event.stopPropagation();removeTorrent('${t.Hash}')">🗑</button>
      </div>
    </div>
  `).join("");
}

// Filter list
function filterList() {
  const query = document.getElementById("listSearch").value.toLowerCase();
  currentTorrents = allTorrents.filter(
    (t) => (t.Title || "").toLowerCase().includes(query) || t.Hash.includes(query)
  );
  renderTorrentList();
}

// Update stats
function updateStats() {
  document.getElementById("statTotal").textContent = allTorrents.length;
  document.getElementById("statActive").textContent = currentTorrents.length;
}

// Add torrent
async function addTorrent() {
  const link = document.getElementById("addLink").value.trim();
  const title = document.getElementById("addTitle").value.trim();
  const poster = document.getElementById("addPoster").value.trim();
  
  if (!link) {
    showToast("Vui lòng nhập magnet link", "error");
    return;
  }
  
  try {
    await apiCall("/torrents", {
      method: "POST",
      body: JSON.stringify({
        action: "add",
        link: link,
        title: title || undefined,
        poster: poster || undefined,
        save_to_db: true,
      }),
    });
    
    showToast("Đã thêm torrent thành công!", "success");
    document.getElementById("addLink").value = "";
    document.getElementById("addTitle").value = "";
    document.getElementById("addPoster").value = "";
    refreshList();
  } catch (err) {
    showToast("❌ Lỗi khi thêm torrent", "error");
  }
}

// Add torrent without saving
async function addTorrentOnly() {
  const link = document.getElementById("addLink").value.trim();
  
  if (!link) {
    showToast("Vui lòng nhập magnet link", "error");
    return;
  }
  
  try {
    await apiCall("/torrents", {
      method: "POST",
      body: JSON.stringify({
        action: "add",
        link: link,
        save_to_db: false,
      }),
    });
    
    showToast("Đã thêm torrent (không lưu)", "success");
    document.getElementById("addLink").value = "";
  } catch (err) {
    showToast("❌ Lỗi khi thêm torrent", "error");
  }
}

// Remove torrent
async function removeTorrent(hash) {
  if (!confirm("Xóa torrent này?")) return;
  
  try {
    await apiCall("/torrents", {
      method: "POST",
      body: JSON.stringify({ action: "rem", hash: hash }),
    });
    
    showToast("Đã xóa torrent", "success");
    refreshList();
  } catch (err) {
    showToast("❌ Lỗi khi xóa", "error");
  }
}

// Play torrent
function playTorrent(hash) {
  showPlayer(hash);
}

// Show player modal
function showPlayer(hash) {
  const modal = document.getElementById("playerModal");
  const video = document.getElementById("videoPlayer");
  const title = document.getElementById("playerTitle");
  
  // Find torrent info
  const torrent = allTorrents.find((t) => t.Hash === hash);
  title.textContent = torrent?.Title || "Đang phát...";
  
  // Set video source - stream first file (index 0)
  video.src = `${API}/stream/play?link=${hash}&index=0&play`;
  
  modal.classList.add("active");
}

function closePlayer() {
  const modal = document.getElementById("playerModal");
  const video = document.getElementById("videoPlayer");
  
  video.pause();
  video.src = "";
  modal.classList.remove("active");
}

// Show torrent detail (file list)
async function showTorrentDetail(hash) {
  try {
    const data = await apiCall("/torrents", {
      method: "POST",
      body: JSON.stringify({ action: "get", hash: hash }),
    });
    
    if (data && data.Torrent && data.Torrent.Files) {
      showFileList(hash, data.Torrent.Files);
    } else {
      // No file info yet, try to get stats
      showToast("Đang lấy thông tin file...", "success");
      playTorrent(hash);
    }
  } catch (err) {
    showToast("❌ Không thể lấy thông tin", "error");
  }
}

// Show file list modal
function showFileList(hash, files) {
  const modal = document.getElementById("playerModal");
  const title = document.getElementById("playerTitle");
  const body = document.querySelector(".modal-body");
  
  title.textContent = "Danh sách file";
  
  body.innerHTML = `
    <div style="width: 100%; max-height: 80vh; overflow-y: auto;">
      ${files.map((f, i) => `
        <div class="torrent-item" onclick="playFile('${hash}', ${f.Id})" style="margin-bottom: 8px;">
          <div class="torrent-item-info">
            <div class="torrent-item-title">${f.Name}</div>
            <div class="torrent-item-meta">${formatSize(f.Length)}</div>
          </div>
          <button class="btn btn-small btn-primary">▶</button>
        </div>
      `).join("")}
    </div>
  `;
  
  modal.classList.add("active");
}

// Play specific file
function playFile(hash, fileId) {
  const modal = document.getElementById("playerModal");
  const video = document.getElementById("videoPlayer");
  const title = document.getElementById("playerTitle");
  
  title.textContent = `Phát file ${fileId + 1}`;
  
  // Reset modal body for video
  document.querySelector(".modal-body").innerHTML = `
    <video id="videoPlayer" controls autoplay>
      Trình duyệt không hỗ trợ phát video.
    </video>`;
  
  const newVideo = document.getElementById("videoPlayer");
  newVideo.src = `${API}/stream/play?link=${hash}&index=${fileId}&play`;
}

// Search torrents (Torznab)
async function searchTorrents() {
  const query = document.getElementById("searchInput").value.trim();
  const container = document.getElementById("searchResults");
  
  if (!query) {
    showToast("Vui lòng nhập từ khóa", "error");
    return;
  }
  
  container.innerHTML = '<div class="empty-state"><div class="spinner"></div><p>Đang tìm kiếm...</p></div>';
  
  try {
    // Use TorrServer's built-in search if available
    const data = await apiCall("/torrents", {
      method: "POST",
      body: JSON.stringify({ action: "list" }),
    });
    
    // Filter by search query
    const results = (Array.isArray(data) ? data : []).filter(
      (t) => (t.Title || "").toLowerCase().includes(query.toLowerCase())
    );
    
    if (results.length === 0) {
      container.innerHTML = `
        <div class="empty-state">
          <p>Không tìm thấy kết quả cho "${query}"</p>
          <p style="font-size: 12px;">Thử thêm torrent bằng magnet link</p>
        </div>`;
      return;
    }
    
    container.innerHTML = results.map((t) => `
      <div class="search-result-item">
        <div class="search-result-title">${t.Title || t.Hash}</div>
        <div class="search-result-meta">
          <span>${t.TorrentSize ? formatSize(t.TorrentSize) : "N/A"}</span>
        </div>
        <div class="search-result-actions">
          <button class="btn btn-small btn-primary" onclick="playTorrent('${t.Hash}')">▶ Phát</button>
          <button class="btn btn-small btn-secondary" onclick="showTorrentDetail('${t.Hash}')">📁 Files</button>
        </div>
      </div>
    `).join("");
  } catch (err) {
    container.innerHTML = '<div class="empty-state"><p>❌ Lỗi tìm kiếm</p></div>';
  }
}

// File upload handler
async function handleFileUpload(e) {
  const file = e.target.files[0];
  if (!file) return;
  
  document.getElementById("uploadHint").textContent = file.name;
  
  const formData = new FormData();
  formData.append("file", file);
  formData.append("title", file.name.replace(".torrent", ""));
  
  try {
    const response = await fetch(`${API}/torrent/upload`, {
      method: "POST",
      body: formData,
    });
    
    if (response.ok) {
      showToast("Đã upload file .torrent thành công!", "success");
      refreshList();
    } else {
      showToast("❌ Lỗi upload file", "error");
    }
  } catch (err) {
    showToast("❌ Lỗi upload file", "error");
  }
}

// Test connection
async function testConnection() {
  await checkConnection();
}

// Save settings (placeholder)
async function saveSettings() {
  showToast("Đã lưu cài đặt (tính năng đang phát triển)", "success");
}

// Utility: format size
function formatSize(bytes) {
  if (!bytes || bytes === 0) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return (bytes / Math.pow(1024, i)).toFixed(1) + " " + units[i];
}

// Utility: show toast
function showToast(message, type = "success") {
  const toast = document.getElementById("toast");
  toast.textContent = message;
  toast.className = `toast ${type} show`;
  
  setTimeout(() => {
    toast.classList.remove("show");
  }, 3000);
}
