/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:ffi';

import 'package:media_kit/ffi/ffi.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as generated;
import 'package:media_kit/src/player/platform_player.dart';

typedef _MediaIOOpenNative = Int32 Function(
  Pointer<Void> userData,
  Pointer<Char> uri,
  Pointer<Void> info,
);

typedef _MpvStreamCbAddRoNative = Int32 Function(
  Pointer<generated.mpv_handle> context,
  Pointer<Char> protocol,
  Pointer<Void> userData,
  Pointer<NativeFunction<_MediaIOOpenNative>> open,
);

typedef _MpvStreamCbAddRoDart = int Function(
  Pointer<generated.mpv_handle> context,
  Pointer<Char> protocol,
  Pointer<Void> userData,
  Pointer<NativeFunction<_MediaIOOpenNative>> open,
);

final RegExp _protocolPattern = RegExp(r'^[a-z][a-z0-9+.-]*$');

/// Returns the FFmpeg demuxer options required by registered native readers.
///
/// The downstream FFmpeg patch is deliberately default-off. Enabling custom
/// nested I/O only when a provider is present preserves upstream behavior for
/// players which do not register a host-owned protocol.
Iterable<String> nativeMediaIODemuxerOptions(
  List<NativeMediaIOProvider> providers,
) sync* {
  if (providers.isNotEmpty) yield 'allow_custom_io=1';
}

/// Returns mpv properties required for playlists which reference a registered
/// host-owned protocol.
///
/// mpv applies its own playlist safety gate before FFmpeg sees the protocol
/// whitelist. The opt-in remains scoped to players with an explicitly
/// registered native provider, so ordinary network playlists keep upstream
/// safety behavior.
Map<String, String> nativeMediaIOPlayerProperties(
  List<NativeMediaIOProvider> providers,
) =>
    providers.isEmpty ? const {} : const {'load-unsafe-playlists': 'yes'};

/// Validates native media I/O descriptors before any protocol is registered.
///
/// Validation is completed as a separate pass because libmpv does not provide
/// protocol unregistration. This prevents an invalid later descriptor from
/// leaving a player with only part of its requested providers installed.
void validateNativeMediaIOProviders(List<NativeMediaIOProvider> providers) {
  final protocols = <String>{};
  for (final provider in providers) {
    if (!_protocolPattern.hasMatch(provider.protocol)) {
      throw ArgumentError.value(
        provider.protocol,
        'protocol',
        'Must be a lowercase URI scheme.',
      );
    }
    if (!protocols.add(provider.protocol)) {
      throw ArgumentError.value(
        provider.protocol,
        'protocol',
        'Each media I/O protocol may only be registered once per player.',
      );
    }
    if (provider.openCallback == 0) {
      throw ArgumentError.value(
        provider.openCallback,
        'openCallback',
        'Must point to a native mpv_stream_cb_open_ro_fn callback.',
      );
    }
  }
}

/// Registers host-owned native media readers on a libmpv player instance.
///
/// Only the one-time registration crosses Dart. Blocking open/read/seek calls
/// stay entirely in native code and therefore never block a Dart isolate.
void registerNativeMediaIOProviders(
  DynamicLibrary library,
  Pointer<generated.mpv_handle> context,
  List<NativeMediaIOProvider> providers,
) {
  if (providers.isEmpty) return;

  validateNativeMediaIOProviders(providers);
  final addReadOnlyProtocol =
      library.lookupFunction<_MpvStreamCbAddRoNative, _MpvStreamCbAddRoDart>(
    'mpv_stream_cb_add_ro',
  );

  for (final provider in providers) {
    final protocol = provider.protocol.toNativeUtf8();
    try {
      final result = addReadOnlyProtocol(
        context,
        protocol.cast(),
        Pointer<Void>.fromAddress(provider.userData),
        Pointer<NativeFunction<_MediaIOOpenNative>>.fromAddress(
          provider.openCallback,
        ),
      );
      if (result < 0) {
        throw StateError(
          'mpv_stream_cb_add_ro failed for ${provider.protocol}: $result',
        );
      }
    } finally {
      calloc.free(protocol);
    }
  }
}
