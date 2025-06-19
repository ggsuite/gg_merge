// @license
// Copyright (c) 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:gg_args/gg_args.dart';
import 'package:gg_log/gg_log.dart';
import 'package:yaml/yaml.dart';
import 'package:gg_status_printer/gg_status_printer.dart';

/// Checks whether the project has local (path:) references in pubspec.yaml.
class HasLocalReferences extends DirCommand<bool> {
  /// Creates a [HasLocalReferences] command
  HasLocalReferences({
    required super.ggLog,
    super.name = 'has-local-references',
    super.description = 'Checks whether pubspec.yaml '
        'contains path: references for dependencies.',
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

  /// Returns true if pubspec.yaml contains at least one path: reference.
  @override
  Future<bool> get({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    final pubspecFile = File('${directory.path}/pubspec.yaml');
    if (!pubspecFile.existsSync()) {
      throw ArgumentError('pubspec.yaml not found');
    }
    final pubspecContent = await pubspecFile.readAsString();
    final pubspecYaml = loadYaml(pubspecContent) as YamlMap;
    final deps =
        (pubspecYaml['dependencies'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
    final devDeps =
        (pubspecYaml['dev_dependencies'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
    final checks = <String, dynamic>{
      ...deps,
      ...devDeps,
    };
    for (final value in checks.values) {
      if (value is Map && value['path'] != null) {
        return true;
      }
    }
    return false;
  }
}

/// Mock for unit testing
class MockHasLocalReferences extends MockDirCommand<bool>
    implements HasLocalReferences {}
