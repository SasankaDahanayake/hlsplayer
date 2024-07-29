import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;

void main() {
  WidgetsFlutterBinding.ensureInitialized(); // Ensure binding is initialized
  runApp(const MyApp());
  startServer(); // Start the server in the main isolate
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Generic WebView Player')),
        body: const PlayerScreen(),
      ),
    );
  }
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({Key? key}) : super(key: key);

  @override
  _PlayerScreenState createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final String downloadUrl = 'http://140.245.49.98/video-files/1/';
  final List<String> files = [
    'playlist.m3u8',
    'segment0.ts',
    'segment1.ts',
    'segment2.ts',
    'segment3.ts',
  ];

  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
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
    downloadFilesAndCopyAssets();
  }

  Future<void> downloadFilesAndCopyAssets() async {
    try {
      await downloadFiles();
      await copyAssetsToTempDir();
      checkServerStatusAndLoadWebView();
    } catch (e) {
      print('Error in downloading files or copying assets: $e');
    }
  }

  Future<void> downloadFiles() async {
    Directory tempDir = await getTemporaryDirectory();
    for (String file in files) {
      String url = '$downloadUrl$file';
      try {
        http.Response response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          File tempFile = File('${tempDir.path}/$file');
          await tempFile.writeAsBytes(response.bodyBytes);
          print('Downloaded $file to ${tempFile.path}');
        } else {
          print('Failed to download $file');
        }
      } catch (e) {
        print('Error downloading $file: $e');
      }
    }
  }

  Future<void> copyAssetsToTempDir() async {
    final Directory tempDir = await getTemporaryDirectory();
    final List<String> assetPaths = [
      'assets/web/enc.key',
      'assets/web/jsplayer.js',
      'assets/web/player - Copy.html',
      'assets/web/player.html',
      'assets/web/playerjs.js',
    ];

    for (String assetPath in assetPaths) {
      final ByteData data = await rootBundle.load(assetPath);
      final List<int> bytes = data.buffer.asUint8List();
      final String tempFilePath = '${tempDir.path}/${assetPath.split('/').last}';
      final File tempFile = File(tempFilePath);
      await tempFile.writeAsBytes(bytes, flush: true);
      print('Copied $assetPath to $tempFilePath');
    }
  }

  void checkServerStatusAndLoadWebView() async {
    bool serverReady = await isServerRunning();
    if (serverReady) {
      print('Server is ready, loading WebView...');
      _controller.loadRequest(Uri.parse('http://localhost:8889/player.html'));
    } else {
      print('Server is not ready yet, retrying in 2 seconds...');
      Future.delayed(Duration(seconds: 2), checkServerStatusAndLoadWebView);
    }
  }

  Future<bool> isServerRunning() async {
    try {
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(Uri.parse('http://localhost:8889/player.html')).timeout(Duration(seconds: 5));
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
}

void startServer() async {
  var handler = const shelf.Pipeline()
      .addMiddleware(shelf.logRequests())
      .addHandler(_handleRequest);

  var server = await io.serve(handler, '0.0.0.0', 8889);
  print('Server is running at http://${server.address.host}:${server.port}');
}

Future<shelf.Response> _handleRequest(shelf.Request request) async {
  final String assetPath = Uri.decodeComponent(request.url.path);
  final Directory tempDir = await getTemporaryDirectory();
  final String filePath = '${tempDir.path}/$assetPath';

  if (await _fileExists(filePath)) {
    final byteData = await _loadFile(filePath);
    final mimeType = _getMimeType(filePath);
    return shelf.Response.ok(
      byteData.buffer.asUint8List(),
      headers: {'Content-Type': mimeType},
    );
  } else {
    return shelf.Response.notFound('Asset not found');
  }
}

Future<bool> _fileExists(String filePath) async {
  try {
    final file = File(filePath);
    return await file.exists();
  } catch (e) {
    print('Error checking file existence: $e');
    return false;
  }
}

Future<ByteData> _loadFile(String filePath) async {
  try {
    final file = File(filePath);
    final Uint8List fileBytes = await file.readAsBytes();
    return ByteData.view(fileBytes.buffer);
  } catch (e) {
    print('Error loading file: $e');
    throw Exception('File loading error');
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
  }[extension] ?? 'application/octet-stream';

  print('Determined MIME type for $filePath: $mimeType');
  return mimeType;
}