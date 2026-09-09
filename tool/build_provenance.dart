import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

const _dependencyPaths = <String>[
  'core/go.mod',
  'core/go.sum',
  'core/Clash.Meta/go.mod',
  'core/Clash.Meta/go.sum',
  'pubspec.lock',
  'tool/singlink/sdk.json',
  'tool/singlink/outbound.go.in',
];

class BuildProvenance {
  BuildProvenance._();

  static String sidecarPath(String artifactPath) => '$artifactPath.build.json';

  static Future<void> removeSidecar(String artifactPath) async {
    final sidecar = File(sidecarPath(artifactPath));
    if (await sidecar.exists()) {
      await sidecar.delete();
    }
  }

  static Future<Map<String, Object?>> observe(String repositoryRoot) async {
    return <String, Object?>{
      'git': await _observeGit(repositoryRoot),
      'dependencyFiles': await _hashDependencies(repositoryRoot),
      'clientVersion': await _readPubspecVersion(repositoryRoot),
    };
  }

  static Future<void> write({
    required String repositoryRoot,
    required String artifactPath,
    required String targetPlatform,
    required String architecture,
    required String mode,
    required bool dev,
    required bool compatible,
    required List<String> tags,
    required Map<String, Object?> startObservation,
    Map<String, Object?>? integration,
  }) async {
    final sidecar = File(sidecarPath(artifactPath));
    final temporary = File('${sidecar.path}.tmp');
    try {
      final artifact = File(artifactPath);
      final endObservation = await observe(repositoryRoot);
      final artifactDigest = await sha256.bind(artifact.openRead()).first;
      final manifest = <String, Object?>{
        'schemaVersion': 1,
        'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
        'stage': 'core-before-signing',
        'artifact': <String, Object?>{
          'name': p.basename(artifactPath),
          'bytes': await artifact.length(),
          'sha256': artifactDigest.toString(),
        },
        'build': <String, Object?>{
          'targetPlatform': targetPlatform,
          'architecture': architecture,
          'mode': mode,
          'dev': dev,
          'compatible': compatible,
          'tags': tags,
        },
        'source': <String, Object?>{
          'repositoryPath': '.',
          'vendoredCorePath': 'core/Clash.Meta',
          'wrapperModule': await _readModuleName(
            p.join(repositoryRoot, 'core', 'go.mod'),
          ),
          'coreModule': await _readModuleName(
            p.join(repositoryRoot, 'core', 'Clash.Meta', 'go.mod'),
          ),
          'upstreamRelease': null,
          'observations': <String, Object?>{
            'start': startObservation,
            'end': endObservation,
            'changedDuringBuild':
                jsonEncode(startObservation) != jsonEncode(endObservation),
          },
        },
      };

      if (integration != null) {
        manifest['integration'] = integration;
      }

      await temporary.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
        flush: true,
      );
      await temporary.rename(sidecar.path);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      if (await sidecar.exists()) await sidecar.delete();
      rethrow;
    }
  }

  static Future<Map<String, Object?>> _observeGit(String root) async {
    final topLevel = await _runGit(root, ['rev-parse', '--show-toplevel']);
    final resolvedRoot = await Directory(root).resolveSymbolicLinks();
    if (topLevel == null ||
        p.canonicalize(topLevel) != p.canonicalize(resolvedRoot)) {
      return <String, Object?>{
        'status': 'unavailable',
        'head': null,
        'headTree': null,
        'vendoredCoreTree': null,
        'dirty': null,
      };
    }

    final statusOutput = await _runGit(root, [
      'status',
      '--porcelain=v1',
      '--untracked-files=normal',
    ]);
    final head = await _runGit(root, ['rev-parse', '--verify', 'HEAD']);
    final headTree = await _runGit(root, [
      'rev-parse',
      '--verify',
      'HEAD^{tree}',
    ]);
    final vendoredCoreTree = await _runGit(root, [
      'rev-parse',
      '--verify',
      'HEAD:core/Clash.Meta',
    ]);
    final available =
        statusOutput != null &&
        head != null &&
        headTree != null &&
        vendoredCoreTree != null;
    return <String, Object?>{
      'status': available ? 'available' : 'unavailable',
      'head': head,
      'headTree': headTree,
      'vendoredCoreTree': vendoredCoreTree,
      'dirty': statusOutput?.isNotEmpty,
    };
  }

  static Future<String?> _runGit(String root, List<String> arguments) async {
    try {
      final result = await Process.run(
        'git',
        ['-C', root, ...arguments],
        environment: {'GIT_NO_REPLACE_OBJECTS': '1'},
        runInShell: false,
      );
      if (result.exitCode != 0) return null;
      return result.stdout.toString().trim();
    } on ProcessException {
      return null;
    }
  }

  static Future<Map<String, Object?>> _hashDependencies(String root) async {
    final hashes = <String, Object?>{};
    for (final relativePath in _dependencyPaths) {
      final file = File(p.join(root, relativePath));
      hashes[relativePath] = await file.exists()
          ? (await sha256.bind(file.openRead()).first).toString()
          : null;
    }
    return hashes;
  }

  static Future<String?> _readPubspecVersion(String root) async {
    try {
      final yaml = loadYaml(
        await File(p.join(root, 'pubspec.yaml')).readAsString(),
      );
      if (yaml is! YamlMap) return null;
      return yaml['version']?.toString();
    } on FileSystemException {
      return null;
    } on YamlException {
      return null;
    }
  }

  static Future<String?> _readModuleName(String goModPath) async {
    try {
      for (final line in await File(goModPath).readAsLines()) {
        final match = RegExp(r'^\s*module\s+(\S+)').firstMatch(line);
        if (match != null) return match.group(1);
      }
    } on FileSystemException {
      return null;
    }
    return null;
  }
}
