const express = require("express");
const fetch = require("node-fetch");
const path = require("path");

const app = express();
const PORT = process.env.PORT || 3000;
const TORRSERVER_URL = process.env.TORRSERVER_URL || "http://127.0.0.1:8090";

app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

// Proxy: GET /api/echo
app.get("/api/echo", async (req, res) => {
  try {
    const response = await fetch(`${TORRSERVER_URL}/echo`);
    const text = await response.text();
    res.json({ version: text, url: TORRSERVER_URL });
  } catch (err) {
    res.status(502).json({ error: "Cannot connect to TorrServer", details: err.message });
  }
});

// Proxy: POST /api/torrents
app.post("/api/torrents", async (req, res) => {
  try {
    const response = await fetch(`${TORRSERVER_URL}/torrents`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(req.body),
    });
    const data = await response.json();
    res.json(data);
  } catch (err) {
    res.status(502).json({ error: "TorrServer error", details: err.message });
  }
});

// Proxy: POST /api/settings
app.post("/api/settings", async (req, res) => {
  try {
    const response = await fetch(`${TORRSERVER_URL}/settings`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(req.body),
    });
    const data = await response.json();
    res.json(data);
  } catch (err) {
    res.status(502).json({ error: "TorrServer error", details: err.message });
  }
});

// Proxy: GET /api/stream/* (streaming)
app.get("/api/stream/*", async (req, res) => {
  try {
    const streamPath = req.params[0];
    const queryString = new URL(req.url, `http://localhost:${PORT}`).search;
    const targetUrl = `${TORRSERVER_URL}/stream/${streamPath}${queryString}`;

    const response = await fetch(targetUrl);

    // Forward content type and status
    res.status(response.status);
    if (response.headers.get("content-type")) {
      res.set("Content-Type", response.headers.get("content-type"));
    }
    if (response.headers.get("content-length")) {
      res.set("Content-Length", response.headers.get("content-length"));
    }
    if (response.headers.get("accept-ranges")) {
      res.set("Accept-Ranges", response.headers.get("accept-ranges"));
    }

    response.body.pipe(res);
  } catch (err) {
    res.status(502).json({ error: "Stream error", details: err.message });
  }
});

// Proxy: GET /api/playlistall
app.get("/api/playlistall", async (req, res) => {
  try {
    const response = await fetch(`${TORRSERVER_URL}/playlistall/all.m3u`);
    const text = await response.text();
    res.set("Content-Type", "audio/x-mpegurl");
    res.send(text);
  } catch (err) {
    res.status(502).json({ error: "TorrServer error", details: err.message });
  }
});

// Proxy: POST /api/viewed
app.post("/api/viewed", async (req, res) => {
  try {
    const response = await fetch(`${TORRSERVER_URL}/viewed`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(req.body),
    });
    const data = await response.json();
    res.json(data);
  } catch (err) {
    res.status(502).json({ error: "TorrServer error", details: err.message });
  }
});

// Proxy: POST /api/cache
app.post("/api/cache", async (req, res) => {
  try {
    const response = await fetch(`${TORRSERVER_URL}/cache`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(req.body),
    });
    const data = await response.json();
    res.json(data);
  } catch (err) {
    res.status(502).json({ error: "TorrServer error", details: err.message });
  }
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`TorrUI running at http://0.0.0.0:${PORT}`);
  console.log(`TorrServer: ${TORRSERVER_URL}`);
});
