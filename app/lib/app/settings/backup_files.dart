/// Saving and opening backup files on each platform.
library;

import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

const _jsonTypes = XTypeGroup(
  label: 'Backup',
  extensions: ['json'],
  mimeTypes: ['application/json'],
  uniformTypeIdentifiers: ['public.json'],
  webWildCards: ['application/json', '.json'],
);

/// Saves [text] as [name]: a save dialog on macOS, a download on the web
/// (where sharing files isn't supported), the share sheet on phones.
/// Returns false if the person cancelled.
Future<bool> saveBackupFile(String name, String text, {Rect? origin}) async {
  final bytes = Uint8List.fromList(utf8.encode(text));
  final file = XFile.fromData(bytes, mimeType: 'application/json', name: name);
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const [_jsonTypes],
    );
    if (location == null) return false;
    await file.saveTo(location.path);
    return true;
  }
  final result = await SharePlus.instance.share(
    ShareParams(
      files: [file],
      fileNameOverrides: [name],
      sharePositionOrigin: origin,
      downloadFallbackEnabled: true,
    ),
  );
  return result.status != ShareResultStatus.dismissed;
}

/// Asks for a backup file and reads it, or returns null if cancelled.
Future<({String name, String text})?> openBackupFile() async {
  final file = await openFile(acceptedTypeGroups: const [_jsonTypes]);
  if (file == null) return null;
  return (name: file.name, text: utf8.decode(await file.readAsBytes()));
}
