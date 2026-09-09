import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'build_provenance.dart';

const _module = 'github.com/jasonsamtago/singlink-go';
const _repository = 'https://github.com/jasonsamtago/singlink-go';
const _tags = ['with_gvisor', 'singlink'];

class _BuildFailure implements Exception {
  const _BuildFailure(this.message);
  final String message;
}

Future<ProcessResult> _run(
  String executable,
  List<String> arguments, {
  required String cwd,
  Map<String, String>? environment,
}) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: cwd,
    environment: {
      ...?environment,
      if (executable == 'git') 'GIT_NO_REPLACE_OBJECTS': '1',
    },
    runInShell: false,
  );
  if (result.exitCode != 0) {
    // Never echo arguments/environment or arbitrary remote/credential text.
    throw _BuildFailure(
      '$executable compiler/source step failed (${result.exitCode})',
    );
  }
  return result;
}

bool _inside(String root, String path) =>
    p.equals(root, path) || p.isWithin(root, path);

Future<String> _futurePath(String path) async {
  var current = p.normalize(p.absolute(path));
  final tail = <String>[];
  while (await FileSystemEntity.type(current, followLinks: false) ==
      FileSystemEntityType.notFound) {
    tail.insert(0, p.basename(current));
    final parent = p.dirname(current);
    if (parent == current) {
      throw const _BuildFailure('Cannot resolve output parent');
    }
    current = parent;
  }
  final resolved = await Directory(current).resolveSymbolicLinks();
  return p.joinAll([resolved, ...tail]);
}

Future<void> _absent(String path) async {
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw const _BuildFailure(
      'Output or provenance already exists; choose a new path',
    );
  }
}

Map<String, String> _offline({String work = 'off'}) => {
  'GOPROXY': 'off',
  'GOSUMDB': 'off',
  'GONOPROXY': 'none',
  'GOVCS': '*:off',
  'GOTOOLCHAIN': 'local',
  'GOWORK': work,
  'GOENV': 'off',
  'GOFLAGS': '',
  'CGO_ENABLED': '0',
};

Future<void> main(List<String> args) async {
  try {
    await _build(args);
  } on _BuildFailure catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  } catch (_) {
    // Filesystem/process exceptions can contain source paths or environment.
    stderr.writeln('SingLink offline compiler operation failed');
    exitCode = 1;
  }
}

Future<void> _build(List<String> args) async {
  final options = <String, String>{};
  var vet = false;
  for (var i = 0; i < args.length; i++) {
    final key = args[i];
    if (key == '--vet' && !vet) {
      vet = true;
      continue;
    }
    if (!['--sdk', '--out', '--target', '--arch'].contains(key) ||
        options.containsKey(key) ||
        i + 1 == args.length ||
        args[i + 1].startsWith('--')) {
      throw const _BuildFailure(
        'Usage: dart tool/build_singlink.dart --sdk checkout --out external-artifact [--target darwin|linux|windows] [--arch arm64|amd64] [--vet]',
      );
    }
    options[key] = args[++i];
  }
  if (options['--sdk'] == null || options['--out'] == null) {
    throw const _BuildFailure('--sdk and --out are required');
  }
  // This entry is invoked from its source location; cwd never chooses the repo.
  final script = await File.fromUri(Platform.script).resolveSymbolicLinks();
  final root = await Directory(
    p.dirname(p.dirname(script)),
  ).resolveSymbolicLinks();
  if (!await File(p.join(root, 'tool', 'singlink', 'sdk.json')).exists() ||
      !await File(p.join(root, 'core', 'go.mod')).exists()) {
    throw const _BuildFailure(
      'Run the compiler entry from its repository source location',
    );
  }
  final sdk = await Directory(options['--sdk']!).resolveSymbolicLinks();
  final requestedOut = p.normalize(p.absolute(options['--out']!));
  await _absent(requestedOut);
  final out = await _futurePath(requestedOut);
  if (_inside(root, out) || _inside(sdk, out)) {
    throw const _BuildFailure('Output must be outside Gbox and SDK source');
  }
  final sidecar = BuildProvenance.sidecarPath(out);
  final temporarySidecar = '$sidecar.tmp';
  await _absent(out);
  await _absent(sidecar);
  await _absent(temporarySidecar);

  final pin = jsonDecode(
    await File(p.join(root, 'tool', 'singlink', 'sdk.json')).readAsString(),
  );
  if (pin is! Map<String, dynamic> ||
      pin['schemaVersion'] != 1 ||
      pin['module'] != _module ||
      pin['repository'] != _repository ||
      pin['revision'] is! String ||
      !RegExp(r'^[0-9a-f]{40}$').hasMatch(pin['revision'] as String)) {
    throw const _BuildFailure('Invalid SDK pin manifest');
  }
  final revision = pin['revision'] as String;
  final commit = (await _run('git', [
    'rev-parse',
    '--verify',
    '$revision^{commit}',
  ], cwd: sdk)).stdout.toString().trim();
  final tree = (await _run('git', [
    'rev-parse',
    '--verify',
    '$revision^{tree}',
  ], cwd: sdk)).stdout.toString().trim();
  if (commit != revision || !RegExp(r'^[0-9a-f]{40}$').hasMatch(tree)) {
    throw const _BuildFailure(
      'SDK pin does not resolve to the exact commit/tree',
    );
  }
  final host =
      jsonDecode(
            (await _run(
              'go',
              ['env', '-json', 'GOHOSTOS', 'GOHOSTARCH', 'GOVERSION'],
              cwd: p.join(root, 'core'),
              environment: _offline(),
            )).stdout.toString(),
          )
          as Map<String, dynamic>;
  final target = options['--target'] ?? host['GOHOSTOS'] as String;
  final arch = options['--arch'] ?? host['GOHOSTARCH'] as String;
  if (!['darwin', 'linux', 'windows'].contains(target) ||
      !['arm64', 'amd64'].contains(arch)) {
    throw const _BuildFailure('Unsupported executable target or architecture');
  }
  final version = RegExp(
    r'^go(\d+)\.(\d+)(?:\.(\d+))?$',
  ).firstMatch(host['GOVERSION'] as String);
  if (version == null ||
      int.parse(version[1]!) < 1 ||
      (int.parse(version[1]!) == 1 && int.parse(version[2]!) < 20)) {
    throw const _BuildFailure('A local Go toolchain at least 1.20 is required');
  }
  final goVersion = '${version[1]}.${version[2]}';
  final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
  if (_inside(root, tempRoot) || _inside(sdk, tempRoot)) {
    throw const _BuildFailure(
      'Temporary directory must be outside source repositories',
    );
  }
  final scratch = await Directory(tempRoot).createTemp('gbox-singlink-');
  var ownArtifact = false;
  var ownSidecar = false;
  var ownTemporarySidecar = false;
  var success = false;
  try {
    final archive = p.join(scratch.path, 'sdk.tar');
    await _run('git', [
      'archive',
      '--format=tar',
      '--output=$archive',
      revision,
    ], cwd: sdk);
    final archiveHash = (await sha256.bind(File(archive).openRead()).first)
        .toString();
    final extracted = await Directory(p.join(scratch.path, 'sdk')).create();
    await _run('tar', [
      '-xf',
      archive,
      '-C',
      extracted.path,
    ], cwd: scratch.path);
    final module = RegExp(r'^\s*module\s+(\S+)', multiLine: true)
        .firstMatch(await File(p.join(extracted.path, 'go.mod')).readAsString())
        ?.group(1);
    if (module != _module) {
      throw const _BuildFailure('Archived SDK module mismatch');
    }
    for (final package in ['session', 'tcpclient', 'mux', 'target']) {
      if (!await Directory(p.join(extracted.path, package)).exists()) {
        throw const _BuildFailure('Archived SDK is missing required packages');
      }
    }
    final work = p.join(scratch.path, 'go.work');
    final modules = [p.join(root, 'core'), extracted.path];
    await File(work).writeAsString(
      'go $goVersion\n\nuse (\n${modules.map((path) => '  ${jsonEncode(path)}').join('\n')}\n)\n',
    );
    final template = p.join(root, 'tool', 'singlink', 'outbound.go.in');
    final templateHash = (await sha256.bind(File(template).openRead()).first)
        .toString();
    final overlay = p.join(scratch.path, 'overlay.json');
    await File(overlay).writeAsString(
      jsonEncode({
        'Replace': {
          p.join(
            root,
            'core',
            'Clash.Meta',
            'adapter',
            'outbound',
            'singlink_disabled.go',
          ): template,
        },
      }),
    );
    final environment = {
      ..._offline(work: work),
      'GOOS': target,
      'GOARCH': arch,
    };
    final start = await BuildProvenance.observe(root);
    await Directory(p.dirname(out)).create(recursive: true);
    // Exclusively reserve all files this invocation may later clean up.
    await File(out).create(exclusive: true);
    ownArtifact = true;
    await File(sidecar).create(exclusive: true);
    ownSidecar = true;
    await File(temporarySidecar).create(exclusive: true);
    ownTemporarySidecar = true;
    await _run(
      'go',
      [
        'build',
        '-trimpath',
        '-overlay=$overlay',
        '-tags=${_tags.join(',')}',
        '-o',
        out,
        '.',
      ],
      cwd: p.join(root, 'core'),
      environment: environment,
    );
    if (vet) {
      await _run(
        'go',
        [
          'vet',
          '-overlay=$overlay',
          '-tags=${_tags.join(',')}',
          'github.com/metacubex/mihomo/adapter',
        ],
        cwd: p.join(root, 'core'),
        environment: environment,
      );
    }
    await BuildProvenance.write(
      repositoryRoot: root,
      artifactPath: out,
      targetPlatform: target,
      architecture: arch,
      mode: 'executable',
      dev: true,
      compatible: false,
      tags: _tags,
      startObservation: start,
      integration: {
        'kind': 'singlink',
        'transport': 'direct-tls',
        'module': _module,
        'revision': revision,
        'tree': tree,
        'archiveSha256': archiveHash,
        'overlayTemplateSha256': templateHash,
        'sourceExtraction': 'git-archive',
      },
    );
    await scratch.delete(recursive: true);
    success = true;
    stdout.writeln(
      'SingLink offline executable compilation and provenance complete. Binary was not run.',
    );
  } finally {
    if (!success) {
      if (ownArtifact && await File(out).exists()) await File(out).delete();
      if (ownSidecar && await File(sidecar).exists()) {
        await File(sidecar).delete();
      }
      if (ownTemporarySidecar && await File(temporarySidecar).exists()) {
        await File(temporarySidecar).delete();
      }
    }
    if (await scratch.exists()) await scratch.delete(recursive: true);
  }
}
