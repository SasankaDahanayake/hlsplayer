import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:path/path.dart' as path;

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({Key? key, required this.videoName}) : super(key: key);

  final String videoName;

  @override
  _PlayerScreenState createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  // final String baseUrl = 'http://140.245.49.98/video-files/1/';
  // final List<String> files = [
  //   'playlist.m3u8',
  //   'segment0.ts',
  //   'segment1.ts',
  //   'segment2.ts',
  //   'segment3.ts',
  // ];

  late final WebViewController _controller;
  HttpServer? server;

  @override
  void initState() {
    super.initState();
    startServer(widget.videoName); // Start the server in the main isolate
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            print('Page started loading: $url');
          },
          onPageFinished: (String url) {
            print('Page finished loading: $url');
          },
          onWebResourceError: (error) {
            print('Web resource error: ${error.description}');
          },
        ),
      );
    downloadFilesAndLoadWebView();
  }

  @override
  void dispose() {
    server?.close();
    super.dispose();
  }

  Future<void> downloadFilesAndLoadWebView() async {
    try {
      // await downloadFiles();
      checkServerStatusAndLoadWebView();
    } catch (e) {
      print('Error in downloading files or loading WebView: $e');
    }
  }

  // Future<void> downloadFiles() async {
  //   Directory tempDir = await getTemporaryDirectory();
  //   for (String file in files) {
  //     String url = '$baseUrl$file';
  //     try {
  //       http.Response response = await http.get(Uri.parse(url));
  //       if (response.statusCode == 200) {
  //         File tempFile = File('${tempDir.path}/$file');
  //         await tempFile.writeAsBytes(response.bodyBytes);
  //         print('Downloaded $file to ${tempFile.path}');
  //       } else {
  //         print('Failed to download $file');
  //       }
  //     } catch (e) {
  //       print('Error downloading $file: $e');
  //     }
  //   }
  // }

  void checkServerStatusAndLoadWebView() async {
    bool serverReady = await isServerRunning();
    if (serverReady) {
      print('Server is ready, loading WebView...');
      _controller.loadRequest(Uri.parse('http://localhost:8889/player.html'));
    } else {
      print('Server is not ready yet, retrying in 2 seconds...');
      Future.delayed(
          const Duration(seconds: 2), checkServerStatusAndLoadWebView);
    }
  }

  Future<bool> isServerRunning() async {
    try {
      final httpClient = HttpClient();
      final request = await httpClient
          .getUrl(Uri.parse('http://localhost:8889/player.html'))
          .timeout(const Duration(seconds: 5));
      final response = await request.close();
      return response.statusCode == 200;
    } catch (e) {
      print('Error checking server status: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }

  void startServer(String videoName) async {
    var handler = const shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addHandler(
            (shelf.Request request) => _handleRequest(request, videoName));

    server = await io.serve(handler, '0.0.0.0', 8889);
    print('Server is running at http://${server?.address.host}:${server?.port}');
  }

  Future<shelf.Response> _handleRequest(
      shelf.Request request, String videoName) async {
    final String assetPath = Uri.decodeComponent(request.url.path);
    const String videoSrc = 'playlist.m3u8';
    const String segmentSrc = 'segment';

    print('Received request for URL path: ${request.url.path}');
    print('Decoded asset path: $assetPath');

    if (assetPath.contains(videoSrc) || assetPath.contains(segmentSrc)) {
      final Directory tempDir = await getTemporaryDirectory();
      final String filePath =
          path.join(tempDir.path, 'video-files', videoName, assetPath);

      print('this is the $filePath');

      if (await File(filePath).exists()) {
        final file = File(filePath);
        final mimeType = _getMimeType(filePath);
        final bytes = await file.readAsBytes();
        return shelf.Response.ok(
          bytes,
          headers: {'Content-Type': mimeType},
        );
      } else {
        return shelf.Response.notFound('Video file not found');
      }
    } else {
      // Determine the actual file path within the assets directory
      final String filePath = 'assets/web/$assetPath';
      print('Constructed file path: $filePath');

      // Check if the file exists
      if (await _fileExists(filePath)) {
        print('File exists: $filePath');
        final byteData = await rootBundle.load(filePath);
        final mimeType = _getMimeType(filePath);
        print('Serving asset: $filePath with MIME type: $mimeType');
        return shelf.Response.ok(
          byteData.buffer.asUint8List(),
          headers: {'Content-Type': mimeType},
        );
      } else {
        // Return a 404 response if the asset is not found
        print('Error: Asset not found: $filePath');
        return shelf.Response.notFound('Asset not found');
      }
    }
  }
}

Future<bool> _fileExists(String filePath) async {
  try {
    await rootBundle.load(filePath);
    return true;
  } catch (e) {
    print('Error checking file existence: $e');
    return false;
  }
}

String _getMimeType(String filePath) {
  final extension = path.extension(filePath);
  final mimeType = {
        '.html': 'text/html',
        '.js': 'application/javascript',
        '.css': 'text/css',
        '.png': 'image/png',
        '.jpg': 'image/jpeg',
        '.jpeg': 'image/jpeg',
        '.m3u8': 'application/vnd.apple.mpegurl',
        '.ts': 'video/MP2T',
        '.key': 'application/octet-stream',
      }[extension] ??
      'application/octet-stream';

  print('Determined MIME type for $filePath: $mimeType');
  return mimeType;
}
