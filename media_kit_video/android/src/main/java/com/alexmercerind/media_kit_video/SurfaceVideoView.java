/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video;

import android.content.Context;
import android.graphics.Bitmap;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.view.SurfaceHolder;
import android.view.Gravity;
import android.view.PixelCopy;
import android.view.SurfaceView;
import android.view.View;
import android.widget.FrameLayout;

import androidx.annotation.NonNull;

import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.util.HashMap;
import java.util.Map;

import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;

/**
 * A native {@link SurfaceView} placed by the Dart {@code Video} widget as a platform view
 * (Android surface mode). mpv renders into it through {@code --wid}: with
 * {@code vo=mediacodec_embed} MediaCodec writes decoded frames straight into this surface and the
 * display hardware composes them, so the GPU does not draw every frame twice (mpv into a texture,
 * then Flutter onto the screen).
 * <p>
 * The surface is reported to Dart as a JNI global reference ({@code wid}) together with its pixel
 * size; {@code wid = 0} when it goes away. The reference is released a few seconds later, after mpv
 * has detached (same as {@link VideoOutput}).
 */
final class SurfaceVideoView implements PlatformView, SurfaceHolder.Callback {
    static final String VIEW_TYPE = "com.alexmercerind/media_kit_video/surface";
    private static final Handler handler = new Handler(Looper.getMainLooper());
    /** Views by platform view id, for sizing calls from Dart. */
    static final java.util.HashMap<Integer, SurfaceVideoView> views = new java.util.HashMap<>();

    /**
     * Fills the platform view (hybrid composition sizes the native view to its parent, and cannot
     * resize it from Dart). The {@link SurfaceView} inside is sized and centred here from the video
     * size, so the surface buffer is exactly the shown size and changes without a new view.
     */
    private final FrameLayout container;
    private final SurfaceView view;
    private int videoWidth = 0, videoHeight = 0;
    /** {@code true}: fill and crop (cover); {@code false}: show whole (contain). */
    private boolean cover = false;
    private final MethodChannel channel;
    private final int viewId;
    private final String handle;
    private long wid = 0;

    SurfaceVideoView(Context context, MethodChannel channel, int viewId, String handle) {
        this.container = new FrameLayout(context);
        this.view = new SurfaceView(context);
        this.channel = channel;
        this.viewId = viewId;
        this.handle = handle;
        view.getHolder().addCallback(this);
        container.addView(view, new FrameLayout.LayoutParams(1, 1, Gravity.CENTER));
        container.addOnLayoutChangeListener((v, l, t, r, b, ol, ot, or, ob) -> layoutVideo());
        views.put(viewId, this);
    }

    /** Video size and fit from Dart. */
    void setVideoSize(int width, int height, boolean cover) {
        videoWidth = width;
        videoHeight = height;
        this.cover = cover;
        layoutVideo();
    }

    private void layoutVideo() {
        final int boxW = container.getWidth(), boxH = container.getHeight();
        if (boxW <= 0 || boxH <= 0 || videoWidth <= 0 || videoHeight <= 0) return;
        final double scale = cover
                ? Math.max((double) boxW / videoWidth, (double) boxH / videoHeight)
                : Math.min((double) boxW / videoWidth, (double) boxH / videoHeight);
        final int w = Math.max(1, (int) Math.round(videoWidth * scale));
        final int h = Math.max(1, (int) Math.round(videoHeight * scale));
        final FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) view.getLayoutParams();
        if (params.width == w && params.height == h) return;
        params.width = w;
        params.height = h;
        params.gravity = Gravity.CENTER;
        view.setLayoutParams(params);
    }

    /**
     * Screenshot of the shown frame ({@link PixelCopy}): mpv never sees the frames in this mode.
     * Copied at the video size (the surface buffer holds the decoded frame, the display scales
     * it), encoded off the main thread. {@code format}: {@code jpeg}, {@code png} or {@code raw}
     * (BGRA, like mpv's {@code screenshot-raw}). {@code maxWidth} (optional) shrinks the copy,
     * keeping the aspect ratio: PixelCopy scales while copying, so small frames (GIF) cost less.
     * Replies {@code null} when there is no frame.
     */
    void capture(String format, Integer maxWidth, MethodChannel.Result result) {
        int w = videoWidth > 0 ? videoWidth : view.getWidth();
        int h = videoHeight > 0 ? videoHeight : view.getHeight();
        if (maxWidth != null && maxWidth > 0 && w > maxWidth) {
            h = Math.max(1, Math.round((float) h * maxWidth / w));
            w = maxWidth;
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N || wid == 0 || w <= 0 || h <= 0) {
            result.success(null);
            return;
        }
        final Bitmap bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
        try {
            PixelCopy.request(view, bitmap, code -> {
                if (code != PixelCopy.SUCCESS) {
                    bitmap.recycle();
                    result.success(null);
                    return;
                }
                new Thread(() -> {
                    byte[] bytes = null;
                    try {
                        bytes = encode(bitmap, format);
                    } catch (Throwable ignored) {
                    } finally {
                        bitmap.recycle();
                    }
                    final byte[] out = bytes;
                    handler.post(() -> result.success(out));
                }, "media_kit_capture").start();
            }, handler);
        } catch (IllegalArgumentException e) {
            // The surface went away between the check and the request.
            bitmap.recycle();
            result.success(null);
        }
    }

    private static byte[] encode(Bitmap bitmap, String format) {
        if ("raw".equals(format)) {
            final ByteBuffer buffer = ByteBuffer.allocate(bitmap.getByteCount());
            bitmap.copyPixelsToBuffer(buffer);
            final byte[] pixels = buffer.array();
            // ARGB_8888 is RGBA in memory; mpv's raw screenshots are BGRA.
            for (int i = 0; i + 3 < pixels.length; i += 4) {
                final byte r = pixels[i];
                pixels[i] = pixels[i + 2];
                pixels[i + 2] = r;
            }
            return pixels;
        }
        final ByteArrayOutputStream stream = new ByteArrayOutputStream();
        final boolean png = "png".equals(format);
        bitmap.compress(png ? Bitmap.CompressFormat.PNG : Bitmap.CompressFormat.JPEG, png ? 100 : 92,
                stream);
        return stream.toByteArray();
    }

    @NonNull
    @Override
    public View getView() {
        return container;
    }

    @Override
    public void surfaceCreated(@NonNull SurfaceHolder holder) {
    }

    @Override
    public void surfaceChanged(@NonNull SurfaceHolder holder, int format, int width, int height) {
        // A resized surface keeps its reference; only report the new size.
        if (wid == 0) wid = VideoOutput.newGlobalObjectRef(holder.getSurface());
        report(width, height);
    }

    @Override
    public void surfaceDestroyed(@NonNull SurfaceHolder holder) {
        detach();
    }

    @Override
    public void dispose() {
        views.remove(viewId);
        view.getHolder().removeCallback(this);
        detach();
    }

    private void detach() {
        if (wid == 0) return;
        final long reference = wid;
        wid = 0;
        report(0, 0);
        handler.postDelayed(() -> VideoOutput.deleteGlobalObjectRef(reference), 5000);
    }

    private void report(int width, int height) {
        final Map<String, Object> arguments = new HashMap<>();
        arguments.put("handle", handle);
        arguments.put("viewId", viewId);
        arguments.put("wid", wid);
        arguments.put("width", width);
        arguments.put("height", height);
        channel.invokeMethod("SurfaceVideoView.Surface", arguments);
    }

    static final class Factory extends PlatformViewFactory {
        private final MethodChannel channel;

        Factory(MethodChannel channel) {
            super(StandardMessageCodec.INSTANCE);
            this.channel = channel;
        }

        @NonNull
        @Override
        public PlatformView create(Context context, int viewId, Object args) {
            return new SurfaceVideoView(context, channel, viewId, (String) args);
        }
    }
}
