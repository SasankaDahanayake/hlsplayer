import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hls_player/player_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uni_links/uni_links.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart';



class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  bool isDownloading = false;
  final ReceivePort _port = ReceivePort();
  List<String> folders = [];
  String videoName = '';
  String downloadedFile = '';
  String basePath = '';
  List<String> filesBeingDownloaded = [];

  @override
  void initState() {
    super.initState();
    _initDeepLinkListener();
    IsolateNameServer.registerPortWithName(
      _port.sendPort,
      'downloader_send_port',
    );
    _port.listen((dynamic data) {
      setState(() {
        isDownloading = data[1] != 100;
      });
    });

    // FlutterDownloader.registerCallback(downloadCallback);
    _loadFolders();

  }

  @override
  void dispose() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    super.dispose();
  }

  Future<void> _loadFolders() async {
    final tempDir = await getTemporaryDirectory();
    final videoDir = Directory('${tempDir.path}/video-files');
    if (await videoDir.exists()) {
      final folderList = videoDir.listSync().whereType<Directory>().map((dir) => dir.path).toList();
      setState(() {
        folders = folderList;
      });
    }
  }


  _initDeepLinkListener() async {
    linkStream.listen((String? link) {
      print('this is the link $link');
      _processLink(link!);
    }, onError: (err) {
      print(err);
    });

  }

  void _processLink(String url) {
    const prefix = 'eclass-poc://';
    if (url.startsWith(prefix)) {
      final remainingUrl = url.substring(prefix.length);
      final separatorIndex = remainingUrl.indexOf(';');

      if (separatorIndex != -1) {
        videoName = remainingUrl.substring(0, separatorIndex);
        final fullUrl = remainingUrl.substring(separatorIndex + 1);

        final uri = Uri.parse(fullUrl);
        final pathSegments = uri.pathSegments;

        if (pathSegments.isNotEmpty) {
          final basePathSegments = pathSegments.sublist(0, pathSegments.length - 1);
          basePath = Uri(
            scheme: uri.scheme,
            host: uri.host,
            port: uri.hasPort ? uri.port : null,
            pathSegments: basePathSegments,
          ).toString();

          print('Video Name: $videoName');
          print('Base URL: $basePath');

          _startDownload();

        } else {
          print('Invalid path in the URL');
        }
      } else {
        print('Separator not found in the URL');
      }
    } else {
      print('URL does not start with the expected prefix');
    }
  }

  static void downloadCallback(
      String id, int status, int progress) {
    final SendPort? send =
    IsolateNameServer.lookupPortByName('downloader_send_port');
    send?.send([id, status, progress]);
  }

  Future<void> _startDownload() async {
    await requestPermissions();
    final tempDir = await getTemporaryDirectory();

    setState(() {
      isDownloading = true;
    });

    final videoDir = Directory('${tempDir.path}/video-files/$videoName');
    if (!await videoDir.exists()) {
      await videoDir.create(recursive: true);
    }

    final files = await _fetchFiles(basePath);

    for (final file in files) {
      final filePath = '${videoDir.path}/$file';
      if (!File(filePath).existsSync()) {
        filesBeingDownloaded.add(file);
        await _downloadFile('$basePath/$file', filePath);
      }
    }

    setState(() {
      isDownloading = false;
      filesBeingDownloaded.clear();
    });
    _loadFolders();
  }

  Future<List<String>> _fetchFiles(String baseUrl) async {
    final response = await http.get(Uri.parse(baseUrl));

    if (response.statusCode == 200) {
      final document = parse(response.body);
      final fileLinks = document.querySelectorAll('a');
      final files = fileLinks.map((link) => link.attributes['href']).where((href) => href != null && href.endsWith('.m3u8') || href!.endsWith('.ts')).toList();
      print('these are the files ${files.cast<String>()}');
      return files.cast<String>();
    } else {
      throw Exception('Failed to load files from $baseUrl');
    }
  }


  Future<void> _downloadFile(String url, String filePath) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        setState(() {
          downloadedFile = 'Downloaded file: $url';
        });
        print('Downloaded file: $url to $filePath');
      } else {
        print('Failed to download file: $url. Status code: ${response.statusCode}');
      }
    } catch (e) {
      print('Error downloading file: $url. Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: folders.length,
                  itemBuilder: (context, index) {
                    final folderName = folders[index].split('/').last;
                    return ListTile(
                      title: Text(folderName),
                      onTap: () => _navigateToPlayerScreen(folderName),
                    );
                  },
                ),
              ),
              if (isDownloading)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Downloading: $videoName', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ...filesBeingDownloaded.map((file) => Text(file)).toList(),
                      // Text(downloadedFile),
                      const Center(child: CircularProgressIndicator()),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _navigateToPlayerScreen(String videoName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerScreen(videoName: videoName),
      ),
    );
  }
}

Future<void> requestPermissions() async {
  if (Platform.isAndroid) {
    await Permission.storage.request();
  } else if (Platform.isIOS) {
    await Permission.photos.request();
  }
}