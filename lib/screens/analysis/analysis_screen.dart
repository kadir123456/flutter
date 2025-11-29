import 'package:flutter/material.dart';

class AnalysisScreen extends StatelessWidget {
  final String bulletinId;
  
  const AnalysisScreen({super.key, required this.bulletinId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analiz Sonuçları')),
      body: Center(child: Text('Analysis Screen - Bülten ID: $bulletinId')),
    );
  }
}
