#include <flutter_linux/flutter_linux.h>
#include <glib/gstdio.h>
#include <gtest/gtest.h>

#include <unistd.h>

#include "filegate_plugin_private.h"
#include "include/filegate/filegate_plugin.h"

namespace filegate {
namespace test {

namespace {

void ExpectErrorCode(FlMethodResponse* response, const char* code) {
  ASSERT_NE(response, nullptr);
  ASSERT_TRUE(FL_IS_METHOD_ERROR_RESPONSE(response));
  EXPECT_STREQ(
      fl_method_error_response_get_code(FL_METHOD_ERROR_RESPONSE(response)),
      code);
}

gchar* ReadTextFile(const char* path) {
  gchar* contents = nullptr;
  gsize length = 0;
  g_autoptr(GError) error = nullptr;
  if (!g_file_get_contents(path, &contents, &length, &error)) {
    return nullptr;
  }
  return contents;
}

}  // namespace

TEST(FilegatePlugin, GetFileSizeMissingPathReturnsInvalidArgs) {
  g_autoptr(FlMethodResponse) response = filegate_get_file_size(nullptr);
  ExpectErrorCode(response, "invalid_args");
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
  ExpectErrorCode(response, "not_a_file");

  g_rmdir(directory);
}

TEST(FilegatePlugin, PickMixedModeReturnsUnsupportedMode) {
  g_autoptr(FlValue) arguments = fl_value_new_map();
  fl_value_set_string_take(arguments, "selectionMode",
                           fl_value_new_string("filesAndDirectories"));

  g_autoptr(FlMethodResponse) response = filegate_pick_files(arguments);
  ExpectErrorCode(response, "unsupported_mode");
}

TEST(FilegatePlugin, PickUnknownModeReturnsInvalidArgs) {
  g_autoptr(FlValue) arguments = fl_value_new_map();
  fl_value_set_string_take(arguments, "selectionMode",
                           fl_value_new_string("unknown"));

  g_autoptr(FlMethodResponse) response = filegate_pick_files(arguments);
  ExpectErrorCode(response, "invalid_args");
}

TEST(FilegatePlugin, SaveMissingBytesReturnsInvalidArgs) {
  g_autoptr(FlValue) arguments = fl_value_new_map();
  fl_value_set_string_take(arguments, "suggestedName",
                           fl_value_new_string("export.txt"));

  g_autoptr(FlMethodResponse) response = filegate_save_file(arguments);
  ExpectErrorCode(response, "invalid_args");
}

TEST(FilegatePlugin, SaveMissingNameReturnsInvalidArgs) {
  const uint8_t bytes[] = {1, 2, 3};
  g_autoptr(FlValue) arguments = fl_value_new_map();
  fl_value_set_string_take(
      arguments, "bytes",
      fl_value_new_uint8_list(bytes, sizeof(bytes) / sizeof(uint8_t)));

  g_autoptr(FlMethodResponse) response = filegate_save_file(arguments);
  ExpectErrorCode(response, "invalid_args");
}

TEST(FilegatePlugin, SaveBlankNameReturnsInvalidArgs) {
  const uint8_t bytes[] = {1, 2, 3};
  g_autoptr(FlValue) arguments = fl_value_new_map();
  fl_value_set_string_take(
      arguments, "bytes",
      fl_value_new_uint8_list(bytes, sizeof(bytes) / sizeof(uint8_t)));
  fl_value_set_string_take(arguments, "suggestedName",
                           fl_value_new_string("   "));

  g_autoptr(FlMethodResponse) response = filegate_save_file(arguments);
  ExpectErrorCode(response, "invalid_args");
}

TEST(FilegatePlugin, WriteMissingPathReturnsInvalidArgs) {
  g_autoptr(FlMethodResponse) response = filegate_write_file(nullptr);
  ExpectErrorCode(response, "invalid_args");
}

TEST(FilegatePlugin, WriteMissingBytesReturnsInvalidArgs) {
  g_autoptr(FlValue) arguments = fl_value_new_map();
  fl_value_set_string_take(arguments, "path",
                           fl_value_new_string("/tmp/filegate-test.txt"));

  g_autoptr(FlMethodResponse) response = filegate_write_file(arguments);
  ExpectErrorCode(response, "invalid_args");
}

TEST(FilegatePlugin, WriteUnknownModeReturnsInvalidArgs) {
  const uint8_t bytes[] = {1};
  g_autoptr(FlValue) arguments = fl_value_new_map();
  fl_value_set_string_take(arguments, "path",
                           fl_value_new_string("/tmp/filegate-test.txt"));
  fl_value_set_string_take(
      arguments, "bytes",
      fl_value_new_uint8_list(bytes, sizeof(bytes) / sizeof(uint8_t)));
  fl_value_set_string_take(arguments, "mode", fl_value_new_string("unknown"));

  g_autoptr(FlMethodResponse) response = filegate_write_file(arguments);
  ExpectErrorCode(response, "invalid_args");
}

TEST(FilegatePlugin, WriteMissingFileReturnsPathNotFound) {
  const uint8_t bytes[] = {1};
  g_autofree gchar* path =
      g_build_filename(g_get_tmp_dir(), "filegate-missing-write.txt", nullptr);
  g_unlink(path);
  g_autoptr(FlValue) arguments = fl_value_new_map();
  fl_value_set_string_take(arguments, "path", fl_value_new_string(path));
  fl_value_set_string_take(
      arguments, "bytes",
      fl_value_new_uint8_list(bytes, sizeof(bytes) / sizeof(uint8_t)));
  fl_value_set_string_take(arguments, "mode", fl_value_new_string("append"));

  g_autoptr(FlMethodResponse) response = filegate_write_file(arguments);
  ExpectErrorCode(response, "path_not_found");
}

TEST(FilegatePlugin, WriteDirectoryReturnsNotAFile) {
  const uint8_t bytes[] = {1};
  g_autoptr(GError) error = nullptr;
  g_autofree gchar* directory = g_dir_make_tmp("filegate-dir-XXXXXX", &error);
  ASSERT_NE(directory, nullptr);
  ASSERT_EQ(error, nullptr);
  g_autoptr(FlValue) arguments = fl_value_new_map();
  fl_value_set_string_take(arguments, "path", fl_value_new_string(directory));
  fl_value_set_string_take(
      arguments, "bytes",
      fl_value_new_uint8_list(bytes, sizeof(bytes) / sizeof(uint8_t)));
  fl_value_set_string_take(arguments, "mode", fl_value_new_string("append"));

  g_autoptr(FlMethodResponse) response = filegate_write_file(arguments);
  ExpectErrorCode(response, "not_a_file");

  g_rmdir(directory);
}

TEST(FilegatePlugin, WriteAppendAddsBytes) {
  g_autofree gchar* path = nullptr;
  g_autoptr(GError) error = nullptr;
  int fd = g_file_open_tmp("filegate-write-XXXXXX", &path, &error);
  ASSERT_GE(fd, 0);
  ASSERT_EQ(error, nullptr);

  const char initial[] = "hello";
  ASSERT_EQ(write(fd, initial, sizeof(initial) - 1),
            static_cast<ssize_t>(sizeof(initial) - 1));
  close(fd);

  const uint8_t bytes[] = {' ', 'w', 'o', 'r', 'l', 'd'};
  g_autoptr(FlValue) arguments = fl_value_new_map();
  fl_value_set_string_take(arguments, "path", fl_value_new_string(path));
  fl_value_set_string_take(
      arguments, "bytes",
      fl_value_new_uint8_list(bytes, sizeof(bytes) / sizeof(uint8_t)));
  fl_value_set_string_take(arguments, "mode", fl_value_new_string("append"));

  g_autoptr(FlMethodResponse) response = filegate_write_file(arguments);
  ASSERT_NE(response, nullptr);
  ASSERT_TRUE(FL_IS_METHOD_SUCCESS_RESPONSE(response));

  g_autofree gchar* contents = ReadTextFile(path);
  ASSERT_NE(contents, nullptr);
  EXPECT_STREQ(contents, "hello world");

  FlValue* result =
      fl_method_success_response_get_result(FL_METHOD_SUCCESS_RESPONSE(response));
  ASSERT_NE(result, nullptr);
  ASSERT_EQ(fl_value_get_type(result), FL_VALUE_TYPE_MAP);
  EXPECT_STREQ(fl_value_get_string(fl_value_lookup_string(result, "path")),
               path);
  EXPECT_STREQ(fl_value_get_string(fl_value_lookup_string(result, "kind")),
               "file");
  FlValue* metadata = fl_value_lookup_string(result, "metadata");
  ASSERT_NE(metadata, nullptr);
  ASSERT_EQ(fl_value_get_type(metadata), FL_VALUE_TYPE_MAP);
  EXPECT_EQ(fl_value_get_int(fl_value_lookup_string(metadata, "size")), 11);

  g_unlink(path);
}

TEST(FilegatePlugin, WriteReplaceTruncatesFile) {
  g_autofree gchar* path = nullptr;
  g_autoptr(GError) error = nullptr;
  int fd = g_file_open_tmp("filegate-write-XXXXXX", &path, &error);
  ASSERT_GE(fd, 0);
  ASSERT_EQ(error, nullptr);

  const char initial[] = "hello";
  ASSERT_EQ(write(fd, initial, sizeof(initial) - 1),
            static_cast<ssize_t>(sizeof(initial) - 1));
  close(fd);

  const uint8_t bytes[] = {'o', 'k'};
  g_autoptr(FlValue) arguments = fl_value_new_map();
  fl_value_set_string_take(arguments, "path", fl_value_new_string(path));
  fl_value_set_string_take(
      arguments, "bytes",
      fl_value_new_uint8_list(bytes, sizeof(bytes) / sizeof(uint8_t)));
  fl_value_set_string_take(arguments, "mode", fl_value_new_string("replace"));

  g_autoptr(FlMethodResponse) response = filegate_write_file(arguments);
  ASSERT_NE(response, nullptr);
  ASSERT_TRUE(FL_IS_METHOD_SUCCESS_RESPONSE(response));

  g_autofree gchar* contents = ReadTextFile(path);
  ASSERT_NE(contents, nullptr);
  EXPECT_STREQ(contents, "ok");

  g_unlink(path);
}

}  // namespace test
}  // namespace filegate
