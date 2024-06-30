//
//  ViewController.swift
//  Scanner
//
//  Created by Likhitha Mandapati on 6/27/24.
//

import UIKit
import AVFoundation
import Vision

class DisplayViewController: UIViewController {
    
    
    var captureSession: AVCaptureSession!
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    var photoOutput: AVCapturePhotoOutput!
    var videoDataOutput: AVCaptureVideoDataOutput!
    var isScanningBarcode = true  // Default to scanning barcode
    
    @IBOutlet var previewImageView: UIImageView!
    @IBOutlet weak var scannerTF: UITextField!
    @IBOutlet weak var scanBarcodeButton: UIButton!
    @IBOutlet weak var captureTextButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCaptureSession()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        videoPreviewLayer?.frame = previewImageView.bounds
    }
    
    
    //MARK: - Scan operation functions
    
    func setupCaptureSession() {
        captureSession = AVCaptureSession()
        
        // Configure video input
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            print("Failed to get video capture device")
            failed()
            return
        }
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            } else {
                print("Failed to add video input")
                failed()
                return
            }
        } catch {
            print("Failed to create video input: \(error)")
            failed()
            return
        }
        
        // Configure metadata output for barcode scanning
        let metaDataOutput = AVCaptureMetadataOutput()
        if captureSession.canAddOutput(metaDataOutput) {
            captureSession.addOutput(metaDataOutput)
            metaDataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metaDataOutput.metadataObjectTypes = [.qr, .ean8, .ean13, .pdf417]
        } else {
            print("Failed to add metadata output")
            failed()
            return
        }
        
        // Configure photo output for capturing still photos
        photoOutput = AVCapturePhotoOutput()
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        } else {
            print("Failed to add photo output")
            failed()
            return
        }
        
        // Configure video data output for text recognition
        videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: .background))
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        } else {
            print("Failed to add video data output")
            failed()
            return
        }
        
        // Setup preview layer
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer?.videoGravity = .resizeAspectFill
        videoPreviewLayer?.frame = view.layer.bounds
        //view.layer.insertSublayer(videoPreviewLayer!, at: 0)
        previewImageView.layer.addSublayer(videoPreviewLayer!)
        
        // Start running the capture session
        captureSession.startRunning()
    }
    
    func startScanning() {
        DispatchQueue.global(qos: .background).async {
            self.captureSession.startRunning()
            DispatchQueue.main.async {
                self.videoPreviewLayer?.frame = self.previewImageView.bounds
            }
        }
    }
    
    func stopScanning() {
        DispatchQueue.global(qos: .background).async {
            self.captureSession.stopRunning()
        }
    }
    
    func failed() {
        let ac = UIAlertController(title: "Scanning not supported", message: "Your device does not support scanning", preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
        present(ac, animated: true)
        captureSession = nil
    }
    
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    

    //MARK: - Barcode scan
    
    @IBAction func scanBarcodeTapped(_ sender: UIButton) {
        scannerTF.text = ""
        isScanningBarcode = true
        startScanning()
    }
    
    func handleBarcodeDetection(_ metadataObjects: [AVMetadataMachineReadableCodeObject]) {
        if let metadataObj = metadataObjects.first, let stringValue = metadataObj.stringValue {
            DispatchQueue.main.async {
                self.scannerTF.text = stringValue
            }
        }
    }
    
    
    //MARK: - Text scan
    
    @IBAction func captureTextTapped(_ sender: UIButton) {
        scannerTF.text = ""
        isScanningBarcode = false
        startScanning()
    }
    
    func handleTextDetection(in image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest { (request, error) in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            let recognizedTexts = observations.compactMap { $0.topCandidates(1).first?.string }
            DispatchQueue.main.async {
                self.scannerTF.text = recognizedTexts.joined(separator: ", ")
            }
        }
        
        do {
            try requestHandler.perform([request])
        } catch {
            print("Failed to perform text detection: \(error)")
        }
    }
}



//MARK: - Metadata extension

extension DisplayViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard isScanningBarcode else { return }
        
        if let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject {
            handleBarcodeDetection([metadataObject])
        }
    }
}


//MARK: - Photo capture extension
extension DisplayViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation() else { return }
        let image = UIImage(data: imageData)
        DispatchQueue.main.async {
            self.previewImageView.image = image
            if let image = image {
                self.handleTextDetection(in: image)
            }
            self.stopScanning()
        }
    }
}

//MARK: - Text capture extension
extension DisplayViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isScanningBarcode, let image = imageFromSampleBuffer(sampleBuffer) else {
            return
        }
        handleTextDetection(in: image)
    }
    
    private func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
