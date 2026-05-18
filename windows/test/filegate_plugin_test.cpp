#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>

#include <filesystem>
#include <fstream>
#include <iterator>
#include <memory>
#include <optional>
#include <string>
#include <variant>

#include "filegate_plugin.h"

namespace filegate {
namespace test {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResultFunctions;
namespace fs = std::filesystem;

struct MethodCallResult {
  std::optional<EncodableValue> success;
  std::string error_code;
};

MethodCallResult Invoke(FilegatePlugin* plugin,
                        const std::string& method,
                        std::unique_ptr<EncodableValue> arguments) {
  MethodCallResult result;
  plugin->HandleMethodCall(
      MethodCall(method, std::move(arguments)),
      std::make_unique<MethodResultFunctions<>>(
          [&result](const EncodableValue* value) {
            if (value != nullptr) {
              result.success = *value;
            } else {
              result.success = EncodableValue();
            }
          },
          [&result](const std::string& code, const std::string& message,
                    const EncodableValue* details) { result.error_code = code; },
          nullptr));
  return result;
}

std::string ReadTextFile(const fs::path& path) {
  std::ifstream file(path, std::ios::binary);
  return std::string(std::istreambuf_iterator<char>(file),
                     std::istreambuf_iterator<char>());
}

}  // namespace

TEST(FilegatePlugin, GetFileSizeMissingPathReturnsInvalidArgs) {
  FilegatePlugin plugin;

  MethodCallResult result =
      Invoke(&plugin, "getFileSize", std::make_unique<EncodableValue>());

  EXPECT_EQ(result.error_code, "invalid_args");
}

TEST(FilegatePlugin, GetFileSizeReturnsFileSize) {
  FilegatePlugin plugin;
  fs::path path = fs::temp_directory_path() / "filegate_test_size.txt";
  {
    std::ofstream file(path, std::ios::binary);
    file << "hello";
  }

  EncodableMap arguments = {
      {EncodableValue("path"), EncodableValue(path.u8string())},
  };
  MethodCallResult result = Invoke(
      &plugin, "getFileSize", std::make_unique<EncodableValue>(arguments));

  ASSERT_TRUE(result.success.has_value());
  ASSERT_TRUE(std::holds_alternative<int64_t>(*result.success));
  EXPECT_EQ(std::get<int64_t>(*result.success), 5);

  fs::remove(path);
}

TEST(FilegatePlugin, GetFileSizeDirectoryReturnsNotAFile) {
  FilegatePlugin plugin;
  EncodableMap arguments = {
      {EncodableValue("path"),
       EncodableValue(fs::temp_directory_path().u8string())},
  };

  MethodCallResult result = Invoke(
      &plugin, "getFileSize", std::make_unique<EncodableValue>(arguments));

  EXPECT_EQ(result.error_code, "not_a_file");
}

TEST(FilegatePlugin, PickMixedModeReturnsUnsupportedMode) {
  FilegatePlugin plugin;
  EncodableMap arguments = {
      {EncodableValue("selectionMode"), EncodableValue("filesAndDirectories")},
  };

  MethodCallResult result =
      Invoke(&plugin, "pick", std::make_unique<EncodableValue>(arguments));

  EXPECT_EQ(result.error_code, "unsupported_mode");
}

TEST(FilegatePlugin, PickUnknownModeReturnsInvalidArgs) {
  FilegatePlugin plugin;
  EncodableMap arguments = {
      {EncodableValue("selectionMode"), EncodableValue("unknown")},
  };

  MethodCallResult result =
      Invoke(&plugin, "pick", std::make_unique<EncodableValue>(arguments));

  EXPECT_EQ(result.error_code, "invalid_args");
}

TEST(FilegatePlugin, SaveMissingBytesReturnsInvalidArgs) {
  FilegatePlugin plugin;
  EncodableMap arguments = {
      {EncodableValue("suggestedName"), EncodableValue("export.txt")},
  };

  MethodCallResult result =
      Invoke(&plugin, "save", std::make_unique<EncodableValue>(arguments));

  EXPECT_EQ(result.error_code, "invalid_args");
}

TEST(FilegatePlugin, SavePathNameReturnsInvalidArgs) {
  FilegatePlugin plugin;
  EncodableMap arguments = {
      {EncodableValue("bytes"), EncodableValue(std::vector<uint8_t>{1, 2, 3})},
      {EncodableValue("suggestedName"), EncodableValue("nested/export.txt")},
  };

  MethodCallResult result =
      Invoke(&plugin, "save", std::make_unique<EncodableValue>(arguments));

  EXPECT_EQ(result.error_code, "invalid_args");
}

TEST(FilegatePlugin, SaveBlankNameReturnsInvalidArgs) {
  FilegatePlugin plugin;
  EncodableMap arguments = {
      {EncodableValue("bytes"), EncodableValue(std::vector<uint8_t>{1, 2, 3})},
      {EncodableValue("suggestedName"), EncodableValue("   ")},
  };

  MethodCallResult result =
      Invoke(&plugin, "save", std::make_unique<EncodableValue>(arguments));

  EXPECT_EQ(result.error_code, "invalid_args");
}

TEST(FilegatePlugin, WriteMissingPathReturnsInvalidArgs) {
  FilegatePlugin plugin;

  MethodCallResult result =
      Invoke(&plugin, "write", std::make_unique<EncodableValue>());

  EXPECT_EQ(result.error_code, "invalid_args");
}

TEST(FilegatePlugin, WriteMissingBytesReturnsInvalidArgs) {
  FilegatePlugin plugin;
  EncodableMap arguments = {
      {EncodableValue("path"), EncodableValue("C:\\temp\\filegate.txt")},
  };

  MethodCallResult result =
      Invoke(&plugin, "write", std::make_unique<EncodableValue>(arguments));

  EXPECT_EQ(result.error_code, "invalid_args");
}

TEST(FilegatePlugin, WriteUnknownModeReturnsInvalidArgs) {
  FilegatePlugin plugin;
  EncodableMap arguments = {
      {EncodableValue("path"), EncodableValue("C:\\temp\\filegate.txt")},
      {EncodableValue("bytes"), EncodableValue(std::vector<uint8_t>{1})},
      {EncodableValue("mode"), EncodableValue("unknown")},
  };

  MethodCallResult result =
      Invoke(&plugin, "write", std::make_unique<EncodableValue>(arguments));

  EXPECT_EQ(result.error_code, "invalid_args");
}

TEST(FilegatePlugin, WriteMissingFileReturnsPathNotFound) {
  FilegatePlugin plugin;
  fs::path path = fs::temp_directory_path() / "filegate_missing_write.txt";
  fs::remove(path);
  EncodableMap arguments = {
      {EncodableValue("path"), EncodableValue(path.u8string())},
      {EncodableValue("bytes"), EncodableValue(std::vector<uint8_t>{1})},
      {EncodableValue("mode"), EncodableValue("append")},
  };

  MethodCallResult result =
      Invoke(&plugin, "write", std::make_unique<EncodableValue>(arguments));

  EXPECT_EQ(result.error_code, "path_not_found");
}

TEST(FilegatePlugin, WriteDirectoryReturnsNotAFile) {
  FilegatePlugin plugin;
  EncodableMap arguments = {
      {EncodableValue("path"),
       EncodableValue(fs::temp_directory_path().u8string())},
      {EncodableValue("bytes"), EncodableValue(std::vector<uint8_t>{1})},
      {EncodableValue("mode"), EncodableValue("append")},
  };

  MethodCallResult result =
      Invoke(&plugin, "write", std::make_unique<EncodableValue>(arguments));

  EXPECT_EQ(result.error_code, "not_a_file");
}

TEST(FilegatePlugin, WriteAppendAddsBytes) {
  FilegatePlugin plugin;
  fs::path path = fs::temp_directory_path() / "filegate_test_write_append.txt";
  {
    std::ofstream file(path, std::ios::binary | std::ios::trunc);
    file << "hello";
  }
  EncodableMap arguments = {
      {EncodableValue("path"), EncodableValue(path.u8string())},
      {EncodableValue("bytes"),
       EncodableValue(std::vector<uint8_t>{' ', 'w', 'o', 'r', 'l', 'd'})},
      {EncodableValue("mode"), EncodableValue("append")},
  };

  MethodCallResult result =
      Invoke(&plugin, "write", std::make_unique<EncodableValue>(arguments));

  ASSERT_TRUE(result.success.has_value());
  EXPECT_EQ(ReadTextFile(path), "hello world");
  const EncodableMap* entry = std::get_if<EncodableMap>(&*result.success);
  ASSERT_NE(entry, nullptr);
  EXPECT_EQ(std::get<std::string>(entry->at(EncodableValue("path"))),
            path.u8string());
  EXPECT_EQ(std::get<std::string>(entry->at(EncodableValue("kind"))), "file");
  const EncodableMap* metadata =
      std::get_if<EncodableMap>(&entry->at(EncodableValue("metadata")));
  ASSERT_NE(metadata, nullptr);
  EXPECT_EQ(std::get<int64_t>(metadata->at(EncodableValue("size"))), 11);

  fs::remove(path);
}

TEST(FilegatePlugin, WriteReplaceTruncatesFile) {
  FilegatePlugin plugin;
  fs::path path = fs::temp_directory_path() / "filegate_test_write_replace.txt";
  {
    std::ofstream file(path, std::ios::binary | std::ios::trunc);
    file << "hello";
  }
  EncodableMap arguments = {
      {EncodableValue("path"), EncodableValue(path.u8string())},
      {EncodableValue("bytes"), EncodableValue(std::vector<uint8_t>{'o', 'k'})},
      {EncodableValue("mode"), EncodableValue("replace")},
  };

  MethodCallResult result =
      Invoke(&plugin, "write", std::make_unique<EncodableValue>(arguments));

  ASSERT_TRUE(result.success.has_value());
  EXPECT_EQ(ReadTextFile(path), "ok");

  fs::remove(path);
}

}  // namespace test
}  // namespace filegate
