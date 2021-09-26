//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <libwinmedia/libwinmedia_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) libwinmedia_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "LibwinmediaPlugin");
  libwinmedia_plugin_register_with_registrar(libwinmedia_registrar);
}
