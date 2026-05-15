#include "include/filegate/filegate_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "filegate_plugin.h"

void FilegatePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  filegate::FilegatePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
