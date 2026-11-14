// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';

/// So many requests may start within a length of time.
typedef RequestWindow = ({Duration within, int requests});

/// Lets requests start only as often as a provider takes them from one
/// client: at most so many within a minute, within an hour.
///
/// A provider counts the requests that create something — a pull request, a
/// comment — per client, and locks a client out for minutes when it sends
/// more. What counts is how many requests **start** within the time, not
/// how many run at the same moment. So a caller may send as many at once as
/// it likes and asks [start] before each: it completes right away while the
/// count allows one more, and otherwise once enough of the earlier requests
/// are older than the time counted.
class RequestLimit {
  /// Constructor. Within each of the [limits] no more requests start than
  /// it names, at least one. [now] and [wait] are for tests.
  RequestLimit({
    required this.limits,
    this._now = DateTime.now,
    this._wait = _delayed,
  });

  // ...........................................................................
  /// What GitHub takes of requests that create content: 80 within a minute
  /// and 500 within an hour.
  static const List<RequestWindow> gitHubContentLimits = [
    (within: Duration(minutes: 1), requests: 80),
    (within: Duration(hours: 1), requests: 500),
  ];

  /// The limit of the pull requests this process creates, shared by
  /// everything that creates one: the provider counts them together too.
  static final RequestLimit pullRequests = RequestLimit(
    limits: gitHubContentLimits,
  );

  /// How many requests may start within which time.
  final List<RequestWindow> limits;

  // ...........................................................................
  /// Completes when one more request may start, and counts it. Callers are
  /// served in the order they asked.
  ///
  /// A caller that has to wait is told so once through [ggLog]; [what]
  /// names the requests in that message.
  Future<void> start({required GgLog ggLog, String what = 'requests'}) {
    final turn = _queue.then((_) => _start(ggLog, what));
    // The next caller gets its turn also when this one failed.
    _queue = turn.then((_) {}, onError: (Object _) {});
    return turn;
  }

  // ######################
  // Private
  // ######################

  final DateTime Function() _now;
  final Future<void> Function(Duration) _wait;

  /// When the requests that still count started, oldest first.
  final List<DateTime> _starts = [];

  /// Completes when the caller before is through.
  Future<void> _queue = Future<void>.value();

  // ...........................................................................
  static Future<void> _delayed(Duration duration) =>
      Future<void>.delayed(duration);

  // ...........................................................................
  Future<void> _start(GgLog ggLog, String what) async {
    var isTold = false;

    while (true) {
      final (:delay, :limit) = _delayAt(_now());
      if (limit == null) {
        break;
      }

      if (!isTold) {
        isTold = true;
        ggLog(
          cDetail(
            '${limit.requests} $what started within ${_spell(limit.within)}, '
            'and a provider takes no more. Waiting ${_seconds(delay)}s.',
          ),
        );
      }
      await _wait(delay);
    }

    final now = _now();
    _starts.add(now);
    _forgetBefore(now);
  }

  // ...........................................................................
  /// How long a request has to wait at [now], and the limit it waits for —
  /// the one that makes it wait longest. No limit: it may start.
  ({Duration delay, RequestWindow? limit}) _delayAt(DateTime now) {
    var delay = Duration.zero;
    RequestWindow? waitsFor;

    for (final limit in limits) {
      final requests = limit.requests < 1 ? 1 : limit.requests;
      final from = now.subtract(limit.within);
      final counted = _starts.where((start) => start.isAfter(from)).toList();
      if (counted.length < requests) {
        continue;
      }

      // One more may start as soon as only requests - 1 are left in the
      // time counted: when this one has left it.
      final leaving = counted[counted.length - requests];
      final wait = leaving.add(limit.within).difference(now);
      if (wait > delay) {
        delay = wait;
        waitsFor = limit;
      }
    }

    return (delay: delay, limit: waitsFor);
  }

  // ...........................................................................
  /// Drops the starts no limit counts anymore.
  void _forgetBefore(DateTime now) {
    var longest = Duration.zero;
    for (final limit in limits) {
      if (limit.within > longest) {
        longest = limit.within;
      }
    }

    final from = now.subtract(longest);
    _starts.removeWhere((start) => !start.isAfter(from));
  }

  // ...........................................................................
  static String _spell(Duration within) {
    if (within == const Duration(minutes: 1)) {
      return 'a minute';
    }
    if (within == const Duration(hours: 1)) {
      return 'an hour';
    }
    return '${within.inSeconds}s';
  }

  // ...........................................................................
  /// [delay] in full seconds, rounded up: »Waiting 0s« would be a lie.
  static int _seconds(Duration delay) => (delay.inMilliseconds / 1000).ceil();
}
