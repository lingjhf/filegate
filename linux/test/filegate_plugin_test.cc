#include <flutter_linux/flutter_linux.h>
#include <gtest/gtest.h>

#include "filegate_plugin_private.h"
#include "include/filegate/filegate_plugin.h"

namespace filegate {
namespace test {

TEST(FilegatePlugin, GetFileSizeMissingPathReturnsInvalidArgs) {
  g_autoptr(FlMethodResponse) response = filegate_get_file_size(nullptr);
  ASSERT_NE(response, nullptr);
  ASSERT_TRUE(FL_IS_METHOD_ERROR_RESPONSE(response));
  EXPECT_STREQ(fl_method_error_response_get_code(
                   FL_METHOD_ERROR_RESPONSE(response)),
               "invalid_args");
}

TEST(FilegatePlugin, PickMixedModeReturnsUnsupportedMode) {
  g_autoptr(FlValue) arguments = fl_value_new_map();
  fl_value_set_string_take(arguments, "selectionMode",
                           fl_value_new_string("filesAndDirectories"));

  g_autoptr(FlMethodResponse) response = filegate_pick_files(arguments);
  ASSERT_NE(response, nullptr);
  ASSERT_TRUE(FL_IS_METHOD_ERROR_RESPONSE(response));
  EXPECT_STREQ(fl_method_error_response_get_code(
                   FL_METHOD_ERROR_RESPONSE(response)),
               "unsupported_mode");
}

}  // namespace test
}  // namespace filegate
