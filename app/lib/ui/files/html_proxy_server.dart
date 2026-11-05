// Serves one workspace HTML file — and the files beside it — over loopback for
// the in-app preview.
//
// A `file://` URL would let the page read the whole device; this proxy only
// answers under a random path prefix, only for paths that stay inside the
// HTML's own directory, and dies with the preview. The bytes come from the
// Host's own `workspaceFiles/readBytes`, so a remote Host works too.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dsh_client/dsh_client.dart';

/// Largest HTML the preview reads at all (the reader's window is 2 MiB).
const htmlPreviewMaxBytes = 4 * 1024 * 1024;

/// Relative files one preview may fetch: count, and bytes in total.
const htmlPreviewMaxFiles = 50;
const htmlPreviewMaxResourceBytes = 8 * 1024 * 1024;

/// A loopback server for one HTML file's preview.
class HtmlPreviewServer {
  HtmlPreviewServer._(
    HttpServer server,
    DshClient client,
    String sessionId,
    String indexPath,
    String token,
    String root,
  ) : _server = server,
      _client = client,
      _sessionId = sessionId,
      _indexPath = indexPath,
      _token = token,
      _root = root,
      _pageUrl = Uri.parse('http://127.0.0.1:${server.port}/$token/');

  final HttpServer _server;
  final DshClient _client;
  final String _sessionId;
  final String _indexPath;
  final String _token;

  /// The HTML's own directory, with a trailing slash ('' at the workspace top).
  final String _root;
  final Uri _pageUrl;

  int _files = 0;
  int _bytes = 0;

  /// A relative file could not be fetched (or the limits were hit): the page
  /// says so instead of showing a hole.
  bool missing = false;

  /// The HTML itself could not be read.
  bool failed = false;

  /// What the WebView loads.
  Uri get pageUrl => _pageUrl;

  static Future<HtmlPreviewServer> start({
    required DshClient client,
    required String sessionId,
    required String path,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final cut = path.lastIndexOf('/');
    final root = cut < 0 ? '' : path.substring(0, cut + 1);
    final preview = HtmlPreviewServer._(server, client, sessionId, path, _newToken(), root);
    server.listen(preview._handle, onError: (Object error, StackTrace stack) {});
    return preview;
  }

  static String _newToken() {
    final random = Random.secure();
    return [for (var i = 0; i < 16; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
  }

  Future<void> close() async {
    try {
      await _server.close(force: true);
    } catch (_) {
      // Already gone.
    }
  }

  /// The preview's own file for an unprefixed name, else null when it leaves
  /// the HTML's directory.
  String? _resolve(List<String> segments) {
    if (segments.isEmpty) return _indexPath;
    final parts = <String>[];
    for (final segment in segments) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (parts.isEmpty) return null;
        parts.removeLast();
        continue;
      }
      parts.add(segment);
    }
    if (parts.isEmpty) return null;
    return '$_root${parts.join('/')}';
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.method != 'GET') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final segments = request.uri.pathSegments;
      if (segments.isEmpty || segments.first != _token) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final rest = segments.sublist(1);
      final path = _resolve(rest);
      if (path == null) {
        response.statusCode = HttpStatus.notFound;
        missing = true;
        return;
      }
      final isIndex = rest.isEmpty;
      if (!isIndex && (_files >= htmlPreviewMaxFiles || _bytes >= htmlPreviewMaxResourceBytes)) {
        response.statusCode = HttpStatus.notFound;
        missing = true;
        return;
      }
      final limit = isIndex
          ? htmlPreviewMaxBytes
          : min(htmlPreviewMaxBytes, htmlPreviewMaxResourceBytes - _bytes);
      final bytes = BytesBuilder(copy: false);
      try {
        await _client.readFile(_sessionId, path, maxBytes: limit, onChunk: bytes.add);
      } catch (_) {
        if (isIndex) {
          failed = true;
        } else {
          missing = true;
        }
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final data = bytes.takeBytes();
      if (!isIndex) {
        _files++;
        _bytes += data.length;
        if (_bytes > htmlPreviewMaxResourceBytes) missing = true;
      }
      response.headers.contentType = _contentType(path);
      response.headers.set('Cache-Control', 'no-store');
      response.add(data);
    } catch (_) {
      // A broken answer still ends: the WebView shows its own error.
      response.statusCode = HttpStatus.internalServerError;
    } finally {
      try {
        await response.close();
      } catch (_) {
        // The WebView went away mid-answer.
      }
    }
  }

  static ContentType _contentType(String path) {
    final dot = path.lastIndexOf('.');
    final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
    final mime = switch (ext) {
      'html' || 'htm' => 'text/html',
      'css' => 'text/css',
      'js' || 'mjs' => 'text/javascript',
      'json' => 'application/json',
      'svg' => 'image/svg+xml',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'ico' => 'image/x-icon',
      'woff' => 'font/woff',
      'woff2' => 'font/woff2',
      'ttf' => 'font/ttf',
      'otf' => 'font/otf',
      'wasm' => 'application/wasm',
      'xml' => 'application/xml',
      'txt' || 'md' || 'csv' => 'text/plain',
      'mp4' => 'video/mp4',
      'webm' => 'video/webm',
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      _ => 'application/octet-stream',
    };
    return ContentType.parse(mime);
  }
}
