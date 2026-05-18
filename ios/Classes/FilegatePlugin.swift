import Flutter
import MobileCoreServices
import UIKit

public class FilegatePlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate {
  private let messenger: FlutterBinaryMessenger
  private let methodChannel: FlutterMethodChannel
  private var readChannels: [String: FlutterEventChannel] = [:]
  private var readHandlers: [String: FileReadStreamHandler] = [:]
  private var pendingPickResult: FlutterResult?
  private var pendingSaveResult: FlutterResult?
  private var pendingSaveTemporaryDirectoryURL: URL?
  private var pendingSelectionMode = "filesOnly"
  private var pendingPickRecursive = false
  private var pendingAllowedExtensions: [String] = []

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FilegatePlugin(binaryMessenger: registrar.messenger())
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
    case "save":
      save(arguments: call.arguments as? [String: Any], result: result)
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

    let fileURL = resolveURL(from: path)
    let temporaryAccess = fileURL.startAccessingSecurityScopedResource()
    if !temporaryAccess && !FileManager.default.fileExists(atPath: fileURL.path) {
      result(FlutterError(code: "path_not_found", message: "The provided path does not exist.", details: path))
      return
    }
    if !temporaryAccess && !FileManager.default.isReadableFile(atPath: fileURL.path) {
      result(FlutterError(code: "security_scope_failed", message: "Unable to access the selected file in the current session.", details: path))
      return
    }

    defer {
      if temporaryAccess {
        fileURL.stopAccessingSecurityScopedResource()
      }
    }

    do {
      let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
      if values.isDirectory == true {
        result(FlutterError(code: "not_a_file", message: "The provided path is a directory, not a file.", details: path))
        return
      }

      if let fileSize = values.fileSize {
        result(fileSize)
        return
      }

      let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
      result((attributes[.size] as? NSNumber)?.intValue)
    } catch {
      result(FlutterError(code: "path_not_found", message: "The provided path does not exist.", details: path))
    }
  }

  private func pick(arguments: [String: Any]?, result: @escaping FlutterResult) {
    guard pendingPickResult == nil && pendingSaveResult == nil else {
      result(FlutterError(code: "picker_active", message: "Another file picker request is already active.", details: nil))
      return
    }

    guard let presenter = topViewController() else {
      result(FlutterError(code: "no_view_controller", message: "No view controller is available to present the document picker.", details: nil))
      return
    }

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

    let documentTypes = buildDocumentTypes(
      selectionMode: selectionMode,
      allowedExtensions: allowedExtensions
    )

    let picker = UIDocumentPickerViewController(documentTypes: documentTypes, in: .open)
    picker.delegate = self
    picker.allowsMultipleSelection = allowMultiple
    if let title, !title.isEmpty {
      picker.title = title
    }
    if let initialDirectory, !initialDirectory.isEmpty {
      picker.directoryURL = resolveURL(from: initialDirectory)
    }

    pendingPickResult = result
    pendingSelectionMode = selectionMode
    pendingPickRecursive = recursive
    pendingAllowedExtensions = allowedExtensions

    presenter.present(picker, animated: true)
  }

  private func save(arguments: [String: Any]?, result: @escaping FlutterResult) {
    guard pendingPickResult == nil && pendingSaveResult == nil else {
      result(FlutterError(code: "picker_active", message: "Another file picker request is already active.", details: nil))
      return
    }

    guard let presenter = topViewController() else {
      result(FlutterError(code: "no_view_controller", message: "No view controller is available to present the document picker.", details: nil))
      return
    }

    guard let typedData = arguments?["bytes"] as? FlutterStandardTypedData else {
      result(FlutterError(code: "invalid_args", message: "A byte payload is required.", details: nil))
      return
    }
    guard let suggestedName = arguments?["suggestedName"] as? String,
          isValidFileName(suggestedName) else {
      result(FlutterError(code: "invalid_args", message: "A non-empty file name is required.", details: nil))
      return
    }

    let title = arguments?["title"] as? String
    let initialDirectory = arguments?["initialDirectory"] as? String
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("filegate-\(UUID().uuidString)", isDirectory: true)
    let temporaryFile = temporaryDirectory.appendingPathComponent(suggestedName)

    do {
      try FileManager.default.createDirectory(
        at: temporaryDirectory,
        withIntermediateDirectories: true
      )
      try typedData.data.write(to: temporaryFile, options: .atomic)
    } catch {
      try? FileManager.default.removeItem(at: temporaryDirectory)
      result(FlutterError(code: "write_failed", message: error.localizedDescription, details: suggestedName))
      return
    }

    let picker = UIDocumentPickerViewController(url: temporaryFile, in: .exportToService)
    picker.delegate = self
    if let title, !title.isEmpty {
      picker.title = title
    }
    if let initialDirectory, !initialDirectory.isEmpty {
      picker.directoryURL = resolveURL(from: initialDirectory)
    }

    pendingSaveResult = result
    pendingSaveTemporaryDirectoryURL = temporaryDirectory

    presenter.present(picker, animated: true)
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

    let fileURL = resolveURL(from: path)
    let streamId = UUID().uuidString
    let eventChannel = FlutterEventChannel(name: "filegate/read/\(streamId)", binaryMessenger: messenger)
    let temporaryAccess = fileURL.startAccessingSecurityScopedResource()
    if !temporaryAccess && !FileManager.default.fileExists(atPath: fileURL.path) {
      result(FlutterError(code: "path_not_found", message: "The provided path does not exist.", details: path))
      return
    }
    if !temporaryAccess && !FileManager.default.isReadableFile(atPath: fileURL.path) {
      result(FlutterError(code: "security_scope_failed", message: "Unable to access the selected file in the current session.", details: path))
      return
    }
    do {
      let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
      if resourceValues.isDirectory == true {
        if temporaryAccess {
          fileURL.stopAccessingSecurityScopedResource()
        }
        result(FlutterError(code: "not_a_file", message: "The provided path is a directory, not a file.", details: path))
        return
      }
    } catch {
      if temporaryAccess {
        fileURL.stopAccessingSecurityScopedResource()
      }
      result(FlutterError(code: "path_not_found", message: "The provided path does not exist.", details: path))
      return
    }

    let handler = FileReadStreamHandler(
      handleFactory: {
        let handle = try FileHandle(forReadingFrom: fileURL)
        try handle.seek(toOffset: UInt64(start))
        return handle
      },
      errorDetails: path,
      chunkSize: chunkSize,
      maxBytes: end.map { $0 - start },
      onDispose: { [weak self] in
        if temporaryAccess {
          fileURL.stopAccessingSecurityScopedResource()
        }
        DispatchQueue.main.async {
          self?.releaseReadStream(streamId)
        }
      }
    )

    eventChannel.setStreamHandler(handler)
    readChannels[streamId] = eventChannel
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

  public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    if pendingSaveResult != nil {
      completePendingSave(urls: urls)
      return
    }

    let result = pendingPickResult
    let selectionMode = pendingSelectionMode
    let recursive = pendingPickRecursive
    let allowedExtensions = pendingAllowedExtensions
    clearPendingPickState()

    guard let result else {
      return
    }

    do {
      let entries = try resolvePickedEntries(
        urls: urls,
        selectionMode: selectionMode,
        recursive: recursive,
        allowedExtensions: allowedExtensions
      )
      result(entries)
    } catch let error as FilegateError {
      result(FlutterError(code: error.code, message: error.message, details: error.details))
    } catch {
      result(FlutterError(code: "pick_failed", message: error.localizedDescription, details: nil))
    }
  }

  public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    if let result = pendingSaveResult {
      result(nil)
      clearPendingSaveState()
      return
    }

    pendingPickResult?(nil)
    clearPendingPickState()
  }

  private func clearPendingPickState() {
    pendingPickResult = nil
    pendingSelectionMode = "filesOnly"
    pendingPickRecursive = false
    pendingAllowedExtensions = []
  }

  private func completePendingSave(urls: [URL]) {
    let result = pendingSaveResult
    defer {
      clearPendingSaveState()
    }

    guard let result else {
      return
    }
    guard let url = urls.first else {
      result(FlutterError(code: "save_failed", message: "No exported file URL was returned.", details: nil))
      return
    }

    result(serializeFileEntry(url))
  }

  private func clearPendingSaveState() {
    if let temporaryDirectory = pendingSaveTemporaryDirectoryURL {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
    pendingSaveResult = nil
    pendingSaveTemporaryDirectoryURL = nil
  }

  private func resolvePickedEntries(
    urls: [URL],
    selectionMode: String,
    recursive: Bool,
    allowedExtensions: [String]
  ) throws -> [[String: Any]] {
    var entriesByPath: [String: [String: Any]] = [:]

    for url in urls {
      let values = try url.resourceValues(forKeys: [.isDirectoryKey])
      if values.isDirectory == true {
        let scopeActive = url.startAccessingSecurityScopedResource()
        guard scopeActive || FileManager.default.isReadableFile(atPath: url.path) else {
          throw FilegateError(code: "security_scope_failed", message: "Unable to access the selected directory in the current session.", details: url.absoluteString)
        }
        defer {
          if scopeActive {
            url.stopAccessingSecurityScopedResource()
          }
        }

        for entry in try expandDirectory(at: url, recursive: recursive, allowedExtensions: allowedExtensions) {
          if let path = entry["path"] as? String {
            entriesByPath[path] = entry
          }
        }
      } else if matchesAllowedExtensions(url: url, allowedExtensions: allowedExtensions) {
        entriesByPath[url.absoluteString] = serializeFileEntry(url)
      }
    }

    return sortedEntries(Array(entriesByPath.values))
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
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      ) else {
        throw FilegateError(code: "enumeration_failed", message: "Unable to enumerate the selected directory.", details: directoryURL.absoluteString)
      }

      var entries: [[String: Any]] = []
      for case let fileURL as URL in enumerator {
        let values = try fileURL.resourceValues(forKeys: Set(keys))
        if values.isDirectory == true {
          continue
        }
        if matchesAllowedExtensions(url: fileURL, allowedExtensions: allowedExtensions) {
          let nestedPath = fileURL.path.replacingOccurrences(of: directoryURL.path + "/", with: "")
          entries.append(serializeFileEntry(fileURL, relativePath: nestedPath))
        }
      }
      return sortedEntries(entries)
    }

    let urls = try FileManager.default.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: keys,
      options: [.skipsHiddenFiles, .skipsPackageDescendants]
    )

    let entries: [[String: Any]] = try urls.compactMap { fileURL -> [String: Any]? in
      let values = try fileURL.resourceValues(forKeys: Set(keys))
      guard values.isDirectory != true else {
        return nil
      }
      guard matchesAllowedExtensions(url: fileURL, allowedExtensions: allowedExtensions) else {
        return nil
      }
      return serializeFileEntry(fileURL, relativePath: fileURL.lastPathComponent)
    }
    return sortedEntries(entries)
  }

  private func sortedEntries(_ entries: [[String: Any]]) -> [[String: Any]] {
    entries.sorted { left, right in
      let leftKey = stableEntryKey(left)
      let rightKey = stableEntryKey(right)
      if leftKey != rightKey {
        return leftKey < rightKey
      }
      let leftName = left["name"] as? String ?? ""
      let rightName = right["name"] as? String ?? ""
      if leftName != rightName {
        return leftName < rightName
      }
      return (left["path"] as? String ?? "") < (right["path"] as? String ?? "")
    }
  }

  private func stableEntryKey(_ entry: [String: Any]) -> String {
    let key =
      (entry["relativePath"] as? String) ??
      (entry["name"] as? String) ??
      (entry["path"] as? String) ??
      ""
    return key.replacingOccurrences(of: "\\", with: "/")
  }

  private func serializeFileEntry(_ url: URL, relativePath: String? = nil) -> [String: Any] {
    [
      "path": url.absoluteString,
      "name": url.lastPathComponent,
      "kind": "file",
      "relativePath": relativePath ?? url.lastPathComponent,
      "metadata": metadataForFile(url),
    ]
  }

  private func buildDocumentTypes(selectionMode: String, allowedExtensions: [String]) -> [String] {
    let normalizedExtensions = normalizeExtensions(allowedExtensions)
    let fileTypes: [String]
    if normalizedExtensions.isEmpty {
      fileTypes = [kUTTypeData as String]
    } else {
      let mapped = normalizedExtensions.compactMap { extensionValue -> String? in
        guard let unmanagedType = UTTypeCreatePreferredIdentifierForTag(
          kUTTagClassFilenameExtension,
          extensionValue as CFString,
          nil
        ) else {
          return nil
        }
        return unmanagedType.takeRetainedValue() as String
      }
      fileTypes = mapped.isEmpty ? [kUTTypeData as String] : mapped
    }

    switch selectionMode {
    case "directoriesOnly":
      return [kUTTypeFolder as String]
    case "filesAndDirectories":
      return fileTypes + [kUTTypeFolder as String]
    default:
      return fileTypes
    }
  }

  private func matchesAllowedExtensions(url: URL, allowedExtensions: [String]) -> Bool {
    let normalizedExtensions = normalizeExtensions(allowedExtensions)
    guard !normalizedExtensions.isEmpty else {
      return true
    }
    return normalizedExtensions.contains(url.pathExtension.lowercased())
  }

  private func normalizeExtensions(_ extensions: [String]) -> [String] {
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

  private func isValidFileName(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty && !value.contains("/") && !value.contains("\\")
  }

  private func metadataForFile(_ url: URL) -> [String: Any] {
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

  private func mimeTypeForFile(_ url: URL) -> String? {
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

  private func releaseReadStream(_ streamId: String) {
    readHandlers.removeValue(forKey: streamId)
    readChannels.removeValue(forKey: streamId)?.setStreamHandler(nil)
  }

  private func cancelReadStream(_ streamId: String) {
    readHandlers.removeValue(forKey: streamId)?.cancel()
    readChannels.removeValue(forKey: streamId)?.setStreamHandler(nil)
  }

  private func resolveURL(from value: String) -> URL {
    if let url = URL(string: value), url.scheme != nil {
      return url
    }
    return URL(fileURLWithPath: value)
  }

  private func topViewController() -> UIViewController? {
    let rootViewController = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)?
      .rootViewController

    var controller = rootViewController
    while let presentedViewController = controller?.presentedViewController {
      controller = presentedViewController
    }
    return controller
  }
}

private final class FileReadStreamHandler: NSObject, FlutterStreamHandler {
  private let handleFactory: () throws -> FileHandle
  private let errorDetails: String
  private let chunkSize: Int
  private let maxBytes: Int?
  private let queue = DispatchQueue(label: "filegate.ios.read", qos: .utility)
  private let lock = NSLock()
  private let onDispose: () -> Void

  private var fileHandle: FileHandle?
  private var eventSink: FlutterEventSink?
  private var isCancelled = false
  private var isDisposed = false

  init(
    handleFactory: @escaping () throws -> FileHandle,
    errorDetails: String,
    chunkSize: Int,
    maxBytes: Int?,
    onDispose: @escaping () -> Void
  ) {
    self.handleFactory = handleFactory
    self.errorDetails = errorDetails
    self.chunkSize = chunkSize
    self.maxBytes = maxBytes
    self.onDispose = onDispose
    super.init()
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    if withLock({ eventSink != nil }) {
      return FlutterError(code: "stream_active", message: "This file stream is already active.", details: nil)
    }

    let handle: FileHandle
    do {
      handle = try handleFactory()
    } catch let error as FilegateError {
      disposeIfNeeded()
      return FlutterError(code: error.code, message: error.message, details: error.details)
    } catch {
      disposeIfNeeded()
      return FlutterError(code: "read_open_failed", message: error.localizedDescription, details: errorDetails)
    }

    lock.lock()
    fileHandle = handle
    eventSink = events
    isCancelled = false
    lock.unlock()

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
      withLock {
        fileHandle = nil
      }
    }

    var remainingBytes = maxBytes
    while true {
      if withLock({ isCancelled }) {
        return
      }
      if let remainingBytes, remainingBytes <= 0 {
        emitEndOfStream()
        return
      }

      do {
        let currentChunkSize = remainingBytes.map { min(chunkSize, $0) } ?? chunkSize
        let data = handle.readData(ofLength: currentChunkSize)
        if !data.isEmpty {
          if let currentRemainingBytes = remainingBytes {
            remainingBytes = currentRemainingBytes - data.count
          }
          emitChunk(data)
          continue
        }
      }

      emitEndOfStream()
      return
    }
  }

  private func emitChunk(_ data: Data) {
    guard let sink = withLock({ isCancelled ? nil : eventSink }) else {
      return
    }
    DispatchQueue.main.async {
      sink(FlutterStandardTypedData(bytes: data))
    }
  }

  private func emitEndOfStream() {
    guard let sink = withLock({ isCancelled ? nil : eventSink }) else {
      return
    }
    DispatchQueue.main.async { [weak self] in
      sink(FlutterEndOfEventStream)
      self?.finishStream()
    }
  }

  private func emitError(_ error: Error) {
    guard let sink = withLock({ isCancelled ? nil : eventSink }) else {
      return
    }
    DispatchQueue.main.async { [weak self] in
      sink(FlutterError(code: "read_failed", message: error.localizedDescription, details: self?.errorDetails))
      self?.finishStream()
    }
  }

  private func finishStream() {
    withLock {
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

private struct FilegateError: Error {
  let code: String
  let message: String
  let details: Any?
}
