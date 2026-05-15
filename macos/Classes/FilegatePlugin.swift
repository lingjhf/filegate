import Cocoa
import FlutterMacOS

public class FilegatePlugin: NSObject, FlutterPlugin {
  private let messenger: FlutterBinaryMessenger
  private let methodChannel: FlutterMethodChannel
  private var readChannels: [String: FlutterEventChannel] = [:]
  private var readHandlers: [String: FileReadStreamHandler] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FilegatePlugin(binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(instance, channel: instance.methodChannel)
  }

  init(binaryMessenger: FlutterBinaryMessenger) {
    messenger = binaryMessenger
    methodChannel = FlutterMethodChannel(name: "filegate", binaryMessenger: binaryMessenger)
    super.init()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pick":
      pick(arguments: call.arguments as? [String: Any], result: result)
    case "getFileSize":
      getFileSize(arguments: call.arguments as? [String: Any], result: result)
    case "startRead":
      startRead(arguments: call.arguments as? [String: Any], result: result)
    case "cancelRead":
      cancelRead(arguments: call.arguments as? [String: Any], result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func getFileSize(arguments: [String: Any]?, result: @escaping FlutterResult) {
    guard let path = arguments?["path"] as? String, !path.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "A non-empty file path is required.", details: nil))
      return
    }

    var isDirectory = ObjCBool(false)
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
      result(FlutterError(code: "path_not_found", message: "The provided path does not exist.", details: path))
      return
    }

    guard !isDirectory.boolValue else {
      result(FlutterError(code: "not_a_file", message: "The provided path is a directory, not a file.", details: path))
      return
    }

    guard FileManager.default.isReadableFile(atPath: path) else {
      result(FlutterError(code: "permission_denied", message: "The provided path is not readable.", details: path))
      return
    }

    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: path)
      result((attributes[.size] as? NSNumber)?.intValue)
    } catch {
      result(FlutterError(code: "read_failed", message: error.localizedDescription, details: path))
    }
  }

  private func pick(arguments: [String: Any]?, result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      let selectionMode = arguments?["selectionMode"] as? String ?? "filesOnly"
      let allowMultiple = arguments?["allowMultiple"] as? Bool ?? false
      let recursive = arguments?["recursive"] as? Bool ?? false
      let allowedExtensions = arguments?["allowedExtensions"] as? [String] ?? []
      let title = arguments?["title"] as? String
      let initialDirectory = arguments?["initialDirectory"] as? String

      let panel = NSOpenPanel()
      panel.canChooseFiles = selectionMode != "directoriesOnly"
      panel.canChooseDirectories = selectionMode != "filesOnly"
      panel.allowsMultipleSelection = allowMultiple
      panel.canCreateDirectories = false

      if let title, !title.isEmpty {
        panel.title = title
      }

      if let initialDirectory, !initialDirectory.isEmpty {
        panel.directoryURL = URL(fileURLWithPath: initialDirectory, isDirectory: true)
      }

      if !allowedExtensions.isEmpty, selectionMode != "directoriesOnly" {
        panel.allowedFileTypes = allowedExtensions
      }

      guard panel.runModal() == .OK else {
        result(nil)
        return
      }

      do {
        let entries = try self.resolvePickedEntries(
          urls: panel.urls,
          recursive: recursive,
          allowedExtensions: allowedExtensions
        )
        result(entries)
      } catch let error as FilegateError {
        result(FlutterError(code: error.code, message: error.message, details: error.details))
      } catch {
        result(FlutterError(code: "enumeration_failed", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func startRead(arguments: [String: Any]?, result: @escaping FlutterResult) {
    guard let path = arguments?["path"] as? String, !path.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "A non-empty file path is required.", details: nil))
      return
    }

    let chunkSize = arguments?["chunkSize"] as? Int ?? 64 * 1024
    guard chunkSize > 0 else {
      result(FlutterError(code: "invalid_args", message: "chunkSize must be greater than zero.", details: nil))
      return
    }
    let start = arguments?["start"] as? Int ?? 0
    guard start >= 0 else {
      result(FlutterError(code: "invalid_args", message: "start must not be negative.", details: nil))
      return
    }

    var isDirectory = ObjCBool(false)
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
      result(FlutterError(code: "path_not_found", message: "The provided path does not exist.", details: path))
      return
    }

    guard !isDirectory.boolValue else {
      result(FlutterError(code: "not_a_file", message: "The provided path is a directory, not a file.", details: path))
      return
    }

    guard FileManager.default.isReadableFile(atPath: path) else {
      result(FlutterError(code: "permission_denied", message: "The provided path is not readable.", details: path))
      return
    }

    let streamId = UUID().uuidString
    let channel = FlutterEventChannel(name: "filegate/read/\(streamId)", binaryMessenger: messenger)
    let handler = FileReadStreamHandler(path: path, start: start, chunkSize: chunkSize) { [weak self] in
      DispatchQueue.main.async {
        self?.releaseReadStream(streamId)
      }
    }

    channel.setStreamHandler(handler)
    readChannels[streamId] = channel
    readHandlers[streamId] = handler
    result(streamId)
  }

  private func cancelRead(arguments: [String: Any]?, result: @escaping FlutterResult) {
    guard let streamId = arguments?["streamId"] as? String, !streamId.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "A non-empty streamId is required.", details: nil))
      return
    }

    cancelReadStream(streamId)
    result(nil)
  }

  private func cancelReadStream(_ streamId: String) {
    readHandlers.removeValue(forKey: streamId)?.cancel()
    readChannels.removeValue(forKey: streamId)?.setStreamHandler(nil)
  }

  private func releaseReadStream(_ streamId: String) {
    readHandlers.removeValue(forKey: streamId)
    readChannels.removeValue(forKey: streamId)?.setStreamHandler(nil)
  }

  private static func serializeEntry(_ url: URL, relativePath: String? = nil) -> [String: Any] {
    let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .nameKey])
    let isDirectory = resourceValues?.isDirectory ?? false
    let name = resourceValues?.name ?? url.lastPathComponent

    return [
      "path": url.path,
      "name": name,
      "kind": isDirectory ? "directory" : "file",
      "relativePath": relativePath ?? name,
    ]
  }

  private func resolvePickedEntries(
    urls: [URL],
    recursive: Bool,
    allowedExtensions: [String]
  ) throws -> [[String: Any]] {
    var entries: [[String: Any]] = []
    for url in urls {
      let values = try url.resourceValues(forKeys: [.isDirectoryKey])
      if values.isDirectory == true {
        entries.append(contentsOf: try expandDirectory(at: url, recursive: recursive, allowedExtensions: allowedExtensions))
      } else if Self.matchesAllowedExtensions(url: url, allowedExtensions: allowedExtensions) {
        entries.append(Self.serializeEntry(url))
      }
    }
    return entries
  }

  private func expandDirectory(
    at directoryURL: URL,
    recursive: Bool,
    allowedExtensions: [String]
  ) throws -> [[String: Any]] {
    let keys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
    let rootName = directoryURL.lastPathComponent
    if recursive {
      guard let enumerator = FileManager.default.enumerator(
        at: directoryURL,
        includingPropertiesForKeys: keys,
        options: [.skipsPackageDescendants, .skipsHiddenFiles]
      ) else {
        throw FilegateError(code: "enumeration_failed", message: "Unable to enumerate the selected directory.", details: directoryURL.path)
      }

      var entries: [[String: Any]] = []
      for case let fileURL as URL in enumerator {
        let values = try fileURL.resourceValues(forKeys: Set(keys))
        if values.isDirectory == true {
          continue
        }
        if Self.matchesAllowedExtensions(url: fileURL, allowedExtensions: allowedExtensions) {
          let nestedPath = fileURL.path.replacingOccurrences(of: directoryURL.path + "/", with: "")
          entries.append(Self.serializeEntry(fileURL, relativePath: rootName + "/" + nestedPath))
        }
      }
      return entries
    }

    let urls = try FileManager.default.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: keys,
      options: [.skipsPackageDescendants, .skipsHiddenFiles]
    )

    return try urls.compactMap { fileURL in
      let values = try fileURL.resourceValues(forKeys: Set(keys))
      guard values.isDirectory != true else {
        return nil
      }
      guard Self.matchesAllowedExtensions(url: fileURL, allowedExtensions: allowedExtensions) else {
        return nil
      }
      return Self.serializeEntry(fileURL, relativePath: rootName + "/" + fileURL.lastPathComponent)
    }
  }

  private static func matchesAllowedExtensions(url: URL, allowedExtensions: [String]) -> Bool {
    guard !allowedExtensions.isEmpty else {
      return true
    }

    let pathExtension = url.pathExtension.lowercased()
    return allowedExtensions.contains { $0.lowercased() == pathExtension }
  }
}

private struct FilegateError: Error {
  let code: String
  let message: String
  let details: Any?
}

private final class FileReadStreamHandler: NSObject, FlutterStreamHandler {
  private let path: String
  private let start: Int
  private let chunkSize: Int
  private let queue = DispatchQueue(label: "filegate.read", qos: .utility)
  private let lock = NSLock()
  private let onDispose: () -> Void

  private var fileHandle: FileHandle?
  private var eventSink: FlutterEventSink?
  private var isCancelled = false
  private var isDisposed = false

  init(path: String, start: Int, chunkSize: Int, onDispose: @escaping () -> Void) {
    self.path = path
    self.start = start
    self.chunkSize = chunkSize
    self.onDispose = onDispose
    super.init()
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    lock.lock()
    defer { lock.unlock() }

    guard eventSink == nil else {
      return FlutterError(code: "stream_active", message: "This file stream is already active.", details: nil)
    }

    guard let handle = FileHandle(forReadingAtPath: path) else {
      return FlutterError(code: "read_open_failed", message: "Unable to open the provided file path.", details: path)
    }

    do {
      try handle.seek(toOffset: UInt64(start))
    } catch {
      try? handle.close()
      return FlutterError(code: "read_failed", message: error.localizedDescription, details: path)
    }

    fileHandle = handle
    eventSink = events
    isCancelled = false

    queue.async { [weak self] in
      self?.readLoop()
    }

    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    cancel()
    return nil
  }

  func cancel() {
    let handle = withLock { () -> FileHandle? in
      isCancelled = true
      let currentHandle = fileHandle
      fileHandle = nil
      eventSink = nil
      return currentHandle
    }

    try? handle?.close()
    disposeIfNeeded()
  }

  private func readLoop() {
    guard let handle = withLock({ fileHandle }) else {
      disposeIfNeeded()
      return
    }

    defer {
      try? handle.close()
      withLock { () -> Void in
        fileHandle = nil
      }
    }

    while true {
      if withLock({ isCancelled }) {
        return
      }

      do {
        let data = handle.readData(ofLength: chunkSize)
        if !data.isEmpty {
          guard let sink = withLock({ isCancelled ? nil : eventSink }) else {
            return
          }
          DispatchQueue.main.async {
            sink(FlutterStandardTypedData(bytes: data))
          }
          continue
        }
      }

      guard let sink = withLock({ isCancelled ? nil : eventSink }) else {
        return
      }
      DispatchQueue.main.async { [weak self] in
        sink(FlutterEndOfEventStream)
        self?.finishStream()
      }
      return
    }
  }

  private func emitError(_ error: Error) {
    guard let sink = withLock({ isCancelled ? nil : eventSink }) else {
      return
    }

    DispatchQueue.main.async { [weak self] in
      sink(FlutterError(code: "read_failed", message: error.localizedDescription, details: self?.path))
      self?.finishStream()
    }
  }

  private func finishStream() {
    withLock { () -> Void in
      fileHandle = nil
      eventSink = nil
    }
    disposeIfNeeded()
  }

  private func disposeIfNeeded() {
    let shouldDispose = withLock { () -> Bool in
      guard !isDisposed else {
        return false
      }
      isDisposed = true
      return true
    }

    if shouldDispose {
      onDispose()
    }
  }

  private func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}
