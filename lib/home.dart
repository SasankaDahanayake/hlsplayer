import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:hls_player/player_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uni_links/uni_links.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  bool isDownloading = false;
  final ReceivePort _port = ReceivePort();
  List<String> folders = [];

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

    FlutterDownloader.registerCallback(downloadCallback);
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
        final videoName = remainingUrl.substring(0, separatorIndex);
        final fullUrl = remainingUrl.substring(separatorIndex + 1);

        // Extract the path part after the domain
        final uri = Uri.parse(fullUrl);
        final path = uri.path;

        print('Video Name: $videoName');
        print('Path for Playlist File: $path');
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
    const baseUrl = 'http://140.245.49.98/video-files/1/';
    final files = [
      'playlist.m3u8',
      'segment0.ts',
      'segment1.ts',
      'segment2.ts',
      'segment3.ts',
    ];

    setState(() {
      isDownloading = true;
    });

    final videoDir = Directory('${tempDir.path}/video-files/Video-1');
    if (!await videoDir.exists()) {
      await videoDir.create(recursive: true);
    }

    // Download the files
    for (final file in files) {
      await FlutterDownloader.enqueue(
        url: '$baseUrl$file',
        savedDir: videoDir.path,
        fileName: file,
        showNotification: true,
        openFileFromNotification: true,
      );
    }

    setState(() {
      isDownloading = false;
    });

    _loadFolders();

  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Stack(
        children: [
          ListView.builder(
            itemCount: folders.length,
            itemBuilder: (context, index) {
              final folderName = folders[index].split('/').last;
              return ListTile(
                title: Text(folderName),
                onTap: () => _navigateToPlayerScreen(folders[index]),
              );
            },
          ),
          if (isDownloading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _startDownload,
        child: const Icon(Icons.download),
      ),
    );
  }

  void _navigateToPlayerScreen(String folderPath) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PlayerScreen(),
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