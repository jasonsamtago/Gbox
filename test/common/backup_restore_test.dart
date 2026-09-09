import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:bett_box/common/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('gbox-restore-');
  });
  tearDown(() async {
    await home.delete(recursive: true);
  });

  Archive roundTrip(List<ArchiveFile> entries) {
    final archive = Archive();
    for (final entry in entries) {
      archive.addFile(entry);
    }
    return ZipDecoder().decodeBytes(ZipEncoder().encode(archive));
  }

  test(
    'upstream #450: repacked backup may contain directory entries',
    () async {
      await Directory(p.join(home.path, 'profiles')).create();
      final archive = roundTrip([
        ArchiveFile.directory('profiles/'),
        ArchiveFile.string('profiles/1.yaml', 'proxies: []\n'),
        ArchiveFile.directory('providers/'),
        ArchiveFile.directory('providers/1/'),
        ArchiveFile.string('providers/1/rules.yaml', 'payload: []\n'),
      ]);

      await restoreBackupFiles(archive.files, home.path);

      expect(
        await File(p.join(home.path, 'profiles/1.yaml')).readAsString(),
        'proxies: []\n',
      );
      expect(
        await File(p.join(home.path, 'providers/1/rules.yaml')).readAsString(),
        'payload: []\n',
      );
      expect(await Directory(p.join(home.path, 'profiles')).exists(), isTrue);
    },
  );

  test('file-only backups still restore and replace profile content', () async {
    final path = p.join(home.path, 'profiles/1.yaml');
    await File(path).create(recursive: true);
    await File(path).writeAsString('old');
    final archive = roundTrip([ArchiveFile.string('profiles/1.yaml', 'new')]);
    await restoreBackupFiles(archive.files, home.path);
    expect(await File(path).readAsBytes(), utf8.encode('new'));
  });

  test('directory entries without a trailing slash are not files', () async {
    final directory = ArchiveFile.directory('profiles');
    expect(directory.name, 'profiles');
    expect(directory.isFile, isFalse);
    await restoreBackupFiles([
      directory,
      ArchiveFile.string('profiles/1.yaml', 'restored'),
    ], home.path);
    expect(
      await File(p.join(home.path, 'profiles/1.yaml')).readAsString(),
      'restored',
    );
  });
}
