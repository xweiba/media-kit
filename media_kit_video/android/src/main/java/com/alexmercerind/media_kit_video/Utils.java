/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video;

import android.media.MediaCodecInfo;
import android.media.MediaCodecInfo.CodecProfileLevel;
import android.media.MediaCodecList;
import android.os.Build;

import io.flutter.Log;


public abstract class Utils {
    private static final String TAG = "Utils";

    public static boolean isEmulator() {
        try {
            // https://github.com/fluttercommunity/plus_plugins/blob/ff54dc49230ee5f8b772a3326d4ff3758618df80/packages/device_info_plus/device_info_plus/android/src/main/kotlin/dev/fluttercommunity/plus/device_info/MethodCallHandlerImpl.kt#L110-L125
            return Build.BRAND.startsWith("generic") && Build.DEVICE.startsWith("generic")
                    || Build.FINGERPRINT.startsWith("generic")
                    || Build.FINGERPRINT.startsWith("unknown")
                    || Build.HARDWARE.contains("goldfish")
                    || Build.HARDWARE.contains("ranchu")
                    || Build.MODEL.contains("google_sdk")
                    || Build.MODEL.contains("Emulator")
                    || Build.MODEL.contains("Android SDK built for x86")
                    || Build.MANUFACTURER.contains("Genymotion")
                    || Build.PRODUCT.contains("sdk_google")
                    || Build.PRODUCT.contains("google_sdk")
                    || Build.PRODUCT.contains("sdk")
                    || Build.PRODUCT.contains("sdk_x86")
                    || Build.PRODUCT.contains("vbox86p")
                    || Build.PRODUCT.contains("emulator")
                    || Build.PRODUCT.contains("simulator");
        } catch (Throwable e) {
            Log.e(TAG, "isEmulator", e);
        }
        return false;
    }

    /**
     * Whether a hardware decoder can take this stream ({@code codec} and {@code profile} as mpv
     * reports them, i.e. FFmpeg names such as {@code h264} / {@code High 10}). Frames can only go
     * straight to the display from a hardware decoder; when MediaCodec refuses the stream mpv
     * decodes in software, which the direct output cannot show. Unknown codecs or profiles count
     * as supported (MediaCodec still gets its chance). mpv often leaves the profile empty; then it is
     * derived from the decoded {@code pixelFormat} (e.g. {@code yuv420p10} → H.264 High 10).
     */
    public static boolean hardwareDecoderSupports(String codec, String profile, String pixelFormat) {
        final String mime = codecMime(codec);
        if (mime == null) return true;
        int[] wanted = profileFlags(codec, profile);
        if (wanted == null) wanted = profileFlagsForPixelFormat(codec, pixelFormat);
        try {
            for (MediaCodecInfo info : new MediaCodecList(MediaCodecList.REGULAR_CODECS).getCodecInfos()) {
                if (info.isEncoder()) continue;
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
                        ? !info.isHardwareAccelerated()
                        : isSoftwareCodecName(info.getName())) continue;
                for (String type : info.getSupportedTypes()) {
                    if (!type.equalsIgnoreCase(mime)) continue;
                    if (wanted == null) return true;
                    for (CodecProfileLevel level : info.getCapabilitiesForType(type).profileLevels) {
                        for (int flag : wanted) {
                            if (level.profile == flag) return true;
                        }
                    }
                }
            }
        } catch (Throwable e) {
            Log.e(TAG, "hardwareDecoderSupports", e);
            return true;
        }
        return false;
    }

    private static boolean isSoftwareCodecName(String name) {
        final String n = name.toLowerCase();
        return n.startsWith("omx.google.") || n.startsWith("c2.android.") || n.contains(".sw.");
    }

    private static String codecMime(String codec) {
        if (codec == null) return null;
        switch (codec) {
            case "h264": return "video/avc";
            case "hevc": return "video/hevc";
            case "vp8": return "video/x-vnd.on2.vp8";
            case "vp9": return "video/x-vnd.on2.vp9";
            case "av1": return "video/av01";
            case "mpeg2video": return "video/mpeg2";
            case "mpeg4": return "video/mp4v-es";
            default: return null;
        }
    }

    /** MediaCodec profile constants matching an FFmpeg profile name; {@code null} = any. */
    private static int[] profileFlags(String codec, String profile) {
        if (profile == null) return null;
        switch (codec) {
            case "h264":
                switch (profile) {
                    case "Constrained Baseline":
                    case "Baseline": return new int[]{CodecProfileLevel.AVCProfileBaseline, CodecProfileLevel.AVCProfileConstrainedBaseline};
                    case "Main": return new int[]{CodecProfileLevel.AVCProfileMain};
                    case "Extended": return new int[]{CodecProfileLevel.AVCProfileExtended};
                    case "High": return new int[]{CodecProfileLevel.AVCProfileHigh, CodecProfileLevel.AVCProfileConstrainedHigh};
                    case "High 10":
                    case "High 10 Intra": return new int[]{CodecProfileLevel.AVCProfileHigh10};
                    case "High 4:2:2":
                    case "High 4:2:2 Intra": return new int[]{CodecProfileLevel.AVCProfileHigh422};
                    case "High 4:4:4":
                    case "High 4:4:4 Predictive":
                    case "High 4:4:4 Intra": return new int[]{CodecProfileLevel.AVCProfileHigh444};
                    default: return null;
                }
            case "hevc":
                switch (profile) {
                    case "Main": return new int[]{CodecProfileLevel.HEVCProfileMain};
                    case "Main 10": return new int[]{CodecProfileLevel.HEVCProfileMain10, CodecProfileLevel.HEVCProfileMain10HDR10, CodecProfileLevel.HEVCProfileMain10HDR10Plus};
                    case "Main Still Picture": return new int[]{CodecProfileLevel.HEVCProfileMainStill};
                    default: return null;
                }
            case "vp9":
                switch (profile) {
                    case "Profile 0": return new int[]{CodecProfileLevel.VP9Profile0};
                    case "Profile 1": return new int[]{CodecProfileLevel.VP9Profile1};
                    case "Profile 2": return new int[]{CodecProfileLevel.VP9Profile2, CodecProfileLevel.VP9Profile2HDR, CodecProfileLevel.VP9Profile2HDR10Plus};
                    case "Profile 3": return new int[]{CodecProfileLevel.VP9Profile3, CodecProfileLevel.VP9Profile3HDR, CodecProfileLevel.VP9Profile3HDR10Plus};
                    default: return null;
                }
            default:
                return null;
        }
    }

    /** Profile constants implied by bit depth / chroma of the decoded frames; {@code null} = any. */
    private static int[] profileFlagsForPixelFormat(String codec, String pixelFormat) {
        if (pixelFormat == null || pixelFormat.isEmpty()) return null;
        final String f = pixelFormat.toLowerCase();
        final boolean chroma444 = f.contains("444") || f.startsWith("gbr");
        final boolean chroma422 = f.contains("422");
        final boolean highDepth = f.matches(".*(p9|p10|p12|p14|p16)(le|be)?$") || f.startsWith("p010") || f.startsWith("p016");
        switch (codec) {
            case "h264":
                if (chroma444) return new int[]{CodecProfileLevel.AVCProfileHigh444};
                if (chroma422) return new int[]{CodecProfileLevel.AVCProfileHigh422};
                if (highDepth) return new int[]{CodecProfileLevel.AVCProfileHigh10};
                return null;
            case "hevc":
                if (chroma444 || chroma422) return new int[]{};
                if (highDepth) return new int[]{CodecProfileLevel.HEVCProfileMain10, CodecProfileLevel.HEVCProfileMain10HDR10, CodecProfileLevel.HEVCProfileMain10HDR10Plus};
                return null;
            case "vp9":
                if (chroma444 || chroma422) return highDepth
                        ? new int[]{CodecProfileLevel.VP9Profile3, CodecProfileLevel.VP9Profile3HDR, CodecProfileLevel.VP9Profile3HDR10Plus}
                        : new int[]{CodecProfileLevel.VP9Profile1};
                if (highDepth) return new int[]{CodecProfileLevel.VP9Profile2, CodecProfileLevel.VP9Profile2HDR, CodecProfileLevel.VP9Profile2HDR10Plus};
                return null;
            case "av1":
                if (chroma444 || chroma422) return new int[]{};
                if (highDepth) return new int[]{CodecProfileLevel.AV1ProfileMain10, CodecProfileLevel.AV1ProfileMain10HDR10, CodecProfileLevel.AV1ProfileMain10HDR10Plus};
                return null;
            default:
                return null;
        }
    }
}
