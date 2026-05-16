import Cocoa
import CoreServices
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
      guard ["filesOnly", "directoriesOnly", "filesAndDirectories"].contains(selectionMode) else {
        result(FlutterError(code: "invalid_args", message: "Unknown selection mode.", details: selectionMode))
        return
      }
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

      let normalizedExtensions = Self.normalizeExtensions(allowedExtensions)
      if !normalizedExtensions.isEmpty, selectionMode != "directoriesOnly" {
        panel.allowedFileTypes = normalizedExtensions
      }

      guard panel.runModal() == .OK else {
        result(nil)
        return
      }

      do {
        let entries = try self.resolvePickedEntries(
          urls: panel.urls,
          selectionMode: selectionMode,
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
    let end = arguments?["end"] as? Int
    if let end, end < start {
      result(FlutterError(code: "invalid_args", message: "end must be greater than or equal to start.", details: nil))
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
    let handler = FileReadStreamHandler(
      path: path,
      start: start,
      chunkSize: chunkSize,
      maxBytes: end.map { $0 - start }
    ) { [weak self] in
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

    var entry: [String: Any] = [
      "path": url.path,
      "name": name,
      "kind": isDirectory ? "directory" : "file",
      "relativePath": relativePath ?? name,
    ]
    if !isDirectory {
      entry["metadata"] = Self.metadataForFile(url)
    }
    return entry
  }

  private func resolvePickedEntries(
    urls: [URL],
    selectionMode: String,
    recursive: Bool,
    allowedExtensions: [String]
  ) throws -> [[String: Any]] {
    var entries: [[String: Any]] = []
    for url in urls {
      let values = try url.resourceValues(forKeys: [.isDirectoryKey])
      if values.isDirectory == true {
        if selectionMode == "filesAndDirectories" {
          entries.append(Self.serializeEntry(url))
        } else {
          entries.append(contentsOf: try expandDirectory(at: url, recursive: recursive, allowedExtensions: allowedExtensions))
        }
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
          entries.append(Self.serializeEntry(fileURL, relativePath: nestedPath))
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
      return Self.serializeEntry(fileURL, relativePath: fileURL.lastPathComponent)
    }
  }

  private static func matchesAllowedExtensions(url: URL, allowedExtensions: [String]) -> Bool {
    let normalizedExtensions = normalizeExtensions(allowedExtensions)
    guard !normalizedExtensions.isEmpty else {
      return true
    }

    let pathExtension = url.pathExtension.lowercased()
    return normalizedExtensions.contains(pathExtension)
  }

  private static func normalizeExtensions(_ extensions: [String]) -> [String] {
    var seen = Set<String>()
    var normalized: [String] = []
    for value in extensions {
      let extensionValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        .lowercased()
      if !extensionValue.isEmpty && seen.insert(extensionValue).inserted {
        normalized.append(extensionValue)
      }
    }
    return normalized
  }

  private static func metadataForFile(_ url: URL) -> [String: Any] {
    var metadata: [String: Any] = [:]
    let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
    if let size = values?.fileSize, size >= 0 {
      metadata["size"] = size
    }
    if let modifiedAt = values?.contentModificationDate {
      metadata["modifiedAt"] = Int(modifiedAt.timeIntervalSince1970 * 1000)
    }
    if let mimeType = mimeTypeForFile(url) {
      metadata["mimeType"] = mimeType
    }
    return metadata
  }

  private static func mimeTypeForFile(_ url: URL) -> String? {
    let pathExtension = url.pathExtension
    guard !pathExtension.isEmpty,
          let unmanagedType = UTTypeCreatePreferredIdentifierForTag(
            kUTTagClassFilenameExtension,
            pathExtension as CFString,
            nil
          ) else {
      return nil
    }

    let type = unmanagedType.takeRetainedValue()
    return UTTypeCopyPreferredTagWithClass(type, kUTTagClassMIMEType)?.takeRetainedValue() as String?
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
  private let maxBytes: Int?
  private let queue = DispatchQueue(label: "filegate.read", qos: .utility)
  private let lock = NSLock()
  private let onDispose: () -> Void

  private var fileHandle: FileHandle?
  private var eventSink: FlutterEventSink?
  private var isCancelled = false
  private var isDisposed = false

  init(path: String, start: Int, chunkSize: Int, maxBytes: Int?, onDispose: @escaping () -> Void) {
    self.path = path
    self.start = start
    self.chunkSize = chunkSize
    self.maxBytes = maxBytes
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
      DispatchQueue.main.async { [weak self] in
        self?.disposeIfNeeded()
      }
      return FlutterError(code: "read_open_failed", message: "Unable to open the provided file path.", details: path)
    }

    do {
      try handle.seek(toOffset: UInt64(start))
    } catch {
      try? handle.close()
      DispatchQueue.main.async { [weak self] in
        self?.disposeIfNeeded()
      }
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

    var remainingBytes = maxBytes
    while true {
      if withLock({ isCancelled }) {
        return
      }
      if let remainingBytes, remainingBytes <= 0 {
        guard let sink = withLock({ isCancelled ? nil : eventSink }) else {
          return
        }
        DispatchQueue.main.async { [weak self] in
          sink(FlutterEndOfEventStream)
          self?.finishStream()
        }
        return
      }

      do {
        let currentChunkSize = remainingBytes.map { min(chunkSize, $0) } ?? chunkSize
        let data = handle.readData(ofLength: currentChunkSize)
        if !data.isEmpty {
          if let currentRemainingBytes = remainingBytes {
            remainingBytes = currentRemainingBytes - data.count
          }
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
