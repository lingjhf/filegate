#ifndef FLUTTER_PLUGIN_FILEGATE_PLUGIN_PRIVATE_H_
#define FLUTTER_PLUGIN_FILEGATE_PLUGIN_PRIVATE_H_

#include <flutter_linux/flutter_linux.h>

#include "include/filegate/filegate_plugin.h"

// This file exposes some plugin internals for unit testing. See
// https://github.com/flutter/flutter/issues/88724 for current limitations
// in the unit-testable API.

FlMethodResponse *filegate_get_file_size(FlValue *arguments);
FlMethodResponse *filegate_pick_files(FlValue *arguments);
FlMethodResponse *filegate_save_file(FlValue *arguments);

#endif  // FLUTTER_PLUGIN_FILEGATE_PLUGIN_PRIVATE_H_
