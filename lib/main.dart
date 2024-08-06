import 'package:flutter/material.dart';

import 'download_screen.dart';
import 'home.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Ensure binding is initialized
  // await FlutterDownloader.initialize(
  //   debug: true,
  //   ignoreSsl: true,  // Add this if you are working with non-HTTPS URLs
  // );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const HomeScreen(),
      routes: {
        '/download': (context) => DownloadScreen(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
