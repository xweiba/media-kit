/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'package:media_kit/media_kit.dart';
import 'package:media_kit/src/player/native/core/native_media_io.dart';
import 'package:test/test.dart';

void main() {
  group('validateNativeMediaIOProviders', () {
    test('accepts a native provider descriptor', () {
      expect(
        () => validateNativeMediaIOProviders(const [
          NativeMediaIOProvider(protocol: 'mediaio', openCallback: 1),
        ]),
        returnsNormally,
      );
    });

    test('rejects invalid URI schemes', () {
      expect(
        () => validateNativeMediaIOProviders(const [
          NativeMediaIOProvider(protocol: 'MediaIO', openCallback: 1),
        ]),
        throwsArgumentError,
      );
    });

    test('rejects duplicate protocols before registration', () {
      expect(
        () => validateNativeMediaIOProviders(const [
          NativeMediaIOProvider(protocol: 'mediaio', openCallback: 1),
          NativeMediaIOProvider(protocol: 'mediaio', openCallback: 2),
        ]),
        throwsArgumentError,
      );
    });

    test('rejects a null open callback', () {
      expect(
        () => validateNativeMediaIOProviders(const [
          NativeMediaIOProvider(protocol: 'mediaio', openCallback: 0),
        ]),
        throwsArgumentError,
      );
    });
  });
}
