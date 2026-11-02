import Flutter
import UIKit
import CoreBluetooth
import AVFoundation
import Photos

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var bridge: ElecLeapBridge?
  override func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      bridge = ElecLeapBridge(controller: controller)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

final class ElecLeapBridge: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  let channel: FlutterMethodChannel
  weak var controller: UIViewController?
  var manager: CBCentralManager!
  let service = CBUUID(string: "9ECA0001-3F55-4F3C-AFF8-0C99D8E7A1B0")
  let writerID = CBUUID(string: "9ECA0002-3F55-4F3C-AFF8-0C99D8E7A1B0")
  let notifyID = CBUUID(string: "9ECA0003-3F55-4F3C-AFF8-0C99D8E7A1B0")
  var peers: [String: CBPeripheral] = [:]
  var found: [String: [String: Any]] = [:]
  var peripheral: CBPeripheral?
  var writer: CBCharacteristic?
  var connectResult: FlutterResult?
  var writeResult: FlutterResult?
  var scanResult: FlutterResult?
  var chunks: [Data] = []
  var timeout: DispatchWorkItem?
  init(controller: FlutterViewController) {
    self.controller = controller
    self.channel = FlutterMethodChannel(name: "elecleap/native", binaryMessenger: controller.binaryMessenger)
    super.init()
    manager = CBCentralManager(delegate: self, queue: .main)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "bleScan":
        self.manager.stopScan(); self.found.removeAll()
        if self.manager.state == .unknown || self.manager.state == .resetting { self.scanResult = result }
        else { self.startScan(result) }
      case "bleStop": self.manager.stopScan(); result(nil)
      case "bleConnect":
        guard let id = call.arguments as? String, let p = self.peers[id] else { result(self.error("设备已离开，请重新扫描")); return }
        self.manager.stopScan()
        self.connectResult?(self.error("连接已被新请求替换")); self.connectResult = result
        self.peripheral = p; self.writer = nil; p.delegate = self
        self.timeout?.cancel()
        let task = DispatchWorkItem { [weak self] in
          guard let self = self, let pending = self.connectResult else { return }
          self.connectResult = nil; pending(self.error("蓝牙连接超时，请重试")); self.manager.cancelPeripheralConnection(p)
        }
        self.timeout = task; DispatchQueue.main.asyncAfter(deadline: .now()+18, execute: task)
        self.manager.connect(p, options: nil)
      case "bleWrite":
        guard let data = call.arguments as? FlutterStandardTypedData, let p = self.peripheral, p.state == .connected, let _ = self.writer else { result(self.error("蓝牙连接不可用")); return }
        guard self.writeResult == nil else { result(self.error("蓝牙传输忙，请稍后重试")); return }
        let count = min(180, p.maximumWriteValueLength(for: .withResponse)), bytes = data.data
        self.chunks = stride(from: 0, to: bytes.count, by: count).map { bytes.subdata(in: $0..<min($0+count,bytes.count)) }
        self.writeResult = result; self.writeNext()
      case "bleDisconnect":
        self.manager.stopScan(); if let p = self.peripheral { self.manager.cancelPeripheralConnection(p) }; self.failed("连接已关闭"); result(nil)
      case "scanQr": self.scanQR(result)
      case "savePhoto": self.savePhoto(call.arguments, result)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
  func error(_ text: String) -> FlutterError { FlutterError(code: "ELECLEAP", message: text, details: nil) }
  func event(_ values: [String: Any]) { channel.invokeMethod("bleEvent", arguments: values) }
  func startScan(_ result: @escaping FlutterResult) {
    guard manager.state == .poweredOn else {
      result(error(manager.state == .unauthorized ? "请在系统设置中为 ElecLeap 开启蓝牙权限" : "请打开手机蓝牙")); return
    }
    manager.scanForPeripherals(withServices: [service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]); result(nil)
  }
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if let result = scanResult, central.state != .unknown && central.state != .resetting { scanResult = nil; startScan(result) }
    if central.state != .poweredOn && central.state != .unknown && central.state != .resetting { failed("蓝牙已关闭或权限不可用") }
  }
  func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
    let id = peripheral.identifier.uuidString, name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "ElecLeap"
    guard name.hasPrefix("ElecLeap") else { return }
    peers[id] = peripheral; found[id] = ["id": id, "name": name, "rssi": RSSI]
    event(["type":"devices","devices": Array(found.values)])
  }
  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) { peripheral.discoverServices([service]) }
  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) { failed("蓝牙连接失败，请重试") }
  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) { failed("蓝牙连接已断开"); event(["type":"disconnected"]) }
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard error == nil, let s = peripheral.services?.first(where: {$0.uuid == service}) else { failed("设备配网服务不匹配"); return }
    peripheral.discoverCharacteristics([writerID,notifyID], for: s)
  }
  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    guard error == nil, let w = service.characteristics?.first(where: {$0.uuid == writerID}), let n = service.characteristics?.first(where: {$0.uuid == notifyID}) else { failed("设备缺少配网特征"); return }
    writer = w; peripheral.setNotifyValue(true, for: n)
  }
  func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    guard characteristic.uuid == notifyID else { return }
    if error != nil || !characteristic.isNotifying { failed("无法订阅设备响应"); return }
    timeout?.cancel(); let result = connectResult; connectResult = nil; result?(nil)
  }
  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    if error != nil { failed("蓝牙接收失败"); return }
    if characteristic.uuid == notifyID, let data = characteristic.value { channel.invokeMethod("bleBytes", arguments: FlutterStandardTypedData(bytes: data)) }
  }
  func writeNext() {
    guard let p = peripheral, let w = writer else { failed("蓝牙连接不可用"); return }
    if chunks.isEmpty { let result = writeResult; writeResult = nil; result?(nil); return }
    p.writeValue(chunks.removeFirst(), for: w, type: .withResponse)
  }
  func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    if error != nil { failed("蓝牙写入失败，请重新连接"); return }; writeNext()
  }
  func failed(_ reason: String) {
    timeout?.cancel(); let c = connectResult, w = writeResult; connectResult = nil; writeResult = nil; writer = nil; chunks.removeAll(); c?(error(reason)); w?(error(reason))
  }
  func scanQR(_ result: @escaping FlutterResult) {
    AVCaptureDevice.requestAccess(for: .video) { allowed in
      DispatchQueue.main.async {
        guard allowed else { result(self.error("请允许相机权限，以扫描设备二维码")); return }
        guard let controller = self.controller, controller.presentedViewController == nil else { result(self.error("请关闭当前窗口后重试")); return }
        let scanner = QRScanner { text in
          if let text = text { result(text) } else { result(self.error("已取消扫码")) }
        }
        scanner.modalPresentationStyle = .fullScreen; controller.present(scanner, animated: true)
      }
    }
  }
  func savePhoto(_ input: Any?, _ result: @escaping FlutterResult) {
    guard let bytes = input as? FlutterStandardTypedData, let image = UIImage(data: bytes.data) else { result(error("图片读取失败")); return }
    let save: (PHAuthorizationStatus) -> Void = { status in
      var allowed = status == .authorized
      if #available(iOS 14, *) { allowed = allowed || status == .limited }
      guard allowed else { DispatchQueue.main.async { result(self.error("请允许添加照片权限")) }; return }
      PHPhotoLibrary.shared().performChanges({ PHAssetChangeRequest.creationRequestForAsset(from: image) }) { success, _ in
        DispatchQueue.main.async { result(success ? nil : self.error("照片保存失败")) }
      }
    }
    if #available(iOS 14, *) { PHPhotoLibrary.requestAuthorization(for: .addOnly, handler: save) }
    else { PHPhotoLibrary.requestAuthorization(save) }
  }
}
final class QRScanner: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  let session = AVCaptureSession()
  var preview: AVCaptureVideoPreviewLayer?
  var completion: ((String?) -> Void)?
  init(completion: @escaping (String?) -> Void) { self.completion = completion; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func viewDidLoad() {
    super.viewDidLoad(); view.backgroundColor = .black
    guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) else { finish(nil); return }
    session.addInput(input); let output = AVCaptureMetadataOutput()
    guard session.canAddOutput(output) else { finish(nil); return }
    session.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr]
    let layer = AVCaptureVideoPreviewLayer(session: session); layer.videoGravity = .resizeAspectFill; view.layer.addSublayer(layer); preview = layer
    let label = UILabel(); label.text = "扫描 ElecLeap 相框上的二维码"; label.textColor = .white; label.textAlignment = .center; label.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(label)
    let cancel = UIButton(type: .system); cancel.setTitle("取消", for: .normal); cancel.tintColor = .white; cancel.translatesAutoresizingMaskIntoConstraints = false; cancel.addTarget(self, action: #selector(cancelScan), for: .touchUpInside); view.addSubview(cancel)
    NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: view.centerXAnchor),label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -90),cancel.centerXAnchor.constraint(equalTo: view.centerXAnchor),cancel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -25)])
    DispatchQueue.global(qos:.userInitiated).async { self.session.startRunning() }
  }
  override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
  @objc func cancelScan() { finish(nil) }
  func finish(_ value: String?) { guard let callback = completion else { return }; completion = nil; DispatchQueue.global().async { self.session.stopRunning() }; dismiss(animated: true) { callback(value) } }
  func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) { if let text = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue { finish(text) } }
}
