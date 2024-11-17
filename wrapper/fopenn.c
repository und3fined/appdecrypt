/*
 * Compile with:
 *
 * clang  fopenn.c -o frida-core-example -L. -lfrida-core -lbsm -ldl
 * -lm -lresolv
 * -Wl,-framework,Foundation,-framework,CoreGraphics,-framework,UIKit
 *
 * Visit https://frida.re to learn more about Frida.
 */

#include "frida-core.h"

#include <stdlib.h>
#include <string.h>

static void on_signal(int signo);
static gboolean stop(gpointer user_data);

static GMainLoop *loop = NULL;

int main(int argc, char *argv[]) {
  guint target_pid;
  FridaDeviceManager *manager;
  GError *error = NULL;
  FridaDeviceList *devices;
  gint num_devices, i;
  FridaDevice *local_device;
  // FridaSession *session;

  frida_init();

  if (argc != 2 || (target_pid = atoi (argv[1])) == 0) {
    g_printerr("Usage: %s <bundle_id> [-R]\n\nOptions:\n-R: Enable remote mode. Port default 1337.", argv[0]);
    return 1;
  }

  loop = g_main_loop_new(NULL, TRUE);

  signal(SIGINT, on_signal);
  signal(SIGTERM, on_signal);

  manager = frida_device_manager_new();

  devices = frida_device_manager_enumerate_devices_sync(manager, NULL, &error);
  g_assert(error == NULL);

  local_device = NULL;
  num_devices = frida_device_list_size(devices);
  for (i = 0; i != num_devices; i++) {
    FridaDevice *device = frida_device_list_get(devices, i);

    g_print("[*] Found device: \"%s\"\n", frida_device_get_name(device));

    if (frida_device_get_dtype(device) == FRIDA_DEVICE_TYPE_LOCAL)
      local_device = g_object_ref(device);

    g_object_unref(device);
  }
  g_assert(local_device != NULL);

  frida_unref(devices);
  devices = NULL;

  frida_device_spawn_sync(local_device, "", NULL, NULL, &error);
  g_assert(error == NULL);

  frida_unref(local_device);

  frida_device_manager_close_sync(manager, NULL, NULL);
  frida_unref(manager);
  g_print("[*] Closed\n");

  g_main_loop_unref(loop);

  return 0;
}

static void on_signal(int signo) { g_idle_add(stop, NULL); }

static gboolean stop(gpointer user_data) {
  g_main_loop_quit(loop);

  return FALSE;
}
