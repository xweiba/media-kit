import 'package:media_kit/src/player/native/player/real.dart';
import 'package:test/test.dart';

void main() {
  test('only cache export failure is excluded from cplayer playback errors',
      () {
    expect(isCacheDumpFailure('Cache dumping stopped due to error.'), isTrue);
    expect(isCacheDumpFailure('Failed to open media.'), isFalse);
    expect(isCacheDumpFailure('No demuxer open.'), isFalse);
    expect(isCacheDumpFailure(''), isFalse);
  });
}
