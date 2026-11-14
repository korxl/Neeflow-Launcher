package net.kdt.pojavlaunch.fragments;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.Toast;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.fragment.app.Fragment;

import net.kdt.pojavlaunch.CustomControlsActivity;
import net.kdt.pojavlaunch.LauncherActivity;
import net.kdt.pojavlaunch.R;
import net.kdt.pojavlaunch.Tools;
import net.kdt.pojavlaunch.extra.ExtraConstants;
import net.kdt.pojavlaunch.extra.ExtraCore;
import net.kdt.pojavlaunch.prefs.LauncherPreferences;
import net.kdt.pojavlaunch.prefs.screens.LauncherPreferenceFragment;
import net.kdt.pojavlaunch.value.MinecraftAccount;
import net.kdt.pojavlaunch.value.launcherprofiles.LauncherProfiles;
import net.kdt.pojavlaunch.value.launcherprofiles.MinecraftProfile;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.Iterator;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class NeeflowLauncherFragment extends Fragment {
    private WebView webView;
    private ValueCallback<Uri[]> fileChooserCallback;
    private ActivityResultLauncher<Intent> fileChooserLauncher;

    public NeeflowLauncherFragment() {
        super();
    }

    @Override
    public void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        fileChooserLauncher = registerForActivityResult(
                new ActivityResultContracts.StartActivityForResult(), result -> {
                    ValueCallback<Uri[]> callback = fileChooserCallback;
                    fileChooserCallback = null;
                    if (callback == null) return;
                    Intent data = result.getData();
                    if (result.getResultCode() != Activity.RESULT_OK || data == null) {
                        callback.onReceiveValue(null);
                        return;
                    }
                    if (data.getClipData() != null) {
                        Uri[] uris = new Uri[data.getClipData().getItemCount()];
                        for (int i = 0; i < uris.length; i++) uris[i] = data.getClipData().getItemAt(i).getUri();
                        callback.onReceiveValue(uris);
                    } else if (data.getData() != null) {
                        callback.onReceiveValue(new Uri[]{data.getData()});
                    } else {
                        callback.onReceiveValue(null);
                    }
                });
    }

    @NonNull
    @Override
    public View onCreateView(@NonNull android.view.LayoutInflater inflater, @Nullable ViewGroup container, @Nullable Bundle savedInstanceState) {
        webView = new WebView(requireContext());
        webView.setBackgroundColor(Color.rgb(11, 12, 15));
        webView.setInitialScale(90);
        webView.setLayoutParams(new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        webView.getSettings().setJavaScriptEnabled(true);
        webView.getSettings().setDomStorageEnabled(true);
        webView.getSettings().setAllowFileAccess(false);
        webView.getSettings().setAllowContentAccess(true);
        webView.getSettings().setJavaScriptCanOpenWindowsAutomatically(false);
        webView.getSettings().setSupportMultipleWindows(false);
        webView.addJavascriptInterface(new NeeflowBridge(), "NeeflowAndroid");
        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback, FileChooserParams params) {
                if (fileChooserCallback != null) fileChooserCallback.onReceiveValue(null);
                fileChooserCallback = callback;
                try {
                    fileChooserLauncher.launch(params.createIntent());
                    return true;
                } catch (Exception exception) {
                    fileChooserCallback = null;
                    callback.onReceiveValue(null);
                    return false;
                }
            }
        });
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                if (isLauncherAsset(uri)) {
                    try {
                        String assetPath = uri.getPath().substring(1);
                        String contentType = assetPath.endsWith(".png") ? "image/png" : assetPath.endsWith(".html") ? "text/html" : "text/plain";
                        android.content.Context context = getContext();
                        if (context == null) return null;
                        return new WebResourceResponse(contentType, contentType.startsWith("text/") ? "UTF-8" : null, context.getAssets().open(assetPath));
                    } catch (IOException ignored) { return null; }
                }
                return super.shouldInterceptRequest(view, request);
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                return openExternalUrl(request.getUrl());
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                return openExternalUrl(Uri.parse(url));
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                super.onPageFinished(view, url);
                view.evaluateJavascript("(function(){if(window.__neeflowFetchReady)return;window.__neeflowFetchReady=true;var originalFetch=window.fetch.bind(window);window.fetch=function(input,init){var target=typeof input==='string'?input:(input&&input.url)||'';var url;try{url=new URL(target,window.location.href)}catch(e){return originalFetch(input,init)}if(url.pathname.indexOf('/api/')!==0)return originalFetch(input,init);return Promise.resolve().then(function(){var body=window.NeeflowAndroid.fetchApi(url.pathname+url.search);var data=JSON.parse(body);return{ok:!data.error,status:data.error?502:200,json:function(){return Promise.resolve(data)},text:function(){return Promise.resolve(body)}}})}})();", null);
            }
        });
        webView.setDownloadListener((url, userAgent, contentDisposition, mimeType, contentLength) -> openExternalUrl(Uri.parse(url)));
        webView.loadUrl("https://appassets.androidplatform.net/neeflow/index.html");
        return webView;
    }

    private boolean isLauncherAsset(Uri uri) {
        return "https".equalsIgnoreCase(uri.getScheme())
                && "appassets.androidplatform.net".equalsIgnoreCase(uri.getHost())
                && uri.getPath() != null
                && uri.getPath().startsWith("/neeflow/");
    }

    private boolean openExternalUrl(Uri uri) {
        if (isLauncherAsset(uri)) return false;
        if ("https".equalsIgnoreCase(uri.getScheme())) {
            try {
                startActivity(new Intent(Intent.ACTION_VIEW, uri));
            } catch (Exception ignored) { }
        }
        return true;
    }

    public boolean handleBack() {
        if (webView == null) return false;
        webView.evaluateJavascript("(function(){var modal=document.querySelector('[data-modal]');if(modal&&!modal.classList.contains('hidden')){document.querySelector('[data-close-modal]')&&document.querySelector('[data-close-modal]').click();return true}var panel=document.querySelector('[data-ingame-settings]');if(panel&&!panel.hidden){document.querySelector('[data-hud-settings-close]')&&document.querySelector('[data-hud-settings-close]').click();return true}return false})()", value -> {
            if (!"true".equals(value) && isAdded()) requireActivity().finish();
        });
        return true;
    }

    @Override
    public void onDestroyView() {
        if (webView != null) {
            webView.removeJavascriptInterface("NeeflowAndroid");
            webView.stopLoading();
            webView.destroy();
            webView = null;
        }
        super.onDestroyView();
    }

    private LauncherActivity launcherActivity() {
        return (LauncherActivity) requireActivity();
    }

    private JSONObject error(String message) {
        JSONObject result = new JSONObject();
        try { result.put("error", message); } catch (JSONException ignored) { }
        return result;
    }

    private JSONObject ok(String id) {
        JSONObject result = new JSONObject();
        try { result.put("ok", true).put("id", id); } catch (JSONException ignored) { }
        return result;
    }

    private final class NeeflowBridge {
        @JavascriptInterface
        public synchronized String getLauncherState() {
            try {
                LauncherProfiles.load();
                String selected = LauncherPreferences.DEFAULT_PREF.getString(LauncherPreferences.PREF_KEY_CURRENT_PROFILE, "");
                if (!LauncherProfiles.mainProfileJson.profiles.containsKey(selected) && !LauncherProfiles.mainProfileJson.profiles.isEmpty()) {
                    selected = LauncherProfiles.mainProfileJson.profiles.keySet().iterator().next();
                    LauncherPreferences.DEFAULT_PREF.edit().putString(LauncherPreferences.PREF_KEY_CURRENT_PROFILE, selected).apply();
                }
                JSONArray profiles = new JSONArray();
                for (String id : LauncherProfiles.mainProfileJson.profiles.keySet()) {
                    MinecraftProfile profile = LauncherProfiles.mainProfileJson.profiles.get(id);
                    if (profile == null || profile.lastVersionId == null || "Unknown".equals(profile.lastVersionId)) continue;
                    profiles.put(new JSONObject()
                            .put("id", id)
                            .put("name", profile.name == null || profile.name.isEmpty() ? profile.lastVersionId : profile.name)
                            .put("gameVersion", profile.lastVersionId)
                            .put("loader", "vanilla"));
                }
                MinecraftAccount account = launcherActivity().getNeeflowSelectedAccount();
                return new JSONObject()
                        .put("username", account == null ? "" : account.username)
                        .put("selectedProfileId", selected)
                        .put("profiles", profiles).toString();
            } catch (Exception exception) {
                return error(exception.getMessage() == null ? "Could not read launcher profiles" : exception.getMessage()).toString();
            }
        }

        @JavascriptInterface
        public synchronized String getRuntimeSettings() {
            try {
                int resolutionRatio = LauncherPreferences.DEFAULT_PREF.contains("resolutionRatio")
                        ? LauncherPreferences.DEFAULT_PREF.getInt("resolutionRatio", 100)
                        : Math.round(LauncherPreferences.PREF_SCALE_FACTOR * 100f);
                int allocation = LauncherPreferences.DEFAULT_PREF.getInt("allocation", LauncherPreferences.PREF_RAM_ALLOCATION);
                return new JSONObject()
                        .put("resolutionRatio", resolutionRatio)
                        .put("allocation", allocation)
                        .put("maxAllocation", getMaxRamAllocation())
                        .put("javaArgs", LauncherPreferences.DEFAULT_PREF.getString("javaArgs", ""))
                        .put("forceVsync", LauncherPreferences.DEFAULT_PREF.getBoolean("force_vsync", LauncherPreferences.PREF_FORCE_VSYNC))
                        .toString();
            } catch (Exception exception) {
                return error(exception.getMessage() == null ? "Could not read runtime settings" : exception.getMessage()).toString();
            }
        }

        @JavascriptInterface
        public synchronized String setRuntimeSetting(String key, String value) {
            try {
                if (key == null || value == null) return error("Некорректная настройка.").toString();
                switch (key) {
                    case "resolutionRatio": {
                        int ratio = Integer.parseInt(value);
                        if (ratio < 25 || ratio > 100 || (ratio - 25) % 5 != 0) return error("Масштаб разрешения должен быть от 25% до 100% с шагом 5%.").toString();
                        LauncherPreferences.DEFAULT_PREF.edit().putInt("resolutionRatio", ratio).apply();
                        LauncherPreferences.PREF_SCALE_FACTOR = ratio / 100f;
                        return ok(value).toString();
                    }
                    case "allocation": {
                        int allocation = Integer.parseInt(value);
                        if (allocation < 256 || allocation > getMaxRamAllocation() || (allocation - 256) % 8 != 0) return error("Выбранный объём памяти выходит за безопасный диапазон устройства.").toString();
                        LauncherPreferences.DEFAULT_PREF.edit().putInt("allocation", allocation).apply();
                        LauncherPreferences.PREF_RAM_ALLOCATION = allocation;
                        return ok(value).toString();
                    }
                    case "javaArgs": {
                        if (value.length() > 2000) return error("Аргументы JVM не должны превышать 2000 символов.").toString();
                        String javaArgs = value.replace('\n', ' ').replace('\r', ' ').replace('\t', ' ').trim();
                        LauncherPreferences.DEFAULT_PREF.edit().putString("javaArgs", javaArgs).apply();
                        LauncherPreferences.PREF_CUSTOM_JAVA_ARGS = javaArgs;
                        return ok(javaArgs).toString();
                    }
                    case "force_vsync": {
                        if (!"true".equals(value) && !"false".equals(value)) return error("Некорректное значение VSync.").toString();
                        boolean enabled = Boolean.parseBoolean(value);
                        LauncherPreferences.DEFAULT_PREF.edit().putBoolean("force_vsync", enabled).apply();
                        LauncherPreferences.PREF_FORCE_VSYNC = enabled;
                        return ok(value).toString();
                    }
                    default:
                        return error("Эта настройка не подключена к игровому рантайму.").toString();
                }
            } catch (NumberFormatException exception) {
                return error("Некорректное значение настройки.").toString();
            } catch (Exception exception) {
                return error(exception.getMessage() == null ? "Не удалось сохранить настройку рантайма." : exception.getMessage()).toString();
            }
        }

        private int getMaxRamAllocation() {
            int deviceRam = Tools.getTotalDeviceMemory(requireContext());
            int maximum = net.kdt.pojavlaunch.Architecture.is32BitsDevice() || deviceRam < 2048
                    ? Math.min(1024, deviceRam)
                    : deviceRam - (deviceRam < 3064 ? 800 : 1024);
            maximum = Math.max(256, maximum);
            return 256 + ((maximum - 256) / 8) * 8;
        }

        @JavascriptInterface
        public synchronized String saveProfile(String profileId, String name, String gameVersion, String loader) {
            if (!"vanilla".equals(loader)) return error("В Android-интерфейсе пока доступны Vanilla-профили. Загрузчики модов можно установить через настройки Amethyst.").toString();
            if (gameVersion == null || !GAME_VERSION.matcher(gameVersion).matches()) return error("Некорректная версия Minecraft.").toString();
            if (name == null || name.trim().isEmpty() || name.trim().length() > 40) return error("Название профиля должно содержать от 1 до 40 символов.").toString();
            try {
                LauncherProfiles.load();
                MinecraftProfile profile = LauncherProfiles.mainProfileJson.profiles.get(profileId);
                String id = profile == null ? null : profileId;
                if (profile == null) {
                    for (String currentId : LauncherProfiles.mainProfileJson.profiles.keySet()) {
                        MinecraftProfile candidate = LauncherProfiles.mainProfileJson.profiles.get(currentId);
                        if (candidate != null && gameVersion.equals(candidate.lastVersionId) && name.trim().equals(candidate.name)) {
                            profile = candidate;
                            id = currentId;
                            break;
                        }
                    }
                }
                if (profile == null) {
                    profile = MinecraftProfile.createTemplate();
                    id = LauncherProfiles.getFreeProfileKey();
                    LauncherProfiles.mainProfileJson.profiles.put(id, profile);
                }
                profile.name = name.trim();
                profile.lastVersionId = gameVersion;
                LauncherProfiles.write();
                LauncherPreferences.DEFAULT_PREF.edit().putString(LauncherPreferences.PREF_KEY_CURRENT_PROFILE, id).apply();
                return ok(id).toString();
            } catch (Exception exception) {
                return error(exception.getMessage() == null ? "Не удалось сохранить профиль." : exception.getMessage()).toString();
            }
        }

        @JavascriptInterface
        public synchronized String selectProfile(String profileId) {
            try {
                LauncherProfiles.load();
                if (!LauncherProfiles.mainProfileJson.profiles.containsKey(profileId)) return error("Профиль Minecraft не найден.").toString();
                LauncherPreferences.DEFAULT_PREF.edit().putString(LauncherPreferences.PREF_KEY_CURRENT_PROFILE, profileId).apply();
                return ok(profileId).toString();
            } catch (Exception exception) {
                return error(exception.getMessage() == null ? "Не удалось выбрать профиль." : exception.getMessage()).toString();
            }
        }

        @JavascriptInterface
        public synchronized String deleteProfile(String profileId) {
            try {
                LauncherProfiles.load();
                if (!LauncherProfiles.mainProfileJson.profiles.containsKey(profileId)) return ok("").toString();
                if (LauncherProfiles.mainProfileJson.profiles.size() <= 1) return error("Нельзя удалить последний профиль Minecraft.").toString();
                LauncherProfiles.mainProfileJson.profiles.remove(profileId);
                String active = LauncherPreferences.DEFAULT_PREF.getString(LauncherPreferences.PREF_KEY_CURRENT_PROFILE, "");
                if (profileId.equals(active)) {
                    active = LauncherProfiles.mainProfileJson.profiles.keySet().iterator().next();
                    LauncherPreferences.DEFAULT_PREF.edit().putString(LauncherPreferences.PREF_KEY_CURRENT_PROFILE, active).apply();
                }
                LauncherProfiles.write();
                return ok(active).toString();
            } catch (Exception exception) {
                return error(exception.getMessage() == null ? "Не удалось удалить профиль." : exception.getMessage()).toString();
            }
        }

        @JavascriptInterface
        public String saveUsername(String username) {
            if (username == null || !LOCAL_USERNAME.matcher(username).matches()) return error("Ник должен содержать от 3 до 16 латинских букв, цифр или подчёркиваний.").toString();
            LauncherActivity activity = launcherActivity();
            activity.runOnUiThread(() -> activity.selectNeeflowLocalAccount(username));
            return ok(username).toString();
        }

        @JavascriptInterface
        public String launchGame(String profileId, String username) {
            if (username == null || !LOCAL_USERNAME.matcher(username).matches()) return error("Сначала укажи игровой ник длиной 3–16 символов.").toString();
            LauncherActivity activity = launcherActivity();
            activity.runOnUiThread(() -> activity.launchNeeflowGame(profileId, username));
            return ok(profileId).toString();
        }

        @JavascriptInterface
        public void openTouchControls() {
            LauncherActivity activity = launcherActivity();
            activity.runOnUiThread(() -> activity.startActivity(new Intent(activity, CustomControlsActivity.class)));
        }

        @JavascriptInterface
        public void openRuntimeSettings() {
            LauncherActivity activity = launcherActivity();
            activity.runOnUiThread(() -> Tools.swapFragment(activity, LauncherPreferenceFragment.class, LauncherActivity.SETTING_FRAGMENT_TAG, null));
        }

        @JavascriptInterface
        public String fetchApi(String route) {
            try {
                if (route == null) throw new IOException("Invalid API route");
                if ("/api/minecraft/catalog".equals(route)) return minecraftCatalog().toString();
                if (route.startsWith("/api/modrinth/search?")) return modrinthSearch(route).toString();
                Matcher versionMatcher = MODRINTH_VERSION_PATH.matcher(route);
                if (versionMatcher.matches()) return modrinthVersion(versionMatcher.group(1)).toString();
                return error("API route not found").toString();
            } catch (Exception exception) {
                return error(exception.getMessage() == null ? "Network request failed" : exception.getMessage()).toString();
            }
        }
    }

    private JSONObject minecraftCatalog() throws IOException, JSONException {
        JSONObject manifest = fetchJson("https://piston-meta.mojang.com/mc/game/version_manifest_v2.json");
        JSONArray fabric = new JSONArray();
        try {
            JSONArray source = fetchJsonArray("https://meta.fabricmc.net/v2/versions/game");
            for (int i = 0; i < source.length(); i++) {
                JSONObject item = source.optJSONObject(i);
                if (item != null && item.optString("version").length() > 0) fabric.put(item.optString("version"));
            }
        } catch (Exception ignored) { }

        JSONArray forge = new JSONArray();
        try {
            JSONObject source = fetchJson("https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json").optJSONObject("promos");
            if (source != null) {
                Iterator<String> keys = source.keys();
                Pattern promoPattern = Pattern.compile("^(\\d+\\.\\d+(?:\\.\\d+)?)-(latest|recommended)$");
                JSONObject builds = new JSONObject();
                while (keys.hasNext()) {
                    String key = keys.next();
                    Matcher match = promoPattern.matcher(key);
                    if (match.matches()) {
                        JSONObject build = builds.optJSONObject(match.group(1));
                        if (build == null) build = new JSONObject();
                        build.put(match.group(2), source.optString(key));
                        builds.put(match.group(1), build);
                    }
                }
                Iterator<String> gameVersions = builds.keys();
                while (gameVersions.hasNext()) {
                    String gameVersion = gameVersions.next();
                    JSONObject build = builds.getJSONObject(gameVersion);
                    forge.put(new JSONObject().put("gameVersion", gameVersion)
                            .put("build", build.optString("recommended", build.optString("latest")))
                            .put("recommended", build.optString("recommended")));
                }
            }
        } catch (Exception ignored) { }

        JSONArray optifine = new JSONArray();
        try {
            String html = fetchText("https://optifine.net/downloads");
            Matcher matcher = Pattern.compile("(?:preview[_-])?OptiFine[_-](\\d+\\.\\d+(?:\\.\\d+)?)(?:[_-]|\\.jar)", Pattern.CASE_INSENSITIVE).matcher(html);
            while (matcher.find()) if (!contains(optifine, matcher.group(1))) optifine.put(matcher.group(1));
        } catch (Exception ignored) { }

        JSONArray versions = new JSONArray();
        JSONArray sourceVersions = manifest.optJSONArray("versions");
        if (sourceVersions != null) {
            for (int i = 0; i < sourceVersions.length(); i++) {
                JSONObject item = sourceVersions.optJSONObject(i);
                if (item != null && !item.optString("id").isEmpty()) {
                    versions.put(new JSONObject().put("id", item.optString("id"))
                            .put("type", item.optString("type", "release"))
                            .put("releaseTime", item.optString("releaseTime")));
                }
            }
        }
        return new JSONObject().put("latest", manifest.optJSONObject("latest") == null ? new JSONObject() : manifest.optJSONObject("latest"))
                .put("versions", versions)
                .put("loaders", new JSONObject().put("fabric", fabric).put("forge", forge).put("optifine", optifine))
                .put("loaderSources", new JSONObject().put("fabric", fabric.length() > 0 ? "ok" : "unavailable")
                        .put("forge", forge.length() > 0 ? "ok" : "unavailable")
                        .put("optifine", optifine.length() > 0 ? "ok" : "unavailable"));
    }

    private JSONObject modrinthSearch(String route) throws IOException, JSONException {
        Uri query = Uri.parse("https://appassets.androidplatform.net" + route);
        String search = query.getQueryParameter("query");
        String sort = query.getQueryParameter("sort");
        if (sort == null || !SORTS.contains(sort)) sort = "downloads";
        String gameVersion = query.getQueryParameter("gameVersion");
        String loader = query.getQueryParameter("loader");
        if (gameVersion != null && !gameVersion.isEmpty() && !GAME_VERSION.matcher(gameVersion).matches()) throw new IOException("Invalid Minecraft version");
        if (loader != null && !loader.isEmpty() && !LOADERS.contains(loader)) throw new IOException("Unsupported loader");
        JSONArray facets = new JSONArray().put(new JSONArray().put("project_type:modpack"));
        if (gameVersion != null && !gameVersion.isEmpty()) facets.put(new JSONArray().put("versions:" + gameVersion));
        if (loader != null && !loader.isEmpty()) facets.put(new JSONArray().put("categories:" + loader));
        Uri.Builder url = Uri.parse("https://api.modrinth.com/v2/search").buildUpon()
                .appendQueryParameter("query", search == null ? "" : search.substring(0, Math.min(100, search.length())))
                .appendQueryParameter("facets", facets.toString())
                .appendQueryParameter("index", sort)
                .appendQueryParameter("limit", "12");
        return fetchJson(url.build().toString());
    }

    private JSONObject modrinthVersion(String versionId) throws IOException, JSONException {
        JSONObject result = fetchJson("https://api.modrinth.com/v2/version/" + versionId);
        JSONArray files = result.optJSONArray("files");
        JSONObject selected = null;
        if (files != null) {
            for (int i = 0; i < files.length(); i++) {
                JSONObject item = files.optJSONObject(i);
                if (item == null) continue;
                if (selected == null || item.optBoolean("primary")) selected = item;
                if (item.optBoolean("primary")) break;
            }
        }
        if (selected == null) throw new IOException("No downloadable Modrinth pack file found");
        Uri fileUrl = Uri.parse(selected.optString("url"));
        if (!"https".equals(fileUrl.getScheme()) || !"cdn.modrinth.com".equals(fileUrl.getHost())) throw new IOException("Invalid Modrinth download URL");
        return new JSONObject().put("version", result.optString("version_number", result.optString("name", "Latest")))
                .put("game_versions", result.optJSONArray("game_versions") == null ? new JSONArray() : result.optJSONArray("game_versions"))
                .put("loaders", result.optJSONArray("loaders") == null ? new JSONArray() : result.optJSONArray("loaders"))
                .put("file", new JSONObject().put("url", fileUrl.toString())
                        .put("filename", selected.optString("filename", "modpack.mrpack"))
                        .put("size", selected.optLong("size")));
    }

    private static JSONObject fetchJson(String url) throws IOException, JSONException {
        return new JSONObject(fetchText(url));
    }

    private static JSONArray fetchJsonArray(String url) throws IOException, JSONException {
        return new JSONArray(fetchText(url));
    }

    private static String fetchText(String url) throws IOException {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setRequestMethod("GET");
        connection.setConnectTimeout(15000);
        connection.setReadTimeout(20000);
        connection.setRequestProperty("Accept", "application/json, text/html;q=0.9, */*;q=0.8");
        connection.setRequestProperty("User-Agent", "NeeflowLauncher/1.0.0 (Android)");
        try {
            int status = connection.getResponseCode();
            if (status < 200 || status >= 300) throw new IOException("Upstream returned HTTP " + status);
            BufferedReader reader = new BufferedReader(new InputStreamReader(connection.getInputStream(), "UTF-8"));
            StringBuilder result = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) result.append(line);
            reader.close();
            return result.toString();
        } finally {
            connection.disconnect();
        }
    }

    private static boolean contains(JSONArray array, String value) {
        for (int i = 0; i < array.length(); i++) if (value.equals(array.optString(i))) return true;
        return false;
    }

    private static final Pattern LOCAL_USERNAME = Pattern.compile("^[A-Za-z0-9_]{3,16}$");
    private static final Pattern GAME_VERSION = Pattern.compile("^[A-Za-z0-9][A-Za-z0-9._+-]{0,31}$");
    private static final Pattern MODRINTH_VERSION_PATH = Pattern.compile("^/api/modrinth/version/([A-Za-z0-9]{5,12})$");
    private static final java.util.Set<String> SORTS = new java.util.HashSet<String>() {{ add("relevance"); add("downloads"); add("follows"); add("newest"); add("updated"); }};
    private static final java.util.Set<String> LOADERS = new java.util.HashSet<String>() {{ add("fabric"); add("forge"); add("neoforge"); add("quilt"); }};
}
