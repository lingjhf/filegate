#include "filegate_plugin.h"

#include <windows.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <cstring>
#include <exception>
#include <filesystem>
#include <memory>
#include <string>
#include <system_error>
#include <variant>
#include <vector>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

namespace filegate {
namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;
namespace fs = std::filesystem;

constexpr char kInvalidArgs[] = "invalid_args";
constexpr char kNotAFile[] = "not_a_file";
constexpr char kPathNotFound[] = "path_not_found";
constexpr char kUnsupportedMode[] = "unsupported_mode";
constexpr char kEnumerationFailed[] = "enumeration_failed";

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  if (size <= 0) {
    return std::wstring();
  }
  std::wstring result(size - 1, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, result.data(), size);
  return result;
}

const EncodableMap* GetArgumentsMap(const EncodableValue* arguments) {
  if (arguments == nullptr) {
    return nullptr;
  }
  return std::get_if<EncodableMap>(arguments);
}

const std::string* LookupString(const EncodableMap* map, const char* key) {
  if (map == nullptr) {
    return nullptr;
  }
  auto iterator = map->find(EncodableValue(key));
  if (iterator == map->end()) {
    return nullptr;
  }
  return std::get_if<std::string>(&iterator->second);
}

bool LookupBool(const EncodableMap* map, const char* key, bool fallback) {
  if (map == nullptr) {
    return fallback;
  }
  auto iterator = map->find(EncodableValue(key));
  if (iterator == map->end()) {
    return fallback;
  }
  const bool* value = std::get_if<bool>(&iterator->second);
  return value != nullptr ? *value : fallback;
}

std::vector<std::string> LookupExtensions(const EncodableMap* map) {
  std::vector<std::string> extensions;
  if (map == nullptr) {
    return extensions;
  }
  auto iterator = map->find(EncodableValue("allowedExtensions"));
  if (iterator == map->end()) {
    return extensions;
  }
  const EncodableList* list = std::get_if<EncodableList>(&iterator->second);
  if (list == nullptr) {
    return extensions;
  }
  for (const EncodableValue& item : *list) {
    const std::string* extension = std::get_if<std::string>(&item);
    if (extension != nullptr && !extension->empty()) {
      extensions.push_back(*extension);
    }
  }
  return extensions;
}

bool MatchesAllowedExtensions(const fs::path& path,
                              const std::vector<std::string>& extensions) {
  if (extensions.empty()) {
    return true;
  }
  std::string path_extension = path.extension().u8string();
  if (!path_extension.empty() && path_extension.front() == '.') {
    path_extension.erase(path_extension.begin());
  }
  for (const std::string& extension : extensions) {
    if (_stricmp(path_extension.c_str(), extension.c_str()) == 0) {
      return true;
    }
  }
  return false;
}

EncodableValue SerializeFileEntry(const fs::path& path,
                                  const std::string& relative_path = "") {
  const std::string name = path.filename().u8string();
  return EncodableValue(EncodableMap{
      {EncodableValue("path"), EncodableValue(path.u8string())},
      {EncodableValue("name"), EncodableValue(name)},
      {EncodableValue("kind"), EncodableValue("file")},
      {EncodableValue("relativePath"),
       EncodableValue(relative_path.empty() ? name : relative_path)},
  });
}

void AppendDirectoryFiles(EncodableList* entries,
                          const fs::path& directory,
                          bool recursive,
                          const std::vector<std::string>& extensions) {
  const std::string root_name = directory.filename().u8string();
  if (recursive) {
    for (const fs::directory_entry& entry :
         fs::recursive_directory_iterator(directory)) {
      if (!entry.is_regular_file()) {
        continue;
      }
      if (!MatchesAllowedExtensions(entry.path(), extensions)) {
        continue;
      }
      std::string relative =
          (fs::path(root_name) / fs::relative(entry.path(), directory))
              .u8string();
      entries->push_back(SerializeFileEntry(entry.path(), relative));
    }
    return;
  }

  for (const fs::directory_entry& entry : fs::directory_iterator(directory)) {
    if (!entry.is_regular_file()) {
      continue;
    }
    if (!MatchesAllowedExtensions(entry.path(), extensions)) {
      continue;
    }
    std::string relative = (fs::path(root_name) / entry.path().filename())
                               .u8string();
    entries->push_back(SerializeFileEntry(entry.path(), relative));
  }
}

std::wstring BuildFilterPattern(const std::vector<std::string>& extensions) {
  std::wstring pattern;
  for (size_t index = 0; index < extensions.size(); index++) {
    if (index > 0) {
      pattern += L";";
    }
    pattern += L"*.";
    pattern += Utf8ToWide(extensions[index]);
  }
  return pattern;
}

}  // namespace

// static
void FilegatePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "filegate",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<FilegatePlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

FilegatePlugin::FilegatePlugin() {}

FilegatePlugin::~FilegatePlugin() {}

void FilegatePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("pick") == 0) {
    Pick(method_call.arguments(), std::move(result));
  } else if (method_call.method_name().compare("getFileSize") == 0) {
    GetFileSize(method_call.arguments(), std::move(result));
  } else {
    result->NotImplemented();
  }
}

void FilegatePlugin::GetFileSize(
    const flutter::EncodableValue* arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const EncodableMap* map = GetArgumentsMap(arguments);
  const std::string* path_value = LookupString(map, "path");
  if (path_value == nullptr || path_value->empty()) {
    result->Error(kInvalidArgs, "A non-empty file path is required.");
    return;
  }

  std::error_code error;
  fs::path path = fs::u8path(*path_value);
  if (!fs::exists(path, error)) {
    result->Error(kPathNotFound, "The provided path does not exist.",
                  EncodableValue(*path_value));
    return;
  }
  if (fs::is_directory(path, error)) {
    result->Error(kNotAFile, "The provided path is a directory, not a file.",
                  EncodableValue(*path_value));
    return;
  }
  const auto size = fs::file_size(path, error);
  if (error) {
    result->Error("read_failed", error.message(), EncodableValue(*path_value));
    return;
  }

  result->Success(EncodableValue(static_cast<int64_t>(size)));
}

void FilegatePlugin::Pick(
    const flutter::EncodableValue* arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const EncodableMap* map = GetArgumentsMap(arguments);
  const std::string* selection_mode_value = LookupString(map, "selectionMode");
  const std::string selection_mode =
      selection_mode_value == nullptr ? "filesOnly" : *selection_mode_value;
  if (selection_mode == "filesAndDirectories") {
    result->Error(
        kUnsupportedMode,
        "Windows file open dialog does not provide a single standard picker "
        "for mixed file and directory selection.");
    return;
  }
  const bool directories_only = selection_mode == "directoriesOnly";
  if (!directories_only && selection_mode != "filesOnly") {
    result->Error(kInvalidArgs, "Unknown selection mode.");
    return;
  }

  HRESULT init_result =
      CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  const bool should_uninitialize = SUCCEEDED(init_result);
  if (FAILED(init_result) && init_result != RPC_E_CHANGED_MODE) {
    result->Error("picker_failed", "Unable to initialize COM.");
    return;
  }

  ComPtr<IFileOpenDialog> dialog;
  HRESULT hr = CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog));
  if (FAILED(hr)) {
    if (should_uninitialize) {
      CoUninitialize();
    }
    result->Error("picker_failed", "Unable to create the Windows file dialog.");
    return;
  }

  DWORD options = 0;
  dialog->GetOptions(&options);
  options |= FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST;
  if (directories_only) {
    options |= FOS_PICKFOLDERS;
  } else {
    options |= FOS_FILEMUSTEXIST;
    if (LookupBool(map, "allowMultiple", false)) {
      options |= FOS_ALLOWMULTISELECT;
    }
  }
  dialog->SetOptions(options);

  const std::string* title = LookupString(map, "title");
  std::wstring title_wide;
  if (title != nullptr && !title->empty()) {
    title_wide = Utf8ToWide(*title);
    dialog->SetTitle(title_wide.c_str());
  }

  const std::string* initial_directory = LookupString(map, "initialDirectory");
  ComPtr<IShellItem> initial_folder;
  std::wstring initial_directory_wide;
  if (initial_directory != nullptr && !initial_directory->empty()) {
    initial_directory_wide = Utf8ToWide(*initial_directory);
    if (SUCCEEDED(SHCreateItemFromParsingName(
            initial_directory_wide.c_str(), nullptr,
            IID_PPV_ARGS(&initial_folder)))) {
      dialog->SetFolder(initial_folder.Get());
    }
  }

  std::vector<std::string> extensions = LookupExtensions(map);
  std::wstring filter_pattern = BuildFilterPattern(extensions);
  const COMDLG_FILTERSPEC filters[] = {
      {L"Allowed files", filter_pattern.c_str()},
      {L"All files", L"*.*"},
  };
  if (!directories_only && !extensions.empty()) {
    dialog->SetFileTypes(2, filters);
  }

  hr = dialog->Show(nullptr);
  if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
    if (should_uninitialize) {
      CoUninitialize();
    }
    result->Success();
    return;
  }
  if (FAILED(hr)) {
    if (should_uninitialize) {
      CoUninitialize();
    }
    result->Error("picker_failed", "Windows file dialog failed.");
    return;
  }

  EncodableList entries;
  try {
    if (directories_only) {
      ComPtr<IShellItem> item;
      hr = dialog->GetResult(&item);
      if (SUCCEEDED(hr)) {
        PWSTR raw_path = nullptr;
        if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &raw_path))) {
          fs::path directory = fs::path(raw_path);
          CoTaskMemFree(raw_path);
          AppendDirectoryFiles(&entries, directory,
                               LookupBool(map, "recursive", false),
                               extensions);
        }
      }
    } else {
      ComPtr<IShellItemArray> results;
      hr = dialog->GetResults(&results);
      if (SUCCEEDED(hr)) {
        DWORD count = 0;
        results->GetCount(&count);
        for (DWORD index = 0; index < count; index++) {
          ComPtr<IShellItem> item;
          if (FAILED(results->GetItemAt(index, &item))) {
            continue;
          }
          PWSTR raw_path = nullptr;
          if (FAILED(item->GetDisplayName(SIGDN_FILESYSPATH, &raw_path))) {
            continue;
          }
          fs::path path = fs::path(raw_path);
          CoTaskMemFree(raw_path);
          if (MatchesAllowedExtensions(path, extensions)) {
            entries.push_back(SerializeFileEntry(path));
          }
        }
      }
    }
  } catch (const std::exception& error) {
    if (should_uninitialize) {
      CoUninitialize();
    }
    result->Error(kEnumerationFailed, error.what());
    return;
  }

  if (should_uninitialize) {
    CoUninitialize();
  }
  result->Success(EncodableValue(entries));
}

}  // namespace filegate
