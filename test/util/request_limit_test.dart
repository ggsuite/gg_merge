// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_merge/src/util/request_limit.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:test/test.dart';

void main() {
  const minute = Duration(minutes: 1);
  const hour = Duration(hours: 1);

  /// The time of the test. Waiting moves it on, nothing else does.
  late DateTime now;
  late List<Duration> waits;
  final messages = <String>[];
  void ggLog(String message) => messages.add(rmControls(message));

  RequestLimit limitOf(List<RequestWindow> limits) => RequestLimit(
    limits: limits,
    now: () => now,
    wait: (duration) async {
      waits.add(duration);
      now = now.add(duration);
    },
  );

  void pass(Duration duration) => now = now.add(duration);

  setUp(() {
    now = DateTime(2026, 11, 14, 12);
    waits = [];
    messages.clear();
  });

  group('RequestLimit', () {
    group('start', () {
      test('lets requests start right away while the limit allows '
          'them', () async {
        final limit = limitOf(const [(within: minute, requests: 3)]);

        for (var i = 0; i < 3; i++) {
          await limit.start(ggLog: ggLog);
        }

        expect(waits, isEmpty);
        expect(messages, isEmpty);
      });

      test('makes a request wait until an earlier one is old enough', () async {
        final limit = limitOf(const [(within: minute, requests: 3)]);

        // Three requests, ten seconds apart.
        await limit.start(ggLog: ggLog);
        pass(const Duration(seconds: 10));
        await limit.start(ggLog: ggLog);
        pass(const Duration(seconds: 10));
        await limit.start(ggLog: ggLog);
        pass(const Duration(seconds: 10));

        // The fourth has to wait until the first is a minute old.
        await limit.start(ggLog: ggLog, what: 'new pull requests');
        expect(waits, [const Duration(seconds: 30)]);
        expect(messages, [
          '3 new pull requests started within a minute, and a provider '
              'takes no more. Waiting 30s.',
        ]);

        // The fifth waits for the second, which started ten seconds later.
        await limit.start(ggLog: ggLog);
        expect(waits, [
          const Duration(seconds: 30),
          const Duration(seconds: 10),
        ]);
        expect(
          messages.last,
          '3 requests started within a minute, and a provider takes no '
          'more. Waiting 10s.',
        );
      });

      test('lets a request start again once a minute has passed', () async {
        final limit = limitOf(const [(within: minute, requests: 1)]);

        await limit.start(ggLog: ggLog);
        pass(minute);
        await limit.start(ggLog: ggLog);

        expect(waits, isEmpty);
      });

      test('keeps 700 requests within 80 a minute and 500 an hour', () async {
        final limit = limitOf(RequestLimit.gitHubContentLimits);
        final starts = <DateTime>[];

        for (var i = 0; i < 700; i++) {
          await limit.start(ggLog: ggLog);
          starts.add(now);
        }

        // As many as possible, as early as possible: 80 at once, the next
        // 80 a minute later, and the 501st once the first is an hour old.
        expect(starts[79], starts[0]);
        expect(starts[80].difference(starts[0]), minute);
        expect(starts[499].difference(starts[0]), const Duration(minutes: 6));
        expect(starts[500].difference(starts[0]), hour);

        // Never more than the limits, wherever the time is counted from.
        int startedWithin(Duration within, DateTime until) => starts
            .where(
              (start) =>
                  !start.isAfter(until) &&
                  start.isAfter(until.subtract(within)),
            )
            .length;

        for (final start in starts) {
          expect(startedWithin(minute, start), lessThanOrEqualTo(80));
          expect(startedWithin(hour, start), lessThanOrEqualTo(500));
        }

        // The request that waited for the hour says so.
        expect(
          messages,
          contains(
            '500 requests started within an hour, and a provider takes no '
            'more. Waiting 3240s.',
          ),
        );
      });

      test('serves the callers in the order they asked', () async {
        final limit = limitOf(const [(within: minute, requests: 1)]);
        final served = <int>[];

        await Future.wait([
          for (var i = 0; i < 3; i++)
            limit.start(ggLog: ggLog).then((_) => served.add(i)),
        ]);

        expect(served, [0, 1, 2]);
        expect(waits, [minute, minute]);
      });

      test('tells a caller only once that it waits', () async {
        // A timer that fires early: the caller has to wait a second time.
        var firesEarly = true;
        final limit = RequestLimit(
          limits: const [(within: minute, requests: 1)],
          now: () => now,
          wait: (duration) async {
            waits.add(duration);
            now = now.add(firesEarly ? duration ~/ 2 : duration);
            firesEarly = false;
          },
        );

        await limit.start(ggLog: ggLog);
        await limit.start(ggLog: ggLog);

        expect(waits, [minute, const Duration(seconds: 30)]);
        expect(messages, hasLength(1));
      });

      test('gives the next caller its turn when one failed', () async {
        var isInterrupted = true;
        final limit = RequestLimit(
          limits: const [(within: minute, requests: 1)],
          now: () => now,
          wait: (duration) async {
            if (isInterrupted) {
              isInterrupted = false;
              throw StateError('interrupted');
            }
            now = now.add(duration);
          },
        );

        await limit.start(ggLog: ggLog);
        await expectLater(limit.start(ggLog: ggLog), throwsStateError);
        await limit.start(ggLog: ggLog);
      });

      test('lets at least one request start, whatever the limit '
          'says', () async {
        final limit = limitOf(const [(within: minute, requests: 0)]);

        await limit.start(ggLog: ggLog);
        expect(waits, isEmpty);

        await limit.start(ggLog: ggLog);
        expect(waits, [minute]);
      });

      test('names other lengths of time in seconds and rounds the wait '
          'up', () async {
        final limit = limitOf(const [
          (within: Duration(seconds: 90), requests: 1),
        ]);

        await limit.start(ggLog: ggLog);
        pass(const Duration(seconds: 89, milliseconds: 500));
        await limit.start(ggLog: ggLog);

        expect(messages, [
          '1 requests started within 90s, and a provider takes no more. '
              'Waiting 1s.',
        ]);
      });

      test('reads the clock and waits for real by default', () async {
        final limit = RequestLimit(
          limits: const [(within: Duration(milliseconds: 60), requests: 1)],
        );
        final stopwatch = Stopwatch()..start();

        await limit.start(ggLog: ggLog);
        await limit.start(ggLog: ggLog);

        expect(
          stopwatch.elapsed,
          greaterThanOrEqualTo(const Duration(milliseconds: 50)),
        );
      });
    });

    group('pullRequests', () {
      test('holds what GitHub takes of requests that create content', () {
        expect(RequestLimit.gitHubContentLimits, const [
          (within: minute, requests: 80),
          (within: hour, requests: 500),
        ]);
        expect(
          RequestLimit.pullRequests.limits,
          RequestLimit.gitHubContentLimits,
        );
      });

      test('is one limit for the whole process', () {
        expect(
          identical(RequestLimit.pullRequests, RequestLimit.pullRequests),
          isTrue,
        );
      });
    });
  });
}
