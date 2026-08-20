// ============================================================
// PATCH: Add /api/streams endpoint to TorrShelf server.mjs
// ============================================================
// Find the existing request handler in server.mjs (the part that
// checks req.url) and ADD this block BEFORE the static file serving.
//
// This endpoint returns stream URLs from all enabled providers.
// Lampa plugin will call: GET /api/streams?title=...&year=...&type=movie&season=1&episode=3
//
// Example response:
// {
//   "streams": [
//     { "name": "UHDMovies", "title": "Movie Name\n1.2GB · 1080p · HTTP", "url": "https://..." },
//     { "name": "4KHDHub", "title": "Movie Name\n800MB · 2160p · HTTP · SEEK", "url": "https://..." }
//   ]
// }

// --- ADD THIS HANDLER inside the existing `if (req.method === "GET")` block ---

/*
  // === TorrShelf Stream API for Lampa plugin ===
  if (parsedUrl.pathname === "/api/streams") {
    const title = parsedUrl.searchParams.get("title") || "";
    const year = Number(parsedUrl.searchParams.get("year")) || 0;
    const type = parsedUrl.searchParams.get("type") || "movie";
    const season = Number(parsedUrl.searchParams.get("season")) || 0;
    const episode = Number(parsedUrl.searchParams.get("episode")) || 0;
    const maxResults = Number(parsedUrl.searchParams.get("max")) || 12;

    if (!title) {
      return safeJson(res, 400, { error: "Missing title parameter" });
    }

    try {
      const allStreams = [];

      // Run all enabled providers in parallel
      const providers = [];

      if (settings.uhdmovies) {
        providers.push(
          getUHDMoviesStreams({ title, year, type, season, episode, maxResults })
            .then(s => s.map(stream => ({ ...stream, provider: "UHDMovies" })))
            .catch(() => [])
        );
      }

      if (settings.fourkhdhub) {
        providers.push(
          get4KHDHubStreams({ title, year, type, season, episode, maxResults })
            .then(s => s.map(stream => ({ ...stream, provider: "4KHDHub" })))
            .catch(() => [])
        );
      }

      if (settings.moviesdrive) {
        providers.push(
          getMoviesDriveStreams({ title, year, type, season, episode, maxResults })
            .then(s => s.map(stream => ({ ...stream, provider: "MoviesDrive" })))
            .catch(() => [])
        );
      }

      if (settings.hdhub4u) {
        providers.push(
          getHDHub4uStreams({ title, year, type, season, episode, maxResults })
            .then(s => s.map(stream => ({ ...stream, provider: "HDHub4u" })))
            .catch(() => [])
        );
      }

      if (settings.vadapav) {
        providers.push(
          getVadapavStreams({ title, year, type, season, episode, maxResults })
            .then(s => s.map(stream => ({ ...stream, provider: "Vadapav" })))
            .catch(() => [])
        );
      }

      const results = await Promise.allSettled(providers);
      for (const result of results) {
        if (result.status === "fulfilled") {
          allStreams.push(...result.value);
        }
      }

      // Format for Lampa
      const formatted = allStreams.map(stream => ({
        name: stream.provider || stream.name || "Unknown",
        title: stream.title || title,
        url: stream.url,
        headers: stream.headers || {},
        behaviorHints: stream.behaviorHints || {}
      }));

      return safeJson(res, 200, { streams: formatted });
    } catch (error) {
      return safeJson(res, 500, { error: error.message || "Internal error" });
    }
  }
  // === End Stream API ===
*/
