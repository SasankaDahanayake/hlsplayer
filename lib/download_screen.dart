import 'package:flutter/material.dart';

class DownloadScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Downloading...')),
      body: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}