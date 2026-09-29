@TestOn('vm')
library video_controller_initialization_test;

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  testWidgets('idle controller creation requests one initialization frame',
      (tester) async {
    await tester.pumpAndSettle();
    expect(tester.binding.schedulerPhase, SchedulerPhase.idle);
    expect(tester.binding.hasScheduledFrame, isFalse);

    final player = _PendingPlayer();
    final controller = VideoController(player);
    // Keep native setup behind a controlled handle boundary: this test proves
    // frame scheduling, not native rendering or successful decoder creation.
    final initialization = expectLater(
      controller.platform.future,
      throwsA(same(player.cancelled)),
    );
    final scheduled = tester.binding.hasScheduledFrame;
    final requestedBeforeFrame = player.handleRequested;
    // Let the failure control finish initialization too, so a missing frame
    // request fails the assertion below without leaving an uncompleted Future.
    if (!scheduled) tester.binding.scheduleFrame();

    await tester.pump();
    expect(player.handleRequested, isTrue);
    expect(tester.binding.hasScheduledFrame, isFalse);
    player.handleResult.completeError(player.cancelled);
    await tester.pump();
    await initialization;
    expect(scheduled, isTrue,
        reason: 'Creation must wake an idle Flutter scene');
    expect(requestedBeforeFrame, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}

class _PendingPlayer implements Player {
  final handleResult = Completer<int>();
  final cancelled = StateError('controlled native initialization boundary');
  bool handleRequested = false;

  @override
  PlatformPlayer? get platform => null;

  @override
  Future<int> get handle {
    handleRequested = true;
    return handleResult.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
