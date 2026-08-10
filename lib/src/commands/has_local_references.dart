// @license
// Copyright (c) 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:yaml/yaml.dart';

/// Checks whether the project has local (path) references in its manifests.
///
/// For Dart/Flutter (`pubspec.yaml`) this checks for `path:` keys in
/// dependency maps. For TypeScript (`package.json`) it checks for npm-style
/// local protocols (`file:`, `link:`, `workspace:`) and bare relative paths
/// in the various dependency sections.
///
/// A *hybrid* carries both manifests and is checked on **both** sides. It used
/// to be checked as Dart only — `detectProjectType` gives `pubspec.yaml`
/// precedence — so a `link:` in its `package.json` passed `can merge` and would
/// have been published, unresolvable for everybody else.
class HasLocalReferences extends DirCommand<bool> {
  /// Creates a [HasLocalReferences] command
  HasLocalReferences({
    required super.ggLog,
    super.name = 'has-local-references',
    super.description = 'Check the manifest for local path references',
  });

  @override
  Future<bool> exec({
    required Directory directory,
    required GgLog ggLog,
    Map<String, dynamic> options = const {},
  }) async {
    return await GgStatusPrinter<bool>(
      message: 'Checking for local path references.',
      ggLog: ggLog,
      dark: true,
    ).logTask(
      task: () => get(directory: directory, ggLog: ggLog),
      success: (b) => b,
    );
  }

  /// Returns true if a manifest contains at least one local path reference.
  @override
  Future<bool> get({required Directory directory, required GgLog ggLog}) async {
    // Every manifest the directory carries is checked, so a hybrid cannot hide
    // a localized npm dependency behind its pubspec. A directory without any
    // manifest has no dependency references at all.
    if (File('${directory.path}/pubspec.yaml').existsSync() &&
        await _checkPubspec(directory)) {
      return true;
    }
    if (File('${directory.path}/package.json').existsSync() &&
        await _checkPackageJson(directory)) {
      return true;
    }
    return false;
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
