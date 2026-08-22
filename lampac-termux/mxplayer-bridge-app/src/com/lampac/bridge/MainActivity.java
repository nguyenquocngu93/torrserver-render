package com.lampac.bridge;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.widget.TextView;
import android.widget.ScrollView;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.URL;
import java.net.HttpURLConnection;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;

public class MainActivity extends Activity {
    private static final String TAG = "SubBridge";
    private static final int PORT = 8484;
    private ServerSocket serverSocket;
    private ExecutorService executor = Executors.newFixedThreadPool(4);
    private Handler handler = new Handler(Looper.getMainLooper());
    private TextView logView;
    private ScrollView scroll;
    private volatile boolean running = false;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        scroll = new ScrollView(this);
        logView = new TextView(this);
        logView.setPadding(24, 24, 24, 24);
        logView.setTextSize(14);
        logView.setText("SubBridge v1.0\nStarting server on port " + PORT + "...\n");
        scroll.addView(logView);
        setContentView(scroll);
        startServer();
    }

    private void appendLog(String msg) {
        handler.post(new Runnable() {
            public void run() {
                logView.append(msg + "\n");
                scroll.fullScroll(ScrollView.FOCUS_DOWN);
            }
        });
        Log.d(TAG, msg);
    }

    private void startServer() {
        executor.execute(new Runnable() {
            public void run() {
                try {
                    serverSocket = new ServerSocket();
                    serverSocket.setReuseAddress(true);
                    serverSocket.bind(new InetSocketAddress("0.0.0.0", PORT));
                    running = true;
                    appendLog("[OK] Server listening on 0.0.0.0:" + PORT);
                    while (running) {
                        try {
                            Socket client = serverSocket.accept();
                            final Socket c = client;
                            executor.execute(new Runnable() {
                                public void run() { handleRequest(c); }
                            });
                        } catch (Exception e) {
                            if (running) appendLog("[ERR] Accept: " + e.getMessage());
                        }
                    }
                } catch (Exception e) {
                    appendLog("[ERR] Server failed: " + e.getMessage());
                }
            }
        });
    }

    private void handleRequest(Socket client) {
        try {
            BufferedReader reader = new BufferedReader(
                new InputStreamReader(client.getInputStream(), StandardCharsets.UTF_8));
            String requestLine = reader.readLine();
            if (requestLine == null) { client.close(); return; }
            String[] parts = requestLine.split(" ");
            String method = parts[0];
            String path = parts.length > 1 ? parts[1] : "/";
            int contentLength = 0;
            String line;
            while ((line = reader.readLine()) != null && !line.isEmpty()) {
                if (line.toLowerCase().startsWith("content-length:")) {
                    contentLength = Integer.parseInt(line.substring(15).trim());
                }
            }
            StringBuilder body = new StringBuilder();
            if (method.equals("POST") && contentLength > 0) {
                char[] buffer = new char[contentLength];
                int read = reader.read(buffer, 0, contentLength);
                if (read > 0) body.append(buffer, 0, read);
            }
            reader.close();
            String response;
            if (path.equals("/ping")) {
                response = "{\"status\":\"ok\",\"app\":\"SubBridge\",\"version\":\"1.0\"}";
            } else if (path.equals("/play") && method.equals("POST")) {
                response = handlePlay(body.toString());
            } else {
                response = "{\"error\":\"unknown endpoint\"}";
            }
            byte[] respBytes = response.getBytes(StandardCharsets.UTF_8);
            String header = "HTTP/1.1 200 OK\r\n" +
                "Content-Type: application/json; charset=utf-8\r\n" +
                "Access-Control-Allow-Origin: *\r\n" +
                "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n" +
                "Content-Length: " + respBytes.length + "\r\n" +
                "Connection: close\r\n\r\n";
            OutputStream os = client.getOutputStream();
            os.write(header.getBytes(StandardCharsets.UTF_8));
            os.write(respBytes);
            os.flush();
            os.close();
        } catch (Exception e) {
            appendLog("[ERR] Request: " + e.getMessage());
        } finally {
            try { client.close(); } catch (Exception ignored) {}
        }
    }

    private String handlePlay(String jsonBody) {
        try {
            appendLog("< POST /play");
            String videoUrl = extractJson(jsonBody, "video");
            String subUrl = extractJson(jsonBody, "sub");
            String subFormat = extractJson(jsonBody, "format");
            String subLabel = extractJson(jsonBody, "label");
            String title = extractJson(jsonBody, "title");
            if (videoUrl == null || videoUrl.isEmpty()) {
                return "{\"error\":\"missing video URL\"}";
            }
            appendLog("  Video: " + videoUrl.substring(0, Math.min(80, videoUrl.length())));
            if (subUrl != null) {
                appendLog("  Sub: " + subUrl.substring(0, Math.min(80, subUrl.length())));
            }
            String localSubPath = null;
            if (subUrl != null && !subUrl.isEmpty()) {
                localSubPath = downloadSubtitle(subUrl, subFormat);
            }
            Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setDataAndType(Uri.parse(videoUrl), "video/*");
            if (localSubPath != null) {
                intent.putExtra("subs", new String[]{localSubPath});
                intent.putExtra("subs.name", new String[]{subLabel != null ? subLabel : "Subtitle"});
                intent.putExtra("subs.enable", new String[]{localSubPath});
                appendLog("  > MXPlayer with sub: " + localSubPath);
            } else {
                appendLog("  > MXPlayer (no sub)");
            }
            intent.putExtra("title", title != null ? title : "SubBridge");
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            try {
                intent.setPackage("com.mxtech.videoplayer.pro");
                startActivity(intent);
                appendLog("  [OK] Opened MXPlayer Pro");
                return "{\"status\":\"ok\",\"player\":\"mxpro\",\"sub\":\"" + (localSubPath != null ? "attached" : "none") + "\"}";
            } catch (Exception e1) {
                try {
                    intent.setPackage("com.mxtech.videoplayer.ad");
                    startActivity(intent);
                    appendLog("  [OK] Opened MXPlayer Free");
                    return "{\"status\":\"ok\",\"player\":\"mxfree\",\"sub\":\"" + (localSubPath != null ? "attached" : "none") + "\"}";
                } catch (Exception e2) {
                    intent.setPackage(null);
                    try {
                        startActivity(intent);
                        appendLog("  [OK] Opened default player");
                        return "{\"status\":\"ok\",\"player\":\"default\",\"sub\":\"" + (localSubPath != null ? "attached" : "none") + "\"}";
                    } catch (Exception e3) {
                        appendLog("  [ERR] No video player found!");
                        return "{\"error\":\"no video player installed\"}";
                    }
                }
            }
        } catch (Exception e) {
            appendLog("[ERR] Play: " + e.getMessage());
            return "{\"error\":\"" + e.getMessage() + "\"}";
        }
    }

    private String downloadSubtitle(String subUrl, String format) {
        try {
            appendLog("  Downloading sub...");
            URL url = new URL(subUrl);
            HttpURLConnection conn = (HttpURLConnection) url.openConnection();
            conn.setConnectTimeout(10000);
            conn.setReadTimeout(15000);
            conn.setRequestProperty("User-Agent", "SubBridge/1.0");
            InputStream is = conn.getInputStream();
            String ext = ".srt";
            if (format != null) {
                ext = "." + format;
            } else if (subUrl.contains(".ass")) {
                ext = ".ass";
            } else if (subUrl.contains(".vtt")) {
                ext = ".vtt";
            }
            File subFile = new File(getCacheDir(), "bridge_sub" + ext);
            FileOutputStream fos = new FileOutputStream(subFile);
            byte[] buffer = new byte[4096];
            int read;
            while ((read = is.read(buffer)) != -1) {
                fos.write(buffer, 0, read);
            }
            fos.flush();
            fos.close();
            is.close();
            conn.disconnect();
            appendLog("  [OK] Sub saved: " + subFile.getAbsolutePath() + " (" + subFile.length() + " bytes)");
            return subFile.getAbsolutePath();
        } catch (Exception e) {
            appendLog("  [ERR] Sub download: " + e.getMessage());
            return null;
        }
    }

    private String extractJson(String json, String key) {
        String pattern = "\"" + key + "\"";
        int idx = json.indexOf(pattern);
        if (idx < 0) return null;
        idx = json.indexOf(":", idx + pattern.length());
        if (idx < 0) return null;
        idx++;
        while (idx < json.length() && json.charAt(idx) == ' ') idx++;
        if (idx >= json.length()) return null;
        if (json.charAt(idx) == '"') {
            idx++;
            int end = idx;
            while (end < json.length()) {
                if (json.charAt(end) == '\\') { end += 2; continue; }
                if (json.charAt(end) == '"') break;
                end++;
            }
            return json.substring(idx, end).replace("\\\"", "\"").replace("\\/", "/");
        }
        return null;
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        running = false;
        try { if (serverSocket != null) serverSocket.close(); } catch (Exception ignored) {}
        executor.shutdownNow();
    }
}
