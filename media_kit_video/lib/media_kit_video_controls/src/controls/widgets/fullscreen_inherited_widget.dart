/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:media_kit_video/media_kit_video_controls/src/controls/methods/video_state.dart';

/// {@template fullscreen_inherited_widget}
///
/// Inherited widget used to identify whether parent [Video] is in fullscreen or not.
///
/// {@endtemplate}
class FullscreenInheritedWidget extends InheritedWidget {
  final VideoState parent;

  FullscreenInheritedWidget({
    super.key,
    required this.parent,
    required Widget child,
  }) : super(child: _FullscreenInheritedWidgetPopScope(child: child));

  static FullscreenInheritedWidget? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<FullscreenInheritedWidget>();
  }

  static FullscreenInheritedWidget of(BuildContext context) {
    final FullscreenInheritedWidget? result = maybeOf(context);
    assert(
      result != null,
      'No [FullscreenInheritedWidget] found in [context]',
    );
    return result!;
  }

  /// 先完成原生窗口退出动画，再弹出 Flutter 全屏路由。
  ///
  /// 原生窗口与 Flutter 路由同时迁移会在 macOS 上产生瞬时负尺寸，
  /// 因此控件按钮、返回键和系统返回手势必须复用这个串行入口。
  static Future<void> exit(BuildContext context) async {
    final state = context
        .findAncestorStateOfType<_FullscreenInheritedWidgetPopScopeState>();
    await state?.exitFullscreen();
  }

  @override
  bool updateShouldNotify(FullscreenInheritedWidget oldWidget) =>
      identical(parent, oldWidget.parent);
}

/// {@template fullscreen_inherited_widget_pop_scope}
///
/// This widget is used to exit native fullscreen when this route is popped from the navigator.
///
/// {@endtemplate}
class _FullscreenInheritedWidgetPopScope extends StatefulWidget {
  final Widget child;
  const _FullscreenInheritedWidgetPopScope({
    required this.child,
  });

  @override
  State<_FullscreenInheritedWidgetPopScope> createState() =>
      _FullscreenInheritedWidgetPopScopeState();
}

class _FullscreenInheritedWidgetPopScopeState
    extends State<_FullscreenInheritedWidgetPopScope> {
  bool _canPop = false;
  Future<void>? _exitFuture;

  Future<void> exitFullscreen() {
    return _exitFuture ??= _exitFullscreen();
  }

  Future<void> _exitFullscreen() async {
    // Capture every inherited/context-bound dependency before the first await.
    // A concurrent system back gesture may deactivate this route while the
    // native exit callback or end-of-frame wait is pending.
    final navigator = Navigator.of(context);
    final exitNativeFullscreen = onExitFullscreen(context);
    await exitNativeFullscreen?.call();
    if (!mounted) return;

    setState(() => _canPop = true);
    // PopScope 在下一帧才会把新的 canPop 注册给 Navigator。
    // 立即 maybePop 会再次被旧状态拦截，导致全屏路由永远无法退出。
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await navigator.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(exitFullscreen());
        }
      },
      child: widget.child,
    );
  }
}
