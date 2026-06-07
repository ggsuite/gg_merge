// @license
// Copyright (c) 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';
import 'package:gg_args/gg_args.dart';
import 'package:gg_lang/gg_lang.dart';
import 'package:gg_log/gg_log.dart';
import 'package:yaml/yaml.dart';
import 'package:gg_status_printer/gg_status_printer.dart';

/// Checks whether the project has local (path) references in its manifest.
///
/// For Dart/Flutter (`pubspec.yaml`) this checks for `path:` keys in
/// dependency maps. For TypeScript (`package.json`) it checks for npm-style
/// local protocols (`file:`, `link:`, `workspace:`) and bare relative paths
/// in the various dependency sections.
class HasLocalReferences extends DirCommand<bool> {
  /// Creates a [HasLocalReferences] command
  HasLocalReferences({
    required super.ggLog,
    super.name = 'has-local-references',
    super.description =
        'Checks whether the package manifest contains local path '
        'references for dependencies.',
  });

  @override
  Future<bool> exec({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    return await GgStatusPrinter<bool>(
      message: 'Checking for local path references.',
      ggLog: ggLog,
    ).logTask(
      task: () => get(directory: directory, ggLog: ggLog),
      success: (b) => b,
    );
  }

  /// Returns true if the manifest contains at least one local path reference.
  @override
  Future<bool> get({required Directory directory, required GgLog ggLog}) async {
    final ProjectType type;
    try {
      type = detectProjectType(directory);
    } catch (_) {
      throw ArgumentError(
        'No package manifest found in "${directory.path}". '
        'Expected pubspec.yaml (Dart/Flutter) or '
        'package.json + tsconfig.json (TypeScript).',
      );
    }

    switch (type) {
      case ProjectType.dart:
      case ProjectType.flutter:
        return _checkPubspec(directory);
      case ProjectType.typescript:
        return _checkPackageJson(directory);
    }
  }

  // ...........................................................................
  Future<bool> _checkPubspec(Directory directory) async {
    final pubspecFile = File('${directory.path}/pubspec.yaml');
    final pubspecContent = await pubspecFile.readAsString();
    final pubspecYaml = loadYaml(pubspecContent) as YamlMap;
    final deps =
        (pubspecYaml['dependencies'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final devDeps =
        (pubspecYaml['dev_dependencies'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final checks = <String, dynamic>{...deps, ...devDeps};
    for (final value in checks.values) {
      if (value is Map && value['path'] != null) {
        return true;
      }
    }
    return false;
  }

  // ...........................................................................
  Future<bool> _checkPackageJson(Directory directory) async {
    final pkg = File('${directory.path}/package.json');
    final decoded = jsonDecode(await pkg.readAsString());
    if (decoded is! Map<String, dynamic>) {
      return false;
    }
    const sections = <String>[
      'dependencies',
      'devDependencies',
      'peerDependencies',
      'optionalDependencies',
    ];
    for (final section in sections) {
      final entries = decoded[section];
      if (entries is! Map) continue;
      for (final value in entries.values) {
        if (value is String && _isLocalNpmRef(value)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Recognises npm-style local references in `package.json` dependency
  /// values: `file:`, `link:` and `workspace:` protocols as well as bare
  /// relative or absolute filesystem paths (including `C:\…` on Windows).
  static bool _isLocalNpmRef(String value) {
    final v = value.trim();
    if (v.startsWith('file:')) return true;
    if (v.startsWith('link:')) return true;
    if (v.startsWith('workspace:')) return true;
    if (v.startsWith('./') || v.startsWith('../')) return true;
    if (v.startsWith('/')) return true;
    // Windows drive-letter path like `C:\foo` or `C:/foo`.
    if (v.length >= 3 && RegExp(r'^[A-Za-z]:[\\/]').matchAsPrefix(v) != null) {
      return true;
    }
    return false;
  }
}

/// Mock for unit testing
class MockHasLocalReferences extends MockDirCommand<bool>
    implements HasLocalReferences {}
