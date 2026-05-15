#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>

#include <memory>
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

}  // namespace

TEST(FilegatePlugin, GetFileSizeMissingPathReturnsInvalidArgs) {
  FilegatePlugin plugin;
  std::string error_code;

  plugin.HandleMethodCall(
      MethodCall("getFileSize", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          nullptr,
          [&error_code](const std::string& code, const std::string& message,
                        const EncodableValue* details) { error_code = code; },
          nullptr));

  EXPECT_EQ(error_code, "invalid_args");
}

TEST(FilegatePlugin, PickMixedModeReturnsUnsupportedMode) {
  FilegatePlugin plugin;
  std::string error_code;
  EncodableMap arguments = {
      {EncodableValue("selectionMode"), EncodableValue("filesAndDirectories")},
  };

  plugin.HandleMethodCall(
      MethodCall("pick", std::make_unique<EncodableValue>(arguments)),
      std::make_unique<MethodResultFunctions<>>(
          nullptr,
          [&error_code](const std::string& code, const std::string& message,
                        const EncodableValue* details) { error_code = code; },
          nullptr));

  EXPECT_EQ(error_code, "unsupported_mode");
}

}  // namespace test
}  // namespace filegate
