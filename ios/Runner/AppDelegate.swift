import CoreImage
import Flutter
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Channel used by the Dart side to detect the subjects of a photo. Detection runs off the main
    // thread; when it is unavailable the Dart side falls back to manual selection.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "EpicicliSubjects") {
      let channel = FlutterMethodChannel(name: "epicicli/subjects", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "detect",
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String
        else {
          result(FlutterMethodNotImplemented)
          return
        }
        let maxSide = args["maxSide"] as? Int ?? 480
        DispatchQueue.global(qos: .userInitiated).async {
          let out = SubjectDetector.detect(path: path, maxSide: maxSide)
          DispatchQueue.main.async { result(out) }
        }
      }
    }
  }
}

/// Foreground subjects of a photo, from Vision's foreground instance mask request.
/// Returns one soft 8-bit mask per subject (at most 8), all of the same size (longer side at most
/// `maxSide`), or nil if detection is unavailable (before iOS 17, unreadable image, request failure).
enum SubjectDetector {
  static func detect(path: String, maxSide: Int) -> [String: Any]? {
    guard #available(iOS 17.0, *) else { return nil }
    guard
      let image = CIImage(
        contentsOf: URL(fileURLWithPath: path), options: [.applyOrientationProperty: true])
    else { return nil }
    let handler = VNImageRequestHandler(ciImage: image, options: [:])
    let request = VNGenerateForegroundInstanceMaskRequest()
    do { try handler.perform([request]) } catch { return nil }

    var masks: [FlutterStandardTypedData] = []
    var w = 0
    var h = 0
    if let obs = request.results?.first {
      let ctx = CIContext()
      let gray = CGColorSpace(name: CGColorSpace.linearGray)
      for i in obs.allInstances.prefix(8) {
        guard
          let buf = try? obs.generateScaledMaskForImage(
            forInstances: IndexSet(integer: i), from: handler)
        else { continue }
        var ci = CIImage(cvPixelBuffer: buf)
        let s = CGFloat(maxSide) / max(ci.extent.width, ci.extent.height)
        if s < 1 { ci = ci.transformed(by: CGAffineTransform(scaleX: s, y: s)) }
        let mw = Int(ci.extent.width.rounded(.down))
        let mh = Int(ci.extent.height.rounded(.down))
        if mw < 2 || mh < 2 { continue }
        if w == 0 {
          w = mw
          h = mh
        } else if mw != w || mh != h {
          continue
        }
        var bytes = [UInt8](repeating: 0, count: w * h)
        ctx.render(
          ci, toBitmap: &bytes, rowBytes: w,
          bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .L8, colorSpace: gray)
        masks.append(FlutterStandardTypedData(bytes: Data(bytes)))
      }
    }
    return ["width": w, "height": h, "masks": masks]
  }
}
