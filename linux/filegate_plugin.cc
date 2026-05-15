#include "include/filegate/filegate_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <glib/gstdio.h>
#include <gtk/gtk.h>

#include <cstring>
#include <string>
#include <sys/stat.h>
#include <vector>

#include "filegate_plugin_private.h"

#define FILEGATE_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), filegate_plugin_get_type(), \
                              FilegatePlugin))

struct _FilegatePlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(FilegatePlugin, filegate_plugin, g_object_get_type())

namespace {

constexpr char kInvalidArgs[] = "invalid_args";
constexpr char kNotAFile[] = "not_a_file";
constexpr char kPathNotFound[] = "path_not_found";
constexpr char kUnsupportedMode[] = "unsupported_mode";
constexpr char kEnumerationFailed[] = "enumeration_failed";

const char* lookup_string(FlValue* map, const char* key) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return nullptr;
  }
  return fl_value_get_string(value);
}

bool lookup_bool(FlValue* map, const char* key, bool fallback) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_BOOL) {
    return fallback;
  }
  return fl_value_get_bool(value);
}

std::vector<std::string> lookup_extensions(FlValue* map) {
  std::vector<std::string> extensions;
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return extensions;
  }
  FlValue* value = fl_value_lookup_string(map, "allowedExtensions");
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_LIST) {
    return extensions;
  }
  for (size_t index = 0; index < fl_value_get_length(value); index++) {
    FlValue* item = fl_value_get_list_value(value, index);
    if (item != nullptr && fl_value_get_type(item) == FL_VALUE_TYPE_STRING) {
      const char* extension = fl_value_get_string(item);
      if (extension != nullptr && strlen(extension) > 0) {
        extensions.emplace_back(extension);
      }
    }
  }
  return extensions;
}

bool matches_allowed_extensions(const char* path,
                                const std::vector<std::string>& extensions) {
  if (extensions.empty()) {
    return true;
  }
  const char* extension = strrchr(path, '.');
  if (extension == nullptr || strlen(extension) <= 1) {
    return false;
  }
  g_autofree gchar* lower_extension = g_ascii_strdown(extension + 1, -1);
  for (const std::string& allowed : extensions) {
    g_autofree gchar* lower_allowed = g_ascii_strdown(allowed.c_str(), -1);
    if (strcmp(lower_extension, lower_allowed) == 0) {
      return true;
    }
  }
  return false;
}

FlValue* serialize_file_entry(const char* path, const char* relative_path) {
  g_autofree gchar* basename = g_path_get_basename(path);
  FlValue* entry = fl_value_new_map();
  fl_value_set_string_take(entry, "path", fl_value_new_string(path));
  fl_value_set_string_take(entry, "name", fl_value_new_string(basename));
  fl_value_set_string_take(entry, "kind", fl_value_new_string("file"));
  fl_value_set_string_take(
      entry, "relativePath",
      fl_value_new_string(relative_path != nullptr ? relative_path : basename));
  return entry;
}

bool append_directory_files(FlValue* entries,
                            const char* directory_path,
                            const char* relative_prefix,
                            bool recursive,
                            const std::vector<std::string>& extensions,
                            GError** error) {
  g_autoptr(GDir) directory = g_dir_open(directory_path, 0, error);
  if (directory == nullptr) {
    return false;
  }

  const gchar* child_name = nullptr;
  while ((child_name = g_dir_read_name(directory)) != nullptr) {
    g_autofree gchar* child_path =
        g_build_filename(directory_path, child_name, nullptr);
    g_autofree gchar* child_relative =
        g_build_filename(relative_prefix, child_name, nullptr);

    if (g_file_test(child_path, G_FILE_TEST_IS_DIR)) {
      if (recursive && !append_directory_files(entries, child_path,
                                               child_relative, true,
                                               extensions, error)) {
        return false;
      }
      continue;
    }

    if (!g_file_test(child_path, G_FILE_TEST_IS_REGULAR)) {
      continue;
    }
    if (!matches_allowed_extensions(child_path, extensions)) {
      continue;
    }
    fl_value_append_take(entries,
                         serialize_file_entry(child_path, child_relative));
  }

  return true;
}

void add_extension_filters(GtkFileChooser* chooser,
                           const std::vector<std::string>& extensions) {
  if (extensions.empty()) {
    return;
  }

  GtkFileFilter* filter = gtk_file_filter_new();
  gtk_file_filter_set_name(filter, "Allowed files");
  for (const std::string& extension : extensions) {
    g_autofree gchar* pattern = g_strdup_printf("*.%s", extension.c_str());
    gtk_file_filter_add_pattern(filter, pattern);
  }
  gtk_file_chooser_add_filter(chooser, filter);

  GtkFileFilter* all_filter = gtk_file_filter_new();
  gtk_file_filter_set_name(all_filter, "All files");
  gtk_file_filter_add_pattern(all_filter, "*");
  gtk_file_chooser_add_filter(chooser, all_filter);
}

}  // namespace

FlMethodResponse* filegate_get_file_size(FlValue* arguments) {
  const char* path = lookup_string(arguments, "path");
  if (path == nullptr || strlen(path) == 0) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        kInvalidArgs, "A non-empty file path is required.", nullptr));
  }

  GStatBuf stat_buffer = {};
  if (g_stat(path, &stat_buffer) != 0) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        kPathNotFound, "The provided path does not exist.", nullptr));
  }
  if (S_ISDIR(stat_buffer.st_mode)) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        kNotAFile, "The provided path is a directory, not a file.", nullptr));
  }

  g_autoptr(FlValue) result = fl_value_new_int(stat_buffer.st_size);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

FlMethodResponse* filegate_pick_files(FlValue* arguments) {
  const char* selection_mode = lookup_string(arguments, "selectionMode");
  if (selection_mode == nullptr) {
    selection_mode = "filesOnly";
  }
  if (strcmp(selection_mode, "filesAndDirectories") == 0) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        kUnsupportedMode,
        "Linux GTK file chooser does not provide a single standard picker for "
        "mixed file and directory selection.",
        nullptr));
  }

  const bool directories_only = strcmp(selection_mode, "directoriesOnly") == 0;
  if (!directories_only && strcmp(selection_mode, "filesOnly") != 0) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        kInvalidArgs, "Unknown selection mode.", nullptr));
  }

  const bool allow_multiple = lookup_bool(arguments, "allowMultiple", false);
  const bool recursive = lookup_bool(arguments, "recursive", false);
  const char* title = lookup_string(arguments, "title");
  const char* initial_directory = lookup_string(arguments, "initialDirectory");
  std::vector<std::string> extensions = lookup_extensions(arguments);

  GtkFileChooserAction action =
      directories_only ? GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER
                       : GTK_FILE_CHOOSER_ACTION_OPEN;
  GtkFileChooserNative* dialog = gtk_file_chooser_native_new(
      title != nullptr && strlen(title) > 0 ? title : "Choose files", nullptr,
      action, "_Open", "_Cancel");
  GtkFileChooser* chooser = GTK_FILE_CHOOSER(dialog);
  gtk_file_chooser_set_select_multiple(chooser,
                                       directories_only ? FALSE : allow_multiple);
  if (initial_directory != nullptr && strlen(initial_directory) > 0) {
    gtk_file_chooser_set_current_folder(chooser, initial_directory);
  }
  if (!directories_only) {
    add_extension_filters(chooser, extensions);
  }

  gint response = gtk_native_dialog_run(GTK_NATIVE_DIALOG(dialog));
  if (response != GTK_RESPONSE_ACCEPT) {
    g_object_unref(dialog);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }

  g_autoptr(FlValue) entries = fl_value_new_list();
  if (directories_only) {
    g_autofree gchar* directory_path = gtk_file_chooser_get_filename(chooser);
    if (directory_path == nullptr || strlen(directory_path) == 0) {
      g_object_unref(dialog);
      return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
    g_autofree gchar* root_name = g_path_get_basename(directory_path);
    g_autoptr(GError) error = nullptr;
    if (!append_directory_files(entries, directory_path, root_name, recursive,
                                extensions, &error)) {
      g_object_unref(dialog);
      return FL_METHOD_RESPONSE(fl_method_error_response_new(
          kEnumerationFailed,
          error != nullptr ? error->message
                           : "Unable to enumerate the selected directory.",
          nullptr));
    }
  } else {
    GSList* filenames = gtk_file_chooser_get_filenames(chooser);
    for (GSList* item = filenames; item != nullptr; item = item->next) {
      gchar* path = static_cast<gchar*>(item->data);
      if (matches_allowed_extensions(path, extensions)) {
        fl_value_append_take(entries, serialize_file_entry(path, nullptr));
      }
      g_free(path);
    }
    g_slist_free(filenames);
  }

  g_object_unref(dialog);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(entries));
}

// Called when a method call is received from Flutter.
static void filegate_plugin_handle_method_call(
    FilegatePlugin* self,
    FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* arguments = fl_method_call_get_args(method_call);

  if (strcmp(method, "pick") == 0) {
    response = filegate_pick_files(arguments);
  } else if (strcmp(method, "getFileSize") == 0) {
    response = filegate_get_file_size(arguments);
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void filegate_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(filegate_plugin_parent_class)->dispose(object);
}

static void filegate_plugin_class_init(FilegatePluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = filegate_plugin_dispose;
}

static void filegate_plugin_init(FilegatePlugin* self) {}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  FilegatePlugin* plugin = FILEGATE_PLUGIN(user_data);
  filegate_plugin_handle_method_call(plugin, method_call);
}

void filegate_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  FilegatePlugin* plugin = FILEGATE_PLUGIN(
      g_object_new(filegate_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "filegate",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}
