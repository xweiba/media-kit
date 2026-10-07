# Apple audio analysis filters

This fork consumes xweiba/libmpv-darwin-build tag `0.6.8-mediaio.4`
(source commit `4012ae32ca8d7ab8ee4f2ba202b9e3c55c3e1b5a`), based on
mpv 0.36 / FFmpeg 6.0. Upstream: https://github.com/media-kit/media-kit.

The music visualizer requires astats, aresample, aformat, anull, asplit,
pan, bandpass and amerge. The common FFmpeg configuration enables all eight
for device and simulator frameworks. Existing MediaIO patches are preserved.

Both Apple video-library packages download the published per-framework ZIPs.
Each archive is checked against the committed SHA256 manifest before extraction;
iOS no longer depends on a combined archive that the release does not publish.

Regression evidence: all 18 archives per host were downloaded and checksummed;
Makefile extraction and mpv header symlinks were verified in isolated directories.
Avfilter binaries contain all eight configure options for macOS universal,
iOS arm64 and iOS simulator universal. This is not a device playback or crash test.

Before release, run the exact visualizer graph on device and simulator, switch
portrait/landscape during playback, and verify playback continues with valid
astats metadata. Restore upstream artifacts once they include these filters and
the required MediaIO patches; do not drop stream callback fixes during migration.
