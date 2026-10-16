# media-kit Fork Notes

- Upstream: https://github.com/media-kit/media-kit
- Fork: https://github.com/xweiba/media-kit
- Base commit: `9559d7c798d529106cdabcaddf20d7f68a748a5e`
- Reason: the Player API exposes playback streams without identifying the
  native file-open that produced queued events. Reusing one Player across
  tracks can therefore make a late native event appear to belong to the new
  track.
- Local changes: add an opt-in source token to `Player.open`, a typed
  source-attributed event stream, and libmpv playlist-entry mapping with
  before-start/on-load/after-end property-drain fences. Legacy streams and
  untagged opens retain their existing behavior. Source attribution currently
  accepts a single `Media`; playlists and redirected playlist entries fail
  closed rather than guessing. The runtime libmpv must expose API 1.108 or
  newer playlist entry IDs. Replay events retain the token and increment the
  entry's attempt number.
- Regression coverage: `media_kit/test/src/player/native/native_source_events_test.dart`
  exercises delayed delivery across same-URI replacement, playlist rejection,
  failed-open attribution, recovery, and an existing native lifecycle test.
  Linux tests were run against the system libmpv and the application's shipped
  Linux libmpv. The Android build recipe was checked for hook support, but no
  Android device test was run for this fork patch.
- Upstream status: no issue or pull request has been filed yet. Review the
  minimal API and native event contract with upstream before publishing this
  fork revision.
- Exit condition: return to the official dependency when upstream provides a
  source token captured at native event ingress, stable playlist-entry origin,
  and boundary tests proving that delayed old-file events cannot be attributed
  to the replacement open. At that point remove this fork pin and retain the
  source-event regression tests against the upstream implementation.

The upstream MIT license and original copyright notices remain in place.
