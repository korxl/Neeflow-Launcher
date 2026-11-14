const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");

const root = __dirname;
const port = Number(process.env.PORT) || 8080;
const apiBase = "https://api.modrinth.com/v2";
const userAgent = "NeeflowLauncher/0.3.0 (https://freemilk.app)";
const cache = new Map();
const allowedSorts = new Set(["relevance", "downloads", "follows", "newest", "updated"]);
const allowedLoaders = new Set(["fabric", "forge", "neoforge", "quilt"]);

function sendJson(response, status, value) {
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "x-content-type-options": "nosniff"
  });
  response.end(JSON.stringify(value));
}

async function modrinthJson(url) {
  const key = url.toString();
  const cached = cache.get(key);
  if (cached && cached.expiresAt > Date.now()) return cached.value;

  const upstream = await fetch(url, {
    headers: { accept: "application/json", "user-agent": userAgent },
    signal: AbortSignal.timeout(15000)
  });
  if (!upstream.ok) {
    const error = new Error(`Modrinth returned HTTP ${upstream.status}`);
    error.status = upstream.status;
    throw error;
  }
  const value = await upstream.json();
  cache.set(key, { value, expiresAt: Date.now() + 45000 });
  return value;
}

async function cachedExternal(url, format = "json", ttl = 300000) {
  const key = `${format}:${url}`;
  const cached = cache.get(key);
  if (cached && cached.expiresAt > Date.now()) return cached.value;

  const upstream = await fetch(url, {
    headers: { accept: format === "json" ? "application/json" : "text/html, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.7", "user-agent": userAgent },
    signal: AbortSignal.timeout(20000)
  });
  if (!upstream.ok) {
    const error = new Error(`Upstream returned HTTP ${upstream.status}`);
    error.status = upstream.status;
    throw error;
  }
  const value = format === "json" ? await upstream.json() : await upstream.text();
  cache.set(key, { value, expiresAt: Date.now() + ttl });
  return value;
}

function forgeSupportMap(metadata) {
  const xml = String(metadata || "");
  const builds = new Map();
  const pattern = /<version>(\d+\.\d+(?:\.\d+)?)-([^<]+)<\/version>/g;
  let match;
  while ((match = pattern.exec(xml)) !== null) builds.set(match[1], match[2]);
  return Array.from(builds, ([gameVersion, build]) => ({ gameVersion, build, recommended: build }));
}

function quiltGameVersions(source) {
  if (!Array.isArray(source)) return [];
  return source.map((entry) => typeof entry === "string" ? entry : entry && entry.version)
    .filter((version) => typeof version === "string" && /^\d+\.\d+(?:\.\d+)?$/.test(version));
}

function neoForgeGameVersions(metadata) {
  const versions = new Set();
  const pattern = /<version>([^<]+)<\/version>/g;
  const xml = String(metadata || "");
  let match;
  while ((match = pattern.exec(xml)) !== null) {
    const parts = match[1].split(".");
    if (parts.length < 2 || !/^\d+$/.test(parts[0]) || !/^\d+$/.test(parts[1])) continue;
    const major = Number(parts[0]);
    const minor = Number(parts[1]);
    versions.add(minor >= 25 ? `${major}.${minor}` : minor === 0 ? `1.${major}` : `1.${major}.${minor}`);
  }
  return Array.from(versions);
}

function optifineGameVersions(html) {
  const versions = new Set();
  const pattern = /(?:preview[_-])?OptiFine[_-](\d+\.\d+(?:\.\d+)?)(?:[_-]|\.jar)/gi;
  let match;
  while ((match = pattern.exec(html)) !== null) versions.add(match[1]);
  return Array.from(versions);
}

async function handleMinecraftCatalog(response) {
  const manifestUrl = "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json";
  const [manifestResult, fabricResult, quiltResult, forgeResult, neoForgeResult, optifineResult] = await Promise.allSettled([
    cachedExternal(manifestUrl),
    cachedExternal("https://meta.fabricmc.net/v2/versions/game"),
    cachedExternal("https://meta.quiltmc.org/v3/versions/game"),
    cachedExternal("https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml", "text"),
    cachedExternal("https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml", "text"),
    cachedExternal("https://optifine.net/downloads", "text", 900000)
  ]);
  if (manifestResult.status !== "fulfilled" || !manifestResult.value || !Array.isArray(manifestResult.value.versions)) {
    const error = manifestResult.status === "rejected" ? manifestResult.reason : new Error("Invalid Mojang version manifest");
    sendJson(response, error.status || 502, { error: "Couldn't load the official Minecraft version list" });
    return;
  }
  const fabricVersions = fabricResult.status === "fulfilled" && Array.isArray(fabricResult.value)
    ? fabricResult.value.filter((entry) => entry && typeof entry.version === "string").map((entry) => entry.version)
    : [];
  const quiltVersions = quiltResult.status === "fulfilled" ? quiltGameVersions(quiltResult.value) : [];
  const forgeVersions = forgeResult.status === "fulfilled" ? forgeSupportMap(forgeResult.value) : [];
  const neoForgeVersions = neoForgeResult.status === "fulfilled" ? neoForgeGameVersions(neoForgeResult.value) : [];
  const optifineVersions = optifineResult.status === "fulfilled" ? optifineGameVersions(optifineResult.value) : [];
  sendJson(response, 200, {
    latest: manifestResult.value.latest || {},
    versions: manifestResult.value.versions.filter((entry) => entry && typeof entry.id === "string").map((entry) => ({ id: entry.id, type: entry.type || "release", releaseTime: entry.releaseTime || "" })),
    loaders: { fabric: fabricVersions, quilt: quiltVersions, forge: forgeVersions, neoforge: neoForgeVersions, optifine: optifineVersions },
    loaderSources: {
      fabric: fabricResult.status === "fulfilled" ? "ok" : "unavailable",
      quilt: quiltResult.status === "fulfilled" ? "ok" : "unavailable",
      forge: forgeResult.status === "fulfilled" ? "ok" : "unavailable",
      neoforge: neoForgeResult.status === "fulfilled" ? "ok" : "unavailable",
      optifine: optifineResult.status === "fulfilled" ? "ok" : "unavailable"
    }
  });
}

async function handleApi(request, response, url) {
  if (request.method !== "GET") {
    sendJson(response, 405, { error: "Method not allowed" });
    return;
  }

  if (url.pathname === "/api/minecraft/catalog") {
    await handleMinecraftCatalog(response);
    return;
  }

  if (url.pathname === "/api/modrinth/search") {
    const query = (url.searchParams.get("query") || "").trim().slice(0, 100);
    const sort = url.searchParams.get("sort") || "downloads";
    const gameVersion = url.searchParams.get("gameVersion") || "";
    const loader = url.searchParams.get("loader") || "";
    if (!allowedSorts.has(sort)) {
      sendJson(response, 400, { error: "Unsupported sort option" });
      return;
    }
    if (gameVersion && !/^\d{1,2}\.\d{1,2}(?:\.\d{1,2})?$/.test(gameVersion)) {
      sendJson(response, 400, { error: "Invalid Minecraft version" });
      return;
    }
    if (loader && !allowedLoaders.has(loader)) {
      sendJson(response, 400, { error: "Unsupported loader" });
      return;
    }

    const facets = [["project_type:modpack"]];
    if (gameVersion) facets.push([`versions:${gameVersion}`]);
    if (loader) facets.push([`categories:${loader}`]);
    const upstreamUrl = new URL(`${apiBase}/search`);
    upstreamUrl.searchParams.set("query", query);
    upstreamUrl.searchParams.set("facets", JSON.stringify(facets));
    upstreamUrl.searchParams.set("index", sort);
    upstreamUrl.searchParams.set("limit", "12");

    try {
      const result = await modrinthJson(upstreamUrl);
      sendJson(response, 200, {
        total_hits: result.total_hits || 0,
        hits: Array.isArray(result.hits) ? result.hits : []
      });
    } catch (error) {
      sendJson(response, error.status || 502, { error: "Couldn't load Modrinth packs", detail: error.message });
    }
    return;
  }

  const versionMatch = url.pathname.match(/^\/api\/modrinth\/version\/([A-Za-z0-9]{5,12})$/);
  if (versionMatch) {
    try {
      const result = await modrinthJson(new URL(`${apiBase}/version/${versionMatch[1]}`));
      const files = Array.isArray(result.files) ? result.files : [];
      const file = files.find((entry) => entry.primary) || files[0];
      if (!file || !file.url || new URL(file.url).hostname !== "cdn.modrinth.com") {
        sendJson(response, 404, { error: "No downloadable Modrinth pack file found" });
        return;
      }
      sendJson(response, 200, {
        version: result.version_number || result.name || "Latest",
        game_versions: result.game_versions || [],
        loaders: result.loaders || [],
        file: { url: file.url, filename: file.filename || "modpack.mrpack", size: file.size || 0 }
      });
    } catch (error) {
      sendJson(response, error.status || 502, { error: "Couldn't load the Modrinth version", detail: error.message });
    }
    return;
  }

  sendJson(response, 404, { error: "Not found" });
}

function serveStatic(response, pathname) {
  const requestedPath = pathname === "/" ? "/index.html" : pathname;
  let filePath;
  try {
    filePath = path.resolve(root, `.${decodeURIComponent(requestedPath)}`);
  } catch {
    response.writeHead(400);
    response.end("Bad request");
    return;
  }
  if (filePath !== root && !filePath.startsWith(`${root}${path.sep}`)) {
    response.writeHead(403);
    response.end("Forbidden");
    return;
  }
  fs.readFile(filePath, (error, contents) => {
    if (error) {
      response.writeHead(error.code === "ENOENT" ? 404 : 500);
      response.end(error.code === "ENOENT" ? "Not found" : "Server error");
      return;
    }
    const extension = path.extname(filePath).toLowerCase();
    const contentTypes = {
      ".html": "text/html; charset=utf-8",
      ".css": "text/css; charset=utf-8",
      ".js": "text/javascript; charset=utf-8",
      ".png": "image/png",
      ".svg": "image/svg+xml"
    };
    response.writeHead(200, {
      "content-type": contentTypes[extension] || "application/octet-stream",
      "x-content-type-options": "nosniff",
      "cache-control": extension === ".html" ? "no-cache" : "public, max-age=3600"
    });
    response.end(contents);
  });
}

const server = http.createServer((request, response) => {
  const url = new URL(request.url, `http://${request.headers.host || "localhost"}`);
  if (url.pathname.startsWith("/api/")) {
    handleApi(request, response, url).catch((error) => sendJson(response, 500, { error: "Unexpected server error", detail: error.message }));
    return;
  }
  if (request.method !== "GET" && request.method !== "HEAD") {
    response.writeHead(405);
    response.end("Method not allowed");
    return;
  }
  serveStatic(response, url.pathname);
});

server.listen(port, "0.0.0.0", () => {
  console.log(`Neeflow Launcher listening on 0.0.0.0:${port}`);
});
