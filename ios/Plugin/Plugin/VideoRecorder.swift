import Foundation
import AVFoundation
import Capacitor

@objc(CAPVideoRecorderPlugin)
public class CAPVideoRecorderPlugin: CAPPlugin, AVCaptureFileOutputRecordingDelegate {

    var capWebView: WKWebView!

    var cameraView: CameraView!
    var captureSession: AVCaptureSession?
    var captureVideoPreviewLayer: AVCaptureVideoPreviewLayer?
    var videoOutput: AVCaptureMovieFileOutput?
    var durationTimer: Timer?

    var audioLevelTimer: Timer?
    var audioRecorder: AVAudioRecorder?

    var cameraInput: AVCaptureDeviceInput?

    var currentCamera: Int = 0
    var frontCamera: AVCaptureDevice?
    var backCamera: AVCaptureDevice?
    var quality: Int = 0

    var stopRecordingCall: CAPPluginCall?

    var previewFrameConfigs: [FrameConfig] = []
    var currentFrameConfig: FrameConfig = FrameConfig(["id": "default"])

    /**
     * Capacitor Plugin load
     */
    override public func load() {
        self.capWebView = self.bridge?.webView
    }

    /**
     * AVCaptureFileOutputRecordingDelegate
     */
    public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        self.durationTimer?.invalidate()
        self.stopRecordingCall?.resolve([
            "videoUrl": self.bridge?.portablePath(fromLocalURL: outputFileURL)?.absoluteString as Any
        ])
    }

    @objc func levelTimerCallback(_ timer: Timer?) {
        self.audioRecorder?.updateMeters()
        // let peakDecebels: Float = (self.audioRecorder?.peakPower(forChannel: 1))!
        let averagePower: Float = (self.audioRecorder?.averagePower(forChannel: 1))!
        self.notifyListeners("onVolumeInput", data: ["value":averagePower])
    }
    
           
    private func requestPermission() {
              DispatchQueue.main.async {}
       }

    
    private func hideBackground() {
           DispatchQueue.main.async {
               self.bridge?.webView!.isOpaque = false
               self.bridge?.webView!.backgroundColor = UIColor.clear
               self.bridge?.webView!.scrollView.backgroundColor = UIColor.clear

               let javascript = "document.documentElement.style.backgroundColor = 'transparent'; document.body.style.backgroundColor = 'transparent'"

               self.bridge?.webView!.evaluateJavaScript(javascript)
           }
       }

       private func showBackground() {
           DispatchQueue.main.async {
               let javascript = "document.documentElement.style.backgroundColor = ''; document.body.style.backgroundColor = ''"

               self.bridge?.webView!.evaluateJavaScript(javascript) { (result, error) in
                   self.bridge?.webView!.isOpaque = true
                   self.bridge?.webView!.backgroundColor = UIColor.white
                   self.bridge?.webView!.scrollView.backgroundColor = UIColor.white
               }
           }
       }


	/**
	* Initializes the camera.
	* { camera: Int, quality: Int }
	*/
    @objc func initialize(_ call: CAPPluginCall) {
    
        if (self.captureSession?.isRunning != true) {
            self.currentCamera = call.getInt("camera", 0)
            self.quality = call.getInt("quality", 0)
            let autoShow = call.getBool("autoShow", true)

            for frameConfig in call.getArray("previewFrames", [ ["id": "default"] ]) {
                self.previewFrameConfigs.append(FrameConfig(frameConfig as! [AnyHashable : Any]))
            }
            self.currentFrameConfig = self.previewFrameConfigs.first!

            if checkAuthorizationStatus(call) {
                DispatchQueue.main.async {
                    do {
                        // Set webview to transparent and set the app window background to white
                        /*
                         UIApplication.shared.delegate?.window?!.backgroundColor = UIColor.white
                         */
                        self.hideBackground()

                        let deviceDescoverySession = AVCaptureDevice.DiscoverySession.init(
                            deviceTypes: [AVCaptureDevice.DeviceType.builtInWideAngleCamera],
                            mediaType: AVMediaType.video,
                            position: AVCaptureDevice.Position.unspecified)

                        for device in deviceDescoverySession.devices {
                            if device.position == AVCaptureDevice.Position.back {
                                self.backCamera = device
                            } else if device.position == AVCaptureDevice.Position.front {
                                self.frontCamera = device
                            }
                        }

                        if (self.backCamera == nil) {
                            self.currentCamera = 1
                        }

                        // Create capture session
                        self.captureSession = AVCaptureSession()
                        // Begin configuration
                        self.captureSession?.beginConfiguration()
                        
                        self.captureSession?.automaticallyConfiguresApplicationAudioSession = false

                        /**
                         * Video file recording capture session
                         */
                        self.captureSession?.usesApplicationAudioSession = true
                        // Add Camera Input
                        self.cameraInput = try createCaptureDeviceInput(currentCamera: self.currentCamera, frontCamera: self.frontCamera, backCamera: self.backCamera)
                        self.captureSession!.addInput(self.cameraInput!)
                        // Add Microphone Input
                        let microphone = AVCaptureDevice.default(for: .audio)
                        if let audioInput = try? AVCaptureDeviceInput(device: microphone!), (self.captureSession?.canAddInput(audioInput))! {
                            self.captureSession!.addInput(audioInput)
                        }
                        // Add Video File Output
                        self.videoOutput = AVCaptureMovieFileOutput()
                        self.videoOutput?.movieFragmentInterval = CMTime.invalid
                        self.captureSession!.addOutput(self.videoOutput!)
                        
                        let cameraMaxWidth = self.cameraInput?.device.activeFormat.formatDescription.dimensions.width ?? 0
                        
                        // Set Video quality
                        switch(self.quality){
                        case 1:
                            // handle camera preset not supported
                            if (cameraMaxWidth != 0 && cameraMaxWidth < 1280) {
                                call.reject("Quality not supported")
                                return
                            }
                            self.captureSession?.sessionPreset = AVCaptureSession.Preset.hd1280x720
                            break;
                        case 2:
                            // handle camera preset not supported
                            if (cameraMaxWidth != 0 && cameraMaxWidth < 1920) {
                                call.reject("Quality not supported")
                                return
                            }
                            self.captureSession?.sessionPreset = AVCaptureSession.Preset.hd1920x1080
                            break;
                        case 3:
                            // handle camera preset not supported
                            if (cameraMaxWidth != 0 && cameraMaxWidth < 3840) {
                                call.reject("Quality not supported")
                                return
                            }
                            self.captureSession?.sessionPreset = AVCaptureSession.Preset.hd4K3840x2160
                            break;
                        case 4:
                            self.captureSession?.sessionPreset = AVCaptureSession.Preset.high
                            break;
                        case 5:
                            self.captureSession?.sessionPreset = AVCaptureSession.Preset.low
                            break;
                        case 6:
                            self.captureSession?.sessionPreset = AVCaptureSession.Preset.cif352x288
                            break;
                        default:
                            self.captureSession?.sessionPreset = AVCaptureSession.Preset.vga640x480
                            break;
                        }

                        let connection: AVCaptureConnection? = self.videoOutput?.connection(with: .video)
                        self.videoOutput?.setOutputSettings([AVVideoCodecKey : AVVideoCodecType.h264], for: connection!)

                        // Commit configurations
                        self.captureSession?.commitConfiguration()
                        
                        try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [
                            AVAudioSession.CategoryOptions.mixWithOthers,
                            AVAudioSession.CategoryOptions.defaultToSpeaker,
                            AVAudioSession.CategoryOptions.allowBluetoothA2DP,
                            AVAudioSession.CategoryOptions.allowAirPlay
                        ])
                        try? AVAudioSession.sharedInstance().setActive(true)
                        let settings = [
                            AVSampleRateKey : 44100.0,
                            AVFormatIDKey : kAudioFormatAppleLossless,
                            AVNumberOfChannelsKey : 2,
                            AVEncoderAudioQualityKey : AVAudioQuality.max.rawValue
                            ] as [String : Any]
                        self.audioRecorder = try AVAudioRecorder(url: URL(fileURLWithPath: "/dev/null"), settings: settings)
                        self.audioRecorder?.isMeteringEnabled = true
                        self.audioRecorder?.prepareToRecord()
                        self.audioRecorder?.record()
                        self.audioLevelTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(self.levelTimerCallback(_:)), userInfo: nil, repeats: true)
                        self.audioRecorder?.updateMeters()

                        // Start running sessions
                        self.captureSession!.startRunning()

                        // Initialize camera view
                        self.initializeCameraView()

                        if autoShow {
                            self.cameraView.isHidden = false
                        }

                    } catch CaptureError.backCameraUnavailable {
                        call.reject("Back camera unavailable")
                    } catch CaptureError.frontCameraUnavailable {
                        call.reject("Front camera unavailable")
                    } catch CaptureError.couldNotCaptureInput( _){
                        call.reject("Camera unavailable")
                    } catch {
                        call.reject("Unexpected error")
                    }
                    call.resolve()
                }
            }
        }
    }

	/**
	* Destroys the camera.
	*/
    @objc func destroy(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.showBackground()

            let appDelegate = UIApplication.shared.delegate
            appDelegate?.window?!.backgroundColor = UIColor.black

            self.capWebView?.isOpaque = true
            self.capWebView?.backgroundColor = UIColor.white
            if (self.captureSession != nil) {
				// Need to destroy all preview layers
                self.previewFrameConfigs = []
                self.currentFrameConfig = FrameConfig(["id": "default"])
                if (self.captureSession!.isRunning) {
                    self.captureSession!.stopRunning()
                }
                if (self.audioRecorder != nil && self.audioRecorder!.isRecording) {
                    self.audioRecorder!.stop()
                }
                self.cameraView?.removePreviewLayer()
                self.captureVideoPreviewLayer = nil
                self.cameraView?.removeFromSuperview()
                self.videoOutput = nil
                self.cameraView = nil
                self.captureSession = nil
                self.audioRecorder = nil
                self.audioLevelTimer?.invalidate()
                self.currentCamera = 0
                self.frontCamera = nil
                self.backCamera = nil
                self.notifyListeners("onVolumeInput", data: ["value":0])
            }
            call.resolve()
        }
    }

	/**
	* Toggle between the front facing and rear facing camera.
	*/
    @objc func flipCamera(_ call: CAPPluginCall) {
        if (self.captureSession != nil) {
            var input: AVCaptureDeviceInput? = nil
            do {
                self.currentCamera = self.currentCamera == 0 ? 1 : 0
                input = try createCaptureDeviceInput(currentCamera: self.currentCamera, frontCamera: self.frontCamera, backCamera: self.backCamera)
            } catch CaptureError.backCameraUnavailable {
                self.currentCamera = self.currentCamera == 0 ? 1 : 0
                call.reject("Back camera unavailable")
            } catch CaptureError.frontCameraUnavailable {
                self.currentCamera = self.currentCamera == 0 ? 1 : 0
                call.reject("Front camera unavailable")
            } catch CaptureError.couldNotCaptureInput( _) {
                self.currentCamera = self.currentCamera == 0 ? 1 : 0
                call.reject("Camera unavailable")
            } catch {
                self.currentCamera = self.currentCamera == 0 ? 1 : 0
                call.reject("Unexpected error")
            }

            if (input != nil) {
                let currentInput = self.cameraInput
                self.captureSession?.beginConfiguration()
                self.captureSession?.removeInput(currentInput!)
                self.captureSession!.addInput(input!)
                self.cameraInput = input
                self.captureSession?.commitConfiguration()
                call.resolve();
            }
        }
    }

	/**
	* Add a camera preview frame config.
	*/
    @objc func addPreviewFrameConfig(_ call: CAPPluginCall) {
        if (self.captureSession != nil) {
            guard let layerId = call.getString("id") else {
                call.reject("Must provide layer id")
                return
            }
			let newFrame = FrameConfig(call.options)

            // Check to make sure config doesn't already exist, if it does, edit it instead
            if (self.previewFrameConfigs.firstIndex(where: {$0.id == layerId }) == nil) {
                self.previewFrameConfigs.append(newFrame)
            }
            else {
                self.editPreviewFrameConfig(call)
                return
            }
			call.resolve()
        }
    }

	/**
	* Edit an existing camera frame config.
	*/
    @objc func editPreviewFrameConfig(_ call: CAPPluginCall) {
        if (self.captureSession != nil) {
            guard let layerId = call.getString("id") else {
                call.reject("Must provide layer id")
                return
            }

            let updatedConfig = FrameConfig(call.options)

            // Get existing frame config
            let existingConfig = self.previewFrameConfigs.filter( {$0.id == layerId }).first
            if (existingConfig != nil) {
                let index = self.previewFrameConfigs.firstIndex(where: {$0.id == layerId })
                self.previewFrameConfigs[index!] = updatedConfig
            }
            else {
                self.addPreviewFrameConfig(call)
                return
            }

            if (self.currentFrameConfig.id == layerId) {
                // Is set to the current frame, need to update
                DispatchQueue.main.async {
                    self.currentFrameConfig = updatedConfig
                    self.updateCameraView(self.currentFrameConfig)
                }
            }
            call.resolve()
        }
    }

    /**
     * Switch frame configs.
     */
    @objc func switchToPreviewFrame(_ call: CAPPluginCall) {
        if (self.captureSession != nil) {
            guard let layerId = call.getString("id") else {
                call.reject("Must provide layer id")
                return
            }
            DispatchQueue.main.async {
                let existingConfig = self.previewFrameConfigs.filter( {$0.id == layerId }).first
                if (existingConfig != nil) {
                    if (existingConfig!.id != self.currentFrameConfig.id) {
                        self.currentFrameConfig = existingConfig!
                        self.updateCameraView(self.currentFrameConfig)
                    }
                }
                else {
                    call.reject("Frame config does not exist")
                    return
                }
                call.resolve()
            }
        }
    }

	/**
	* Show the camera preview frame.
	*/
    @objc func showPreviewFrame(_ call: CAPPluginCall) {
        if (self.captureSession != nil) {
            DispatchQueue.main.async {
                self.cameraView.isHidden = true
                call.resolve()
            }
        }
    }

	/**
	* Hide the camera preview frame.
	*/
    @objc func hidePreviewFrame(_ call: CAPPluginCall) {
        if (self.captureSession != nil) {
            DispatchQueue.main.async {
                self.cameraView.isHidden = false
                call.resolve()
            }
        }
    }

    func initializeCameraView() {
        self.cameraView = CameraView(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        self.cameraView.isHidden = true
        self.cameraView.autoresizingMask = [.flexibleWidth, .flexibleHeight];
        self.captureVideoPreviewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession!)
        self.captureVideoPreviewLayer?.frame = self.cameraView.bounds
        self.cameraView.addPreviewLayer(self.captureVideoPreviewLayer)

        self.cameraView.backgroundColor = UIColor.black
        self.cameraView.videoPreviewLayer?.masksToBounds = true
        self.cameraView.clipsToBounds = false
        self.cameraView.layer.backgroundColor = UIColor.clear.cgColor

        self.capWebView!.superview!.insertSubview(self.cameraView, belowSubview: self.capWebView!)

        self.updateCameraView(self.currentFrameConfig)
    }

    func updateCameraView(_ config: FrameConfig) {
        // Set position and dimensions
        let width = config.width as? String == "fill" ? UIScreen.main.bounds.width : config.width as! CGFloat
        let height = config.height as? String == "fill" ? UIScreen.main.bounds.height : config.height as! CGFloat
        self.cameraView.frame = CGRect(x: config.x, y: config.y, width: width, height: height)

        // Set stackPosition
        if config.stackPosition == "front" {
            self.capWebView!.superview!.bringSubviewToFront(self.cameraView)
        }
        else if config.stackPosition == "back" {
            self.capWebView!.superview!.sendSubviewToBack(self.cameraView)
        }

        // Set decorations
        self.cameraView.videoPreviewLayer?.cornerRadius = config.borderRadius
        self.cameraView.layer.shadowOffset = CGSize.zero
        self.cameraView.layer.shadowColor = config.dropShadow.color
        self.cameraView.layer.shadowOpacity = config.dropShadow.opacity
        self.cameraView.layer.shadowRadius = config.dropShadow.radius
        self.cameraView.layer.shadowPath = UIBezierPath(roundedRect: self.cameraView.bounds, cornerRadius: config.borderRadius).cgPath
    }

	/**
	* Start recording.
	*/
    @objc func startRecording(_ call: CAPPluginCall) {
        if (self.captureSession != nil) {
            if (!(videoOutput?.isRecording)!) {
                let tempDir = NSURL.fileURL(withPath:NSTemporaryDirectory(),isDirectory:true)
                var fileName = randomFileName()
                fileName.append(".mp4")
                let fileUrl = NSURL.fileURL(withPath: joinPath(left:tempDir.path,right: fileName));

                DispatchQueue.main.async {
                    self.videoOutput?.connection(with: .video)?.videoOrientation = self.cameraView.interfaceOrientationToVideoOrientation(UIApplication.shared.statusBarOrientation)
                    self.videoOutput?.startRecording(to: fileUrl, recordingDelegate: self)
                    call.resolve()
                }
            }
        }
    }

	/**
	* Stop recording.
	*/
    @objc func stopRecording(_ call: CAPPluginCall) {
        if (self.captureSession != nil) {
            if (videoOutput?.isRecording)! {
                self.stopRecordingCall = call
                self.videoOutput!.stopRecording()
            }
        }
    }

	/**
	* Get current recording duration.
	*/
    @objc func getDuration(_ call: CAPPluginCall) {
        if (self.videoOutput!.isRecording == true) {
            let duration = self.videoOutput?.recordedDuration;
            if (duration != nil) {
                call.resolve(["value":round(CMTimeGetSeconds(duration!))])
            } else {
                call.resolve(["value":0])
            }
        } else {
            call.resolve(["value":0])
        }
    }
}
