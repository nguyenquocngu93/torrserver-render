const express = require("express");
const fetch = require("node-fetch");
const path = require("path");
const { URLSearchParams } = require("url");

const app = express();
const PORT = process.env.PORT || 3000;
const TORRSERVER_URL = process.env.TORRSERVER_URL || "http://127.0.0.1:8090";
const JACKETT_URL = process.env.JACKETT_URL || "http://127.0.0.1:9117";
const JACKETT_API_KEY = process.env.JACKETT_API_KEY || "";

app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

// ============ TorrServer Proxy ============

app.get("/api/echo", async (req, res) => {
  try {
    const r = await fetch(`${TORRSERVER_URL}/echo`);
    const text = await r.text();
    res.json({ version: text, url: TORRSERVER_URL });
  } catch (err) {
    res.status(502).json({ error: "Cannot connect to TorrServer", details: err.message });
  }
});

app.post("/api/torrents", async (req, res) => {
  try {
    const r = await fetch(`${TORRSERVER_URL}/torrents`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(req.body),
    });
    res.json(await r.json());
  } catch (err) {
    res.status(502).json({ error: "TorrServer error", details: err.message });
  }
});

app.post("/api/settings", async (req, res) => {
  try {
    const r = await fetch(`${TORRSERVER_URL}/settings`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(req.body),
    });
    res.json(await r.json());
  } catch (err) {
    res.status(502).json({ error: "TorrServer error", details: err.message });
  }
});

app.get("/api/stream/*", async (req, res) => {
  try {
    const streamPath = req.params[0];
    const qs = new URL(req.url, `http://localhost:${PORT}`).search;
    const r = await fetch(`${TORRSERVER_URL}/stream/${streamPath}${qs}`);
    res.status(r.status);
    if (r.headers.get("content-type")) res.set("Content-Type", r.headers.get("content-type"));
    if (r.headers.get("content-length")) res.set("Content-Length", r.headers.get("content-length"));
    if (r.headers.get("accept-ranges")) res.set("Accept-Ranges", r.headers.get("accept-ranges"));
    r.body.pipe(res);
  } catch (err) {
    res.status(502).json({ error: "Stream error", details: err.message });
  }
});

app.get("/api/playlistall", async (req, res) => {
  try {
    const r = await fetch(`${TORRSERVER_URL}/playlistall/all.m3u`);
    res.set("Content-Type", "audio/x-mpegurl");
    res.send(await r.text());
  } catch (err) {
    res.status(502).json({ error: "TorrServer error", details: err.message });
  }
});

app.post("/api/viewed", async (req, res) => {
  try {
    const r = await fetch(`${TORRSERVER_URL}/viewed`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(req.body),
    });
    res.json(await r.json());
  } catch (err) {
    res.status(502).json({ error: "TorrServer error", details: err.message });
  }
});

app.post("/api/cache", async (req, res) => {
  try {
    const r = await fetch(`${TORRSERVER_URL}/cache`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(req.body),
    });
    res.json(await r.json());
  } catch (err) {
    res.status(502).json({ error: "TorrServer error", details: err.message });
  }
});

// ============ Jackett Search ============

// GET /api/jackett?q=...&categories=2000,5000
app.get("/api/jackett", async (req, res) => {
  const query = req.query.q || "";
  const cats = req.query.categories || "2000,5000"; // 2000=Movies, 5000=TV
  if (!query) return res.json([]);

  try {
    const params = new URLSearchParams({
      apikey: JACKETT_API_KEY,
      Query: query,
      Category: cats,
      Trackers: "all",
    });
    const url = `${JACKETT_URL}/api/v2.0/indexers/all/results/torznab/api?${params}`;
    const r = await fetch(url);
    const text = await r.text();

    // Parse Torznab XML
    const results = [];
    const items = text.split("<item>").slice(1);
    for (const item of items) {
      const title = extractTag(item, "title");
      const enclosure = extractAttr(item, "enclosure", "url");
      const size = parseInt(extractAttr(item, "torznab:attr", "size", "length") || extractTag(item, "size") || "0");
      const seeders = parseInt(extractAttr(item, "torznab:attr", "seeders") || "0");
      const peers = parseInt(extractAttr(item, "torznab:attr", "peers") || "0");
      const category = extractAttr(item, "torznab:attr", "category") || "";
      const indexer = extractTag(item, "jackett:indexer") || "";

      // Extract magnet from download link
      let magnet = "";
      const desc = extractTag(item, "description") || "";
      if (desc.startsWith("magnet:")) {
        magnet = desc;
      } else {
        magnet = enclosure; // fallback to torrent download link
      }

      results.push({ title, magnet, size, seeders, peers, category, indexer });
    }
    res.json(results);
  } catch (err) {
    res.status(502).json({ error: "Jackett search failed", details: err.message });
  }
});

function extractTag(xml, tag) {
  const re = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)</${tag}>`);
  const m = xml.match(re);
  return m ? m[1].trim() : "";
}

function extractAttr(xml, tag, name, extraAttr) {
  const re = new RegExp(`<${tag}[^>]*name=["']${name}["'][^>]*(?:${extraAttr ? extraAttr + '=["\']([^"\']*)["\']' : ""})[^>]*/?>`, "i");
  const m = xml.match(re);
  if (!m) return "";
  return extraAttr && m[1] ? m[1] : "";
}

// ============ Jackett Status ============
app.get("/api/jackett/status", async (req, res) => {
  try {
    const r = await fetch(`${JACKETT_URL}/api/v2.0/indexers/all/results/torznab/api?apikey=${JACKETT_API_KEY}&q=test&limit=1`);
    if (r.ok) {
      res.json({ status: "ok", url: JACKETT_URL });
    } else {
      res.json({ status: "error", code: r.status });
    }
  } catch (err) {
    res.json({ status: "offline", details: err.message });
  }
});

// ============ Add magnet/torrent to TorrServer ============
app.post("/api/add", async (req, res) => {
  const { link, title, poster, save } = req.body;
  try {
    const r = await fetch(`${TORRSERVER_URL}/torrents`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        action: "add",
        link: link,
        title: title || undefined,
        poster: poster || undefined,
        save_to_db: save !== false,
      }),
    });
    res.json(await r.json());
  } catch (err) {
    res.status(502).json({ error: "Failed to add torrent", details: err.message });
  }
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`TorrUI running at http://0.0.0.0:${PORT}`);
  console.log(`TorrServer: ${TORRSERVER_URL}`);
  console.log(`Jackett:    ${JACKETT_URL}`);
});
