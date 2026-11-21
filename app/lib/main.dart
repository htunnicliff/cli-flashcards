import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'schema/manifest.dart';

void main() {
  runApp(const CliFlashcardsApp());
}

/// Placeholder shell until the screens land: lists the bundled decks.
class CliFlashcardsApp extends StatelessWidget {
  const CliFlashcardsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CLI Flashcards',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF3B82F6)),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF3B82F6),
        brightness: Brightness.dark,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('CLI Flashcards')),
        body: FutureBuilder(
          future: rootBundle
              .loadString('assets/decks/index.json')
              .then(
                (text) => DeckManifest.fromJson(
                  jsonDecode(text) as Map<String, dynamic>,
                ),
              ),
          builder: (context, snapshot) {
            final manifest = snapshot.data;
            if (manifest == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              children: [
                for (final deck in manifest.decks)
                  ListTile(
                    title: Text('${deck.tool} (${deck.variant})'),
                    subtitle: Text('${deck.optionCount} options'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
