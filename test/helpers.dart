// @license
// Copyright (c) 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:mocktail/mocktail.dart';
import 'package:gg_process/gg_process.dart';
import 'dart:io';

class MockGgProcessWrapper extends Mock implements GgProcessWrapper {}

/// Helper to capture ggLog output
void capturePrint({
  required void Function(String) ggLog,
  required Future<void> Function() code,
}) async {
  final messages = <String>[];
  ggLog = messages.add;
  await code();
}

/// Fake Directory fallback for mocktail
class _FakeDirectory extends Fake implements Directory {}

/// Fake GgLog fallback
class _FakeGgLog extends Fake {
  void call(String _) {}
}

void registerTestFallbacks() {
  registerFallbackValue(_FakeDirectory());
  registerFallbackValue(<String>[]);
  registerFallbackValue(_FakeGgLog());
}
