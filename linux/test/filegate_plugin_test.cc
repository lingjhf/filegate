#include <flutter_linux/flutter_linux.h>
#include <glib/gstdio.h>
#include <gtest/gtest.h>

#include <unistd.h>

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

TEST(FilegatePlugin, GetFileSizeReturnsFileSize) {
  g_autofree gchar* path = nullptr;
  g_autoptr(GError) error = nullptr;
  int fd = g_file_open_tmp("filegate-test-XXXXXX", &path, &error);
  ASSERT_GE(fd, 0);
  ASSERT_EQ(error, nullptr);

  const char data[] = "hello";
  ASSERT_EQ(write(fd, data, sizeof(data) - 1),
            static_cast<ssize_t>(sizeof(data) - 1));
  close(fd);

  g_autoptr(FlValue) arguments = fl_value_new_map();
  fl_value_set_string_take(arguments, "path", fl_value_new_string(path));

  g_autoptr(FlMethodResponse) response = filegate_get_file_size(arguments);
  ASSERT_NE(response, nullptr);
  ASSERT_TRUE(FL_IS_METHOD_SUCCESS_RESPONSE(response));

  FlValue* result =
      fl_method_success_response_get_result(FL_METHOD_SUCCESS_RESPONSE(response));
  ASSERT_NE(result, nullptr);
  ASSERT_EQ(fl_value_get_type(result), FL_VALUE_TYPE_INT);
  EXPECT_EQ(fl_value_get_int(result), 5);

  g_unlink(path);
}

TEST(FilegatePlugin, GetFileSizeDirectoryReturnsNotAFile) {
  g_autoptr(GError) error = nullptr;
  g_autofree gchar* directory = g_dir_make_tmp("filegate-dir-XXXXXX", &error);
  ASSERT_NE(directory, nullptr);
  ASSERT_EQ(error, nullptr);

  g_autoptr(FlValue) arguments = fl_value_new_map();
  fl_value_set_string_take(arguments, "path", fl_value_new_string(directory));

  g_autoptr(FlMethodResponse) response = filegate_get_file_size(arguments);
  ASSERT_NE(response, nullptr);
  ASSERT_TRUE(FL_IS_METHOD_ERROR_RESPONSE(response));
  EXPECT_STREQ(fl_method_error_response_get_code(
                   FL_METHOD_ERROR_RESPONSE(response)),
               "not_a_file");

  g_rmdir(directory);
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

TEST(FilegatePlugin, PickUnknownModeReturnsInvalidArgs) {
  g_autoptr(FlValue) arguments = fl_value_new_map();
  fl_value_set_string_take(arguments, "selectionMode",
                           fl_value_new_string("unknown"));

  g_autoptr(FlMethodResponse) response = filegate_pick_files(arguments);
  ASSERT_NE(response, nullptr);
  ASSERT_TRUE(FL_IS_METHOD_ERROR_RESPONSE(response));
  EXPECT_STREQ(fl_method_error_response_get_code(
                   FL_METHOD_ERROR_RESPONSE(response)),
               "invalid_args");
}

}  // namespace test
}  // namespace filegate
