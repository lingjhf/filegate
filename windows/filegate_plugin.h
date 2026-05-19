#ifndef FLUTTER_PLUGIN_FILEGATE_PLUGIN_H_
#define FLUTTER_PLUGIN_FILEGATE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <fstream>
#include <memory>
#include <string>
#include <unordered_map>
#include <utility>

namespace filegate {

class FilegatePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  FilegatePlugin();

  virtual ~FilegatePlugin();

  // Disallow copy and assign.
  FilegatePlugin(const FilegatePlugin&) = delete;
  FilegatePlugin& operator=(const FilegatePlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  void Pick(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void Save(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void Write(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void StartWrite(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void WriteChunk(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void FinishWrite(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void CancelWrite(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void GetFileSize(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  struct WriteSession {
    explicit WriteSession(std::string path) : path(std::move(path)) {}

    std::string path;
    std::ofstream file;
  };

  std::unordered_map<std::string, std::unique_ptr<WriteSession>>
      write_sessions_;
};

}  // namespace filegate

#endif  // FLUTTER_PLUGIN_FILEGATE_PLUGIN_H_
