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
        logView.setText("SubBridge v2.0\nListening on port " + PORT + "\n\n");
        scroll.addView(logView);
        setContentView(scroll);
        startServer();
    }

    private void appendLog(final String msg) {
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
                    appendLog("[OK] Server ready");
                    while (running) {
                        try {
                            Socket client = serverSocket.accept();
                            final Socket c = client;
                            executor.execute(new Runnable() {
                                public void run() { handleRequest(c); }
                            });
                        } catch (Exception e) {
                            if (running) appendLog("[ERR] " + e.getMessage());
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
                int totalRead = 0;
                while (totalRead < contentLength) {
                    int read = reader.read(buffer, totalRead, contentLength - totalRead);
                    if (read < 0) break;
                    totalRead += read;
                }
                body.append(buffer, 0, totalRead);
            }
            reader.close();

            String response;
            if (method.equals("OPTIONS")) {
                response = "";
            } else if (path.equals("/ping")) {
                response = "{\"status\":\"ok\",\"app\":\"SubBridge\",\"version\":\"2.0\"}";
            } else if (path.equals("/play") && method.equals("POST")) {
                response = handlePlay(body.toString());
            } else {
                response = "{\"error\":\"unknown endpoint\"}";
            }

            byte[] respBytes = response.getBytes(StandardCharsets.UTF_8);
            String header = "HTTP/1.1 200 OK\r\n"
                + "Content-Type: application/json; charset=utf-8\r\n"
                + "Access-Control-Allow-Origin: *\r\n"
                + "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
                + "Access-Control-Allow-Headers: Content-Type\r\n"
                + "Content-Length: " + respBytes.length + "\r\n"
                + "Connection: close\r\n\r\n";

            OutputStream os = client.getOutputStream();
            os.write(header.getBytes(StandardCharsets.UTF_8));
            if (respBytes.length > 0) os.write(respBytes);
            os.flush();
            os.close();
        } catch (Exception e) {
            appendLog("[ERR] " + e.getMessage());
        } finally {
            try { client.close(); } catch (Exception ignored) {}
        }
    }

    private String handlePlay(String jsonBody) {
        try {
            appendLog(">> POST /play");
            String videoUrl = extractJson(jsonBody, "video");
            String subUrl = extractJson(jsonBody, "sub");
            String subFormat = extractJson(jsonBody, "format");
            String subLabel = extractJson(jsonBody, "label");
            String title = extractJson(jsonBody, "title");

            if (videoUrl == null || videoUrl.isEmpty()) {
                return "{\"error\":\"missing video URL\"}";
            }

            appendLog("  URL: " + videoUrl.substring(0, Math.min(100, videoUrl.length())));

            // Download subtitle if provided
            String localSubPath = null;
            if (subUrl != null && !subUrl.isEmpty()) {
                appendLog("  Sub: " + subUrl.substring(0, Math.min(80, subUrl.length())));
                localSubPath = downloadSubtitle(subUrl, subFormat);
            }

            // Build MXPlayer intent
            final Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setDataAndType(Uri.parse(videoUrl), "video/*");
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);

            // Title
            if (title != null && !title.isEmpty()) {
                intent.putExtra("title", title);
            }

            // Subtitle extras for MXPlayer
            if (localSubPath != null) {
                intent.putExtra("subs", new String[]{localSubPath});
                intent.putExtra("subs.name", new String[]{subLabel != null ? subLabel : "Subtitle"});
                intent.putExtra("subs.enable", new String[]{localSubPath});
                appendLog("  Sub attached: " + localSubPath);
            }

            // Launch on main thread
            handler.post(new Runnable() {
                public void run() {
                    try {
                        // Try MXPlayer Pro first
                        intent.setPackage("com.mxtech.videoplayer.pro");
                        startActivity(intent);
                        appendLog("  >> MXPlayer Pro");
                    } catch (Exception e1) {
                        try {
                            // Try MXPlayer Free
                            intent.setPackage("com.mxtech.videoplayer.ad");
                            startActivity(intent);
                            appendLog("  >> MXPlayer Free");
                        } catch (Exception e2) {
                            try {
                                // Try any video player
                                intent.setPackage(null);
                                startActivity(intent);
                                appendLog("  >> Default player");
                            } catch (Exception e3) {
                                appendLog("  !! No video player found");
                            }
                        }
                    }
                }
            });

            String subStatus = localSubPath != null ? "attached" : "none";
            return "{\"status\":\"ok\",\"sub\":\"" + subStatus + "\"}";

        } catch (Exception e) {
            appendLog("[ERR] " + e.getMessage());
            return "{\"error\":\"" + e.getMessage().replace("\"", "'") + "\"}";
        }
    }

    private String downloadSubtitle(String subUrl, String format) {
        try {
            appendLog("  Downloading sub...");
            URL url = new URL(subUrl);
            HttpURLConnection conn = (HttpURLConnection) url.openConnection();
            conn.setConnectTimeout(10000);
            conn.setReadTimeout(15000);
            conn.setRequestProperty("User-Agent", "SubBridge/2.0");
            InputStream is = conn.getInputStream();

            String ext = ".srt";
            if (format != null && !format.isEmpty()) {
                ext = "." + format;
            } else if (subUrl.contains(".ass")) ext = ".ass";
            else if (subUrl.contains(".vtt")) ext = ".vtt";
            else if (subUrl.contains(".sub")) ext = ".sub";

            File subFile = new File(getCacheDir(), "bridge_sub" + ext);
            FileOutputStream fos = new FileOutputStream(subFile);
            byte[] buffer = new byte[4096];
            int read;
            long total = 0;
            while ((read = is.read(buffer)) != -1) {
                fos.write(buffer, 0, read);
                total += read;
            }
            fos.flush();
            fos.close();
            is.close();
            conn.disconnect();

            appendLog("  Sub saved: " + total + " bytes");
            return subFile.getAbsolutePath();
        } catch (Exception e) {
            appendLog("  Sub download failed: " + e.getMessage());
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
            StringBuilder sb = new StringBuilder();
            while (idx < json.length()) {
                char c = json.charAt(idx);
                if (c == '\\' && idx + 1 < json.length()) {
                    char next = json.charAt(idx + 1);
                    if (next == '"') sb.append('"');
                    else if (next == '\\') sb.append('\\');
                    else if (next == '/') sb.append('/');
                    else if (next == 'n') sb.append('\n');
                    else { sb.append(c); sb.append(next); }
                    idx += 2;
                    continue;
                }
                if (c == '"') break;
                sb.append(c);
                idx++;
            }
            return sb.toString();
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
