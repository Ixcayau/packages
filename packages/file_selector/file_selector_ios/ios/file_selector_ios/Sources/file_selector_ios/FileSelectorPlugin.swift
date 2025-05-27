// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Flutter
import ObjectiveC
import UIKit

/// Bridge between a UIDocumentPickerViewController and its Pigeon callback.
class PickerCompletionBridge: NSObject, UIDocumentPickerDelegate {
  let completion: (Result<[String], Error>) -> Void
  /// The plugin instance that owns this object, to ensure that it lives as long as the picker it
  /// serves as a delegate for. Instances are responsible for removing themselves from their owner
  /// on completion.
  let owner: FileSelectorPlugin

  init(completion: @escaping (Result<[String], Error>) -> Void, owner: FileSelectorPlugin) {
    self.completion = completion
    self.owner = owner
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    sendResult(urls.map({ $0.path }))
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    sendResult([])
  }

  private func sendResult(_ result: [String]) {
    completion(.success(result))
    owner.pendingCompletions.remove(self)
  }
}

public class FileSelectorPlugin: NSObject, FlutterPlugin, FileSelectorApi {
  /// Owning references to pending completion callbacks.
  ///
  /// This is necessary since the objects need to live until a UIDocumentPickerDelegate method is
  /// called on the delegate, but the delegate is weak. Objects in this set are responsible for
  /// removing themselves from it.
  var pendingCompletions: Set<PickerCompletionBridge> = []
  /// Overridden document picker, for testing.
  var documentPickerViewControllerOverride: UIDocumentPickerViewController?
  /// Overridden view presenter, for testing.
  var viewPresenterOverride: ViewPresenter?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FileSelectorPlugin()
    FileSelectorApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
  }
    
  func openFile(config: FileSelectorConfig, completion: @escaping (Result<[String], Error>) -> Void)
  {
    let completionBridge = PickerCompletionBridge(completion: completion, owner: self)
    let documentPicker = documentPickerViewControllerOverride ?? UIDocumentPickerViewController(
      documentTypes: config.utis,
      in: .import
    )
    documentPicker.allowsMultipleSelection = config.allowMultiSelection
    documentPicker.delegate = completionBridge
    documentPicker.modalPresentationStyle = .formSheet
    
    // Improved view controller hierarchy handling
    DispatchQueue.main.async {
      guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let window = windowScene.windows.first(where: { $0.isKeyWindow }),
          var topController = window.rootViewController else {
        completion(.failure(PigeonError(code: "error", message: "Unable to access window hierarchy", details: nil)))
        return
      }
      
      // Find the topmost presented view controller
      while let presentedController = topController.presentedViewController {
        topController = presentedController
      }
      
      // Special handling for Flutter view controllers
      if let flutterViewController = topController as? FlutterViewController {
        // Ensure presentation happens after Flutter view is fully loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          flutterViewController.present(documentPicker, animated: true) {
            self.pendingCompletions.insert(completionBridge)
          }
        }
      } else {
        topController.present(documentPicker, animated: true) {
          self.pendingCompletions.insert(completionBridge)
        }
      }
    }
  }

}
