// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#include "include/media_kit_video/utils.h"

// Same bound as macOS: a window manager that never reports the new state must
// not leave the caller waiting forever.
#define FULLSCREEN_TRANSITION_TIMEOUT_MS 3000

typedef struct {
  GtkWidget* window;
  gboolean fullscreen;
  gulong state_handler_id;
  guint timeout_id;
  UtilsFullscreenCallback callback;
  gpointer user_data;
} FullscreenTransition;

static gboolean utils_is_fullscreen(GtkWidget* window) {
  GdkWindow* gdk_window = gtk_widget_get_window(window);
  return gdk_window != NULL && (gdk_window_get_state(gdk_window) &
                                GDK_WINDOW_STATE_FULLSCREEN) != 0;
}

static void fullscreen_transition_finish(FullscreenTransition* transition) {
  if (transition->state_handler_id != 0) {
    g_signal_handler_disconnect(transition->window,
                                transition->state_handler_id);
  }
  if (transition->timeout_id != 0) {
    g_source_remove(transition->timeout_id);
  }
  transition->callback(transition->user_data);
  g_object_unref(transition->window);
  g_free(transition);
}

static gboolean fullscreen_transition_state_cb(GtkWidget* widget,
                                               GdkEventWindowState* event,
                                               gpointer data) {
  FullscreenTransition* transition = (FullscreenTransition*)data;
  gboolean fullscreen =
      (event->new_window_state & GDK_WINDOW_STATE_FULLSCREEN) != 0;
  if (fullscreen == transition->fullscreen) {
    fullscreen_transition_finish(transition);
  }
  return FALSE;
}

static gboolean fullscreen_transition_timeout_cb(gpointer data) {
  FullscreenTransition* transition = (FullscreenTransition*)data;
  // Returning G_SOURCE_REMOVE destroys the source; don't remove it again.
  transition->timeout_id = 0;
  fullscreen_transition_finish(transition);
  return G_SOURCE_REMOVE;
}

void utils_set_native_fullscreen(GtkWidget* window,
                                 gboolean fullscreen,
                                 UtilsFullscreenCallback callback,
                                 gpointer user_data) {
  // Unrealized windows have no state to wait for; already in the requested
  // state means GTK will not report a change.
  if (gtk_widget_get_window(window) == NULL ||
      utils_is_fullscreen(window) == fullscreen) {
    if (fullscreen) {
      gtk_window_fullscreen(GTK_WINDOW(window));
    } else {
      gtk_window_unfullscreen(GTK_WINDOW(window));
    }
    callback(user_data);
    return;
  }
  FullscreenTransition* transition = g_new0(FullscreenTransition, 1);
  transition->window = GTK_WIDGET(g_object_ref(window));
  transition->fullscreen = fullscreen;
  transition->callback = callback;
  transition->user_data = user_data;
  transition->state_handler_id =
      g_signal_connect(window, "window-state-event",
                       G_CALLBACK(fullscreen_transition_state_cb), transition);
  transition->timeout_id =
      g_timeout_add(FULLSCREEN_TRANSITION_TIMEOUT_MS,
                    fullscreen_transition_timeout_cb, transition);
  if (fullscreen) {
    gtk_window_fullscreen(GTK_WINDOW(window));
  } else {
    gtk_window_unfullscreen(GTK_WINDOW(window));
  }
}

void utils_enter_native_fullscreen(GtkWidget* window) {
  gtk_window_fullscreen(GTK_WINDOW(window));
}

void utils_exit_native_fullscreen(GtkWidget* window) {
  gtk_window_unfullscreen(GTK_WINDOW(window));
}
