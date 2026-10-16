/// The kind of a native event attributed to one [Player.open] source token.
enum PlaybackSourceEventKind {
  /// The playlist entry associated with an attributed open has started.
  start,

  /// libmpv reported the first playback restart for this attempt.
  firstFrame,

  /// The media position changed.
  position,

  /// The media duration changed.
  duration,

  /// The pause property changed; `false` means playing.
  playing,

  /// The native core/cache buffering state changed.
  buffering,

  /// libmpv reported a buffering percentage in the inclusive 0..100 range.
  bufferingPercentage,

  /// The native end-of-file property became true.
  completed,

  /// The playlist entry ended. [PlaybackSourceEvent.reason] describes why.
  ended,

  /// The playlist entry failed with a native libmpv error.
  error,

  /// Source attribution could not be established safely.
  invalidated,
}

/// Native playback evidence tied to a caller-provided open token.
///
/// `source` is the exact object passed to [Player.open]. It is never inferred
/// from the Player's current open when a queued native event is delivered.
/// `playlistEntryId` identifies an mpv entry for the lifetime of its core.
/// `attempt` increments each time that entry emits START_FILE, including
/// replay; it is zero for invalidation events without a known entry.
///
/// Only one payload field is populated according to [kind]:
/// [PlaybackSourceEventKind.position] and [PlaybackSourceEventKind.duration]
/// use [duration]; [PlaybackSourceEventKind.playing] uses [playing];
/// [PlaybackSourceEventKind.buffering] uses [buffering];
/// [PlaybackSourceEventKind.bufferingPercentage] uses [percentage];
/// [PlaybackSourceEventKind.completed] uses [completed]; [ended],
/// [error], and [invalidated] use [reason], with [error] also using
/// [errorCode]. [start] and [firstFrame] have no payload.
final class PlaybackSourceEvent {
  const PlaybackSourceEvent({
    required this.source,
    required this.kind,
    required this.attempt,
    this.playlistEntryId,
    this.duration,
    this.playing,
    this.buffering,
    this.percentage,
    this.completed,
    this.errorCode,
    this.reason,
  });

  /// Caller-owned, immutable token supplied to [Player.open].
  final Object source;

  /// Native playlist entry ID, or null when attribution was lost.
  final int? playlistEntryId;

  /// Playback attempt within this entry. Replay increments this value.
  final int attempt;

  /// Event category and its corresponding typed payload.
  final PlaybackSourceEventKind kind;

  /// Position or duration for the matching event kind.
  final Duration? duration;

  /// Playing state for [PlaybackSourceEventKind.playing].
  final bool? playing;

  /// Buffering state for [PlaybackSourceEventKind.buffering].
  final bool? buffering;

  /// Buffering percentage for [PlaybackSourceEventKind.bufferingPercentage].
  final double? percentage;

  /// EOF state for [PlaybackSourceEventKind.completed].
  final bool? completed;

  /// Negative libmpv error code for [PlaybackSourceEventKind.error].
  final int? errorCode;

  /// Stable event reason, or human-readable invalidation detail.
  final String? reason;
}
