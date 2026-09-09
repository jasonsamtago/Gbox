import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart';

extension ArchiveExt on Archive {
  Future<void> addDirectoryToArchive(String dirPath, String parentPath) async {
    final dir = Directory(dirPath);
    final entities = await dir.list(recursive: false).toList();
    for (final entity in entities) {
      final relativePath = relative(
        entity.path,
        from: parentPath,
      ).replaceAll('\\', '/');
      if (entity is File) {
        final data = await entity.readAsBytes();
        final archiveFile = ArchiveFile(relativePath, data.length, data);
        addFile(archiveFile);
      } else if (entity is Directory) {
        await addDirectoryToArchive(entity.path, parentPath);
      }
    }
  }

  void add<T>(String name, T raw) {
    final data = json.encode(raw);
    addFile(ArchiveFile(name, data.length, utf8.encode(data)));
  }
}

/// Writes the profile entries shared by native and legacy backup recovery.
Future<void> restoreBackupFiles(
  Iterable<ArchiveFile> profiles,
  String homeDirPath,
) async {
  for (final profile in profiles) {
    if (!profile.isFile) continue;
    final filePath = join(homeDirPath, profile.name);
    final file = File(filePath);
    await file.create(recursive: true);
    await file.writeAsBytes(profile.content);
  }
}
