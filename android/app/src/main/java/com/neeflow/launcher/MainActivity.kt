package com.neeflow.launcher

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebViewAssetLoader
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

class MainActivity : Activity() {
    private lateinit var launcherView: WebView
    private var fileChooserCallback: ValueCallback<Array<Uri>>? = null

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.rgb(11, 12, 15)
        window.navigationBarColor = Color.rgb(11, 12, 15)

        val assetLoader = WebViewAssetLoader.Builder()
            .addPathHandler("/", WebViewAssetLoader.AssetsPathHandler(this, "www"))
            .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(this, "www/assets"))
            .build()

        launcherView = WebView(this).apply {
            setBackgroundColor(Color.rgb(11, 12, 15))
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.allowFileAccess = false
            settings.allowContentAccess = true
            settings.javaScriptCanOpenWindowsAutomatically = false
            settings.setSupportMultipleWindows(false)
            settings.mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
            webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                    val uri = request.url
                    if (uri.host == ASSET_HOST && uri.path?.startsWith("/api/") == true) {
                        return handleApiRequest(uri)
                    }
                    return assetLoader.shouldInterceptRequest(uri)
                }

                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    val uri = request.url
                    if (uri.scheme == "https" && uri.host == ASSET_HOST) return false
                    if (uri.scheme == "https") {
                        return try {
                            startActivity(Intent(Intent.ACTION_VIEW, uri))
                            true
                        } catch (_: Exception) {
                            true
                        }
                    }
                    return true
                }
            }
            webChromeClient = object : WebChromeClient() {
                override fun onShowFileChooser(
                    webView: WebView,
                    callback: ValueCallback<Array<Uri>>,
                    fileChooserParams: WebChromeClient.FileChooserParams
                ): Boolean {
                    fileChooserCallback?.onReceiveValue(null)
                    fileChooserCallback = callback
                    return try {
                        startActivityForResult(fileChooserParams.createIntent(), FILE_CHOOSER_REQUEST)
                        true
                    } catch (_: Exception) {
                        fileChooserCallback = null
                        callback.onReceiveValue(null)
                        false
                    }
                }
            }
        }
        setContentView(launcherView)
        launcherView.loadUrl("https://$ASSET_HOST/index.html")
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        if (!::launcherView.isInitialized) {
            super.onBackPressed()
            return
        }
        launcherView.evaluateJavascript(
            """(() => {
                const modal = document.querySelector('[data-modal]');
                if (modal && !modal.classList.contains('hidden')) {
                    document.querySelector('[data-close-modal]')?.click();
                    return true;
                }
                const hud = document.querySelector('[data-ingame-settings]');
                if (hud && !hud.hidden) {
                    document.querySelector('[data-hud-settings-close]')?.click();
                    return true;
                }
                return false;
            })()""".trimIndent()
        ) { handled ->
            if (handled != "true") super.onBackPressed()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != FILE_CHOOSER_REQUEST) return
        val callback = fileChooserCallback ?: return
        fileChooserCallback = null
        val results = when {
            resultCode != RESULT_OK -> null
            data?.clipData != null -> Array(data.clipData!!.itemCount) { index -> data.clipData!!.getItemAt(index).uri }
            data?.data != null -> arrayOf(data.data!!)
            else -> null
        }
        callback.onReceiveValue(results)
    }

    override fun onDestroy() {
        if (::launcherView.isInitialized) {
            launcherView.stopLoading()
            launcherView.destroy()
        }
        super.onDestroy()
    }

    private fun handleApiRequest(uri: Uri): WebResourceResponse {
        val response = try {
            when {
                uri.path == "/api/minecraft/catalog" -> jsonResponse(200, minecraftCatalog())
                uri.path == "/api/modrinth/search" -> jsonResponse(200, searchModrinth(uri))
                VERSION_PATH.matches(uri.path.orEmpty()) -> jsonResponse(200, modrinthVersion(uri.path!!.substringAfterLast('/')))
                else -> jsonResponse(404, JSONObject().put("error", "Not found"))
            }
        } catch (error: Exception) {
            jsonResponse(502, JSONObject().put("error", error.message ?: "Network request failed"))
        }
        return response
    }

    private fun minecraftCatalog(): JSONObject {
        val manifest = fetchJson("https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")
        val fabricResult = runCatching { fetchJsonArray("https://meta.fabricmc.net/v2/versions/game") }
        val forgeResult = runCatching { fetchJson("https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json") }
        val optifineResult = runCatching { fetchText("https://optifine.net/downloads") }
        val fabric = fabricResult.getOrDefault(JSONArray())
        val forge = forgeResult.getOrDefault(JSONObject())
        val optifine = optifineResult.getOrDefault("")

        val versions = JSONArray()
        val sourceVersions = manifest.optJSONArray("versions") ?: JSONArray()
        for (index in 0 until sourceVersions.length()) {
            val version = sourceVersions.optJSONObject(index) ?: continue
            val id = version.optString("id")
            if (id.isNotBlank()) {
                versions.put(JSONObject()
                    .put("id", id)
                    .put("type", version.optString("type", "release"))
                    .put("releaseTime", version.optString("releaseTime")))
            }
        }

        val fabricVersions = JSONArray()
        for (index in 0 until fabric.length()) {
            val version = fabric.optJSONObject(index)?.optString("version").orEmpty()
            if (version.isNotBlank()) fabricVersions.put(version)
        }

        val forgePromos = forge.optJSONObject("promos") ?: JSONObject()
        val forgeBuilds = linkedMapOf<String, MutableMap<String, String>>()
        val forgePattern = Regex("^(\\d+\\.\\d+(?:\\.\\d+)?)-(latest|recommended)$")
        val promoKeys = forgePromos.keys()
        while (promoKeys.hasNext()) {
            val key = promoKeys.next()
            val match = forgePattern.matchEntire(key) ?: continue
            val build = forgePromos.optString(key)
            if (build.isNotBlank()) forgeBuilds.getOrPut(match.groupValues[1]) { mutableMapOf() }[match.groupValues[2]] = build
        }
        val forgeVersions = JSONArray()
        forgeBuilds.forEach { (gameVersion, builds) ->
            forgeVersions.put(JSONObject()
                .put("gameVersion", gameVersion)
                .put("build", builds["recommended"] ?: builds["latest"].orEmpty())
                .put("recommended", builds["recommended"].orEmpty()))
        }

        val optifineVersions = JSONArray()
        val optifinePattern = Regex("(?:preview[_-])?OptiFine[_-](\\d+\\.\\d+(?:\\.\\d+)?)(?:[_-]|\\.jar)", RegexOption.IGNORE_CASE)
        optifinePattern.findAll(optifine).map { it.groupValues[1] }.distinct().forEach { optifineVersions.put(it) }
        return JSONObject()
            .put("latest", manifest.optJSONObject("latest") ?: JSONObject())
            .put("versions", versions)
            .put("loaders", JSONObject()
                .put("fabric", fabricVersions)
                .put("forge", forgeVersions)
                .put("optifine", optifineVersions))
            .put("loaderSources", JSONObject()
                .put("fabric", if (fabricResult.isSuccess) "ok" else "unavailable")
                .put("forge", if (forgeResult.isSuccess) "ok" else "unavailable")
                .put("optifine", if (optifineResult.isSuccess) "ok" else "unavailable"))
    }

    private fun searchModrinth(uri: Uri): JSONObject {
        val query = uri.getQueryParameter("query").orEmpty().take(100)
        val sort = uri.getQueryParameter("sort")?.takeIf { it in ALLOWED_SORTS } ?: "downloads"
        val gameVersion = uri.getQueryParameter("gameVersion").orEmpty()
        val loader = uri.getQueryParameter("loader").orEmpty()
        if (gameVersion.isNotEmpty() && !GAME_VERSION.matches(gameVersion)) throw IOException("Invalid Minecraft version")
        if (loader.isNotEmpty() && loader !in ALLOWED_LOADERS) throw IOException("Unsupported loader")

        val facets = JSONArray().put(JSONArray().put("project_type:modpack"))
        if (gameVersion.isNotEmpty()) facets.put(JSONArray().put("versions:$gameVersion"))
        if (loader.isNotEmpty()) facets.put(JSONArray().put("categories:$loader"))
        val requestUrl = Uri.parse("https://api.modrinth.com/v2/search").buildUpon()
            .appendQueryParameter("query", query)
            .appendQueryParameter("facets", facets.toString())
            .appendQueryParameter("index", sort)
            .appendQueryParameter("limit", "12")
            .build()
        val result = fetchJson(requestUrl.toString())
        return JSONObject()
            .put("total_hits", result.optInt("total_hits"))
            .put("hits", result.optJSONArray("hits") ?: JSONArray())
    }

    private fun modrinthVersion(versionId: String): JSONObject {
        if (!VERSION_ID.matches(versionId)) throw IOException("Invalid Modrinth version")
        val result = fetchJson("https://api.modrinth.com/v2/version/$versionId")
        val files = result.optJSONArray("files") ?: JSONArray()
        var selectedFile: JSONObject? = null
        for (index in 0 until files.length()) {
            val file = files.optJSONObject(index) ?: continue
            if (selectedFile == null || file.optBoolean("primary")) selectedFile = file
            if (file.optBoolean("primary")) break
        }
        val file = selectedFile ?: throw IOException("No downloadable Modrinth pack file found")
        val fileUrl = Uri.parse(file.optString("url"))
        if (fileUrl.scheme != "https" || fileUrl.host != "cdn.modrinth.com") throw IOException("Invalid Modrinth download URL")
        return JSONObject()
            .put("version", result.optString("version_number", result.optString("name", "Latest")))
            .put("game_versions", result.optJSONArray("game_versions") ?: JSONArray())
            .put("loaders", result.optJSONArray("loaders") ?: JSONArray())
            .put("file", JSONObject()
                .put("url", fileUrl.toString())
                .put("filename", file.optString("filename", "modpack.mrpack"))
                .put("size", file.optLong("size")))
    }

    private fun fetchJson(url: String): JSONObject = JSONObject(fetchText(url))

    private fun fetchJsonArray(url: String): JSONArray = JSONArray(fetchText(url))

    private fun fetchText(url: String): String {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.requestMethod = "GET"
        connection.connectTimeout = 15_000
        connection.readTimeout = 20_000
        connection.setRequestProperty("Accept", "application/json, text/html;q=0.9, */*;q=0.8")
        connection.setRequestProperty("User-Agent", "NeeflowLauncher/1.0.0 (Android)")
        try {
            val status = connection.responseCode
            if (status !in 200..299) throw IOException("Upstream returned HTTP $status")
            return connection.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
        } finally {
            connection.disconnect()
        }
    }

    private fun jsonResponse(status: Int, value: JSONObject): WebResourceResponse {
        val reason = when (status) {
            200 -> "OK"
            400 -> "Bad Request"
            404 -> "Not Found"
            else -> "Bad Gateway"
        }
        return WebResourceResponse(
            "application/json",
            "utf-8",
            status,
            reason,
            mapOf("Cache-Control" to "no-store", "X-Content-Type-Options" to "nosniff"),
            value.toString().byteInputStream(Charsets.UTF_8)
        )
    }

    companion object {
        private const val ASSET_HOST = "appassets.androidplatform.net"
        private const val FILE_CHOOSER_REQUEST = 7101
        private val VERSION_PATH = Regex("^/api/modrinth/version/[A-Za-z0-9]{5,12}$")
        private val VERSION_ID = Regex("^[A-Za-z0-9]{5,12}$")
        private val GAME_VERSION = Regex("^\\d{1,2}\\.\\d{1,2}(?:\\.\\d{1,2})?$")
        private val ALLOWED_SORTS = setOf("relevance", "downloads", "follows", "newest", "updated")
        private val ALLOWED_LOADERS = setOf("fabric", "forge", "neoforge", "quilt")
    }
}
