#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>

#include <filesystem>
#include <fstream>
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

}  // namespace test
}  // namespace filegate
