/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/LiveCameraView.kt
//
// NOTE: Android used CameraX (ProcessCameraProvider, ImageAnalysis) which has no
// direct iOS equivalent. This port uses AVFoundation via UIViewRepresentable to
// provide a live camera feed. `onBitmap` is called on the session queue with each
// captured UIImage, matching the contract of the Android `onBitmap(Bitmap, ImageProxy)`
// callback. The caller is responsible for any frame-rate throttling.
//
// `outputImageFormat` and `preferredSize` are kept for API parity but are best-effort
// on iOS: the session preset is chosen close to `preferredSize`, and UIImage is always
// RGBA/BGRA.

import SwiftUI
import AVFoundation

// MARK: - LiveCameraView

/// Displays a live camera preview and delivers bitmap frames to the caller.
/// Mirrors `LiveCameraView` composable.
struct LiveCameraView: View {
  /// Called on a background queue for each captured frame.
  var onBitmap: (UIImage) -> Void
  var useFrontCamera: Bool = true
  var renderPreview: Bool = true

  @State private var permissionGranted: Bool = false
  @State private var session: AVCaptureSession? = nil

  var body: some View {
    Group {
      if permissionGranted {
        if renderPreview {
          CameraPreviewView(
            onBitmap: onBitmap,
            useFrontCamera: useFrontCamera,
            session: $session
          )
        } else {
          // No preview — still runs the capture pipeline.
          CameraPreviewView(
            onBitmap: onBitmap,
            useFrontCamera: useFrontCamera,
            session: $session
          )
          .frame(width: 0, height: 0)
          .hidden()
        }
      } else {
        Color.black
          .overlay(
            Text("Camera permission required")
              .foregroundStyle(.white)
          )
      }
    }
    .task {
      await requestCameraPermission()
    }
    .onDisappear {
      session?.stopRunning()
    }
  }

  private func requestCameraPermission() async {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    switch status {
    case .authorized:
      permissionGranted = true
    case .notDetermined:
      let granted = await AVCaptureDevice.requestAccess(for: .video)
      await MainActor.run { permissionGranted = granted }
    default:
      break
    }
  }
}

// MARK: - CameraPreviewView

private struct CameraPreviewView: UIViewRepresentable {
  var onBitmap: (UIImage) -> Void
  var useFrontCamera: Bool
  @Binding var session: AVCaptureSession?

  func makeCoordinator() -> Coordinator {
    Coordinator(onBitmap: onBitmap)
  }

  func makeUIView(context: Context) -> PreviewUIView {
    let view = PreviewUIView()
    let captureSession = AVCaptureSession()
    captureSession.sessionPreset = .medium   // ~480p, close to the Android 500px preferredSize

    guard let device = AVCaptureDevice.default(
      .builtInWideAngleCamera,
      for: .video,
      position: useFrontCamera ? .front : .back
    ),
    let input = try? AVCaptureDeviceInput(device: device),
    captureSession.canAddInput(input) else { return view }

    captureSession.addInput(input)

    let output = AVCaptureVideoDataOutput()
    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    output.setSampleBufferDelegate(context.coordinator, queue: DispatchQueue(label: "camera.queue"))
    if captureSession.canAddOutput(output) {
      captureSession.addOutput(output)
    }

    // Mirror front camera like the Android implementation
    if useFrontCamera,
       let connection = output.connection(with: .video) {
      connection.automaticallyAdjustsVideoMirroring = false
      connection.isVideoMirrored = true
    }

    let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
    previewLayer.videoGravity = .resizeAspectFill
    view.previewLayer = previewLayer
    view.layer.addSublayer(previewLayer)

    DispatchQueue.global(qos: .userInitiated).async {
      captureSession.startRunning()
    }

    DispatchQueue.main.async { self.session = captureSession }
    return view
  }

  func updateUIView(_ uiView: PreviewUIView, context: Context) {
    DispatchQueue.main.async {
      uiView.previewLayer?.frame = uiView.bounds
    }
  }

  final class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let onBitmap: (UIImage) -> Void
    init(onBitmap: @escaping (UIImage) -> Void) { self.onBitmap = onBitmap }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
      guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
      let ciImage = CIImage(cvImageBuffer: imageBuffer)
      let context = CIContext()
      guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
      let uiImage = UIImage(cgImage: cgImage)
      onBitmap(uiImage)
    }
  }
}

// MARK: - PreviewUIView

private final class PreviewUIView: UIView {
  var previewLayer: AVCaptureVideoPreviewLayer?

  override func layoutSubviews() {
    super.layoutSubviews()
    previewLayer?.frame = bounds
  }
}
