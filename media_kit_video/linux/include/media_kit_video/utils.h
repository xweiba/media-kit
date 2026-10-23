// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#include <gtk/gtk.h>

typedef void (*UtilsFullscreenCallback)(gpointer user_data);

// Requests (or leaves) fullscreen for |window| and invokes |callback| on the
// main thread once GTK reports the new window state, immediately when the
// window is already in that state, or after a timeout.
void utils_set_native_fullscreen(GtkWidget* window,
                                 gboolean fullscreen,
                                 UtilsFullscreenCallback callback,
                                 gpointer user_data);

void utils_enter_native_fullscreen(GtkWidget* window);

void utils_exit_native_fullscreen(GtkWidget* window);
