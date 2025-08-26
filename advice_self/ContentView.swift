//
//  ContentView.swift
//  advice_self
//
//  Created by x23015xx on 2025/08/08.
//

import SwiftUI
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import PhotosUI
import Photos
import AVFoundation

// アドバイスの種類を定義
enum AdviceType {
    case moveUp, moveDown, moveLeft, moveRight
    case moveToRuleOfThirds, moveToCenterComposition
    case reduceSubjects, improveOverall
}

// 視覚的アドバイスの構造体
struct VisualAdvice {
    let type: AdviceType
    let message: String
    let targetPosition: CGPoint?
    let currentPosition: CGPoint
    let arrowDirection: ArrowDirection?
    let intensity: Double
}

enum ArrowDirection {
    case up, down, left, right, upLeft, upRight, downLeft, downRight
}

enum AdviceTarget {
    case ruleOfThirds, centerComposition, bestComposition
}


// 構図評価の結果を格納する構造体
struct CompositionEvaluation {
    let ruleOfThirdsScore: Double
    let centerCompositionScore: Double
    let bestRule: String
    let overallScore: Double
    let recommendations: [String]
}

// シンプルなカメラビュー
struct SimpleCameraView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onImageCaptured: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = CameraViewController()
        vc.onImageCaptured = { image in
            DispatchQueue.main.async {
                onImageCaptured(image)
                isPresented = false
            }
        }
        vc.onCancel = {
            DispatchQueue.main.async {
                isPresented = false
            }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject {
        let parent: SimpleCameraView
        init(_ parent: SimpleCameraView) { self.parent = parent }
    }
}

// カスタムカメラビューコントローラ（プレビュー上にグリッドを描画）
class CameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    var onImageCaptured: ((UIImage) -> Void)?
    var onCancel: (() -> Void)?

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!

    // 複数レイヤーに分割して描画
    private let thirdsLayer = CAShapeLayer()
    private let cornerLayer = CAShapeLayer()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
        configurePreview()
        configureUI()

        // セッションの実行は UI をブロックしないようにバックグラウンドで開始
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // セッション停止もバックグラウンドで実行
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        // フレームを更新してからパスを再計算
        thirdsLayer.frame = view.bounds
        cornerLayer.frame = view.bounds
        updateGridPath()
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // カメラ入力
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        // 写真出力
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
        }

        session.commitConfiguration()
    }

    private func configurePreview() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)

        // 三分割線レイヤー
        thirdsLayer.frame = view.bounds
        thirdsLayer.fillColor = UIColor.clear.cgColor
        thirdsLayer.strokeColor = UIColor.white.withAlphaComponent(0.6).cgColor
        thirdsLayer.lineWidth = 1.0
        view.layer.addSublayer(thirdsLayer)

        // コーナーマーカー
        cornerLayer.frame = view.bounds
        cornerLayer.fillColor = UIColor.clear.cgColor
        cornerLayer.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
        cornerLayer.lineWidth = 2.0
        view.layer.addSublayer(cornerLayer)

        updateGridPath()
    }

    private func updateGridPath() {
        let w = thirdsLayer.bounds.width
        let h = thirdsLayer.bounds.height

        // 三分割線
        let thirdsPath = UIBezierPath()
        thirdsPath.move(to: CGPoint(x: w / 3.0, y: 0))
        thirdsPath.addLine(to: CGPoint(x: w / 3.0, y: h))
        thirdsPath.move(to: CGPoint(x: w * 2.0 / 3.0, y: 0))
        thirdsPath.addLine(to: CGPoint(x: w * 2.0 / 3.0, y: h))
        thirdsPath.move(to: CGPoint(x: 0, y: h / 3.0))
        thirdsPath.addLine(to: CGPoint(x: w, y: h / 3.0))
        thirdsPath.move(to: CGPoint(x: 0, y: h * 2.0 / 3.0))
        thirdsPath.addLine(to: CGPoint(x: w, y: h * 2.0 / 3.0))
        thirdsLayer.path = thirdsPath.cgPath

        // コーナーマーカー（四隅の短い線）
        let cornerPath = UIBezierPath()
        let markerLen: CGFloat = min(w, h) * 0.06 // 画面サイズに応じた長さ
        // 左上
        cornerPath.move(to: CGPoint(x: 8, y: markerLen + 8))
        cornerPath.addLine(to: CGPoint(x: 8, y: 8))
        cornerPath.addLine(to: CGPoint(x: markerLen + 8, y: 8))
        // 右上
        cornerPath.move(to: CGPoint(x: w - 8, y: markerLen + 8))
        cornerPath.addLine(to: CGPoint(x: w - 8, y: 8))
        cornerPath.addLine(to: CGPoint(x: w - markerLen - 8, y: 8))
        // 左下
        cornerPath.move(to: CGPoint(x: 8, y: h - markerLen - 8))
        cornerPath.addLine(to: CGPoint(x: 8, y: h - 8))
        cornerPath.addLine(to: CGPoint(x: markerLen + 8, y: h - 8))
        // 右下
        cornerPath.move(to: CGPoint(x: w - 8, y: h - markerLen - 8))
        cornerPath.addLine(to: CGPoint(x: w - 8, y: h - 8))
        cornerPath.addLine(to: CGPoint(x: w - markerLen - 8, y: h - 8))
        cornerLayer.path = cornerPath.cgPath
    }

    func configureUI() {
        // キャプチャボタン
        let captureButton = UIButton(type: .system)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.backgroundColor = UIColor.white.withAlphaComponent(0.9)
        captureButton.layer.cornerRadius = 32
        captureButton.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
        view.addSubview(captureButton)

        // キャンセルボタン
        let cancelButton = UIButton(type: .system)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setTitle("キャンセル", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            captureButton.widthAnchor.constraint(equalToConstant: 64),
            captureButton.heightAnchor.constraint(equalToConstant: 64),

            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12)
        ])
    }

    @objc private func captureTapped() {
        let settings = AVCapturePhotoSettings()
        settings.isHighResolutionPhotoEnabled = true
        if photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
            settings.livePhotoVideoCodecType = .jpeg
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

    // MARK: - AVCapturePhotoCaptureDelegate
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Photo capture error: \(error)")
            return
        }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        
        // 撮影した画像をそのまま使用（リサイズなし）
        onImageCaptured?(image)
    }
}

// アプリのメインビュー
struct ContentView: View {
    @State private var originalImage: UIImage? = nil
    @State private var saliencyHeatMapImage: UIImage?
    @State private var boundingRects: [CGRect] = []
    @State private var centroids: [CGPoint] = []
    @State private var binaryImage: UIImage?
    @State private var showBoundingRects: Bool = false
    @State private var showCentroids: Bool = false
    @State private var showBinaryImage: Bool = false
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var showCompositionGrid: Bool = false
    @State private var compositionEvaluation: CompositionEvaluation?
    @State private var showingCamera = false
    @State private var cameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)
    @State private var autoAnalyzeAfterCapture = true
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var visualAdvices: [VisualAdvice] = []
    @State private var showVisualAdvice: Bool = false
    @State private var selectedAdviceTarget: AdviceTarget = .bestComposition
    @State private var isAnalyzing = false
    
    @State private var unprocessedOriginalImage: UIImage? = nil  // 未加工の元画像を保存
    @State private var showOriginalImage: Bool = true  // デフォルトでtrueに設定
    
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Section
                    headerSection
                    
                    // Image Selection Cards
                    imageSelectionSection
                    
                    // Main Image Display
                    imageDisplayCard
                    
                    // Analysis Controls
                    if originalImage != nil {
                        analysisControlsSection
                    }
                    
                    // Results Section
                    resultsSection
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
            }
            .navigationBarHidden(true)
            .background(
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.systemGray6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .sheet(isPresented: $showingCamera) {
            SimpleCameraView(isPresented: $showingCamera) { image in
                // 撮影した画像をそのまま使用（リサイズなし）
                originalImage = image
                unprocessedOriginalImage = image
                resetAnalysisData()
                
                if autoAnalyzeAfterCapture {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        performSaliencyAnalysis()
                    }
                }
            }
        }
        .onChange(of: selectedItem) { newItem in
            Task {
                if let newItem = newItem {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        if let uiImage = UIImage(data: data) {
                            await MainActor.run {
                                // 選択した画像をそのまま使用（リサイズなし）
                                originalImage = uiImage
                                unprocessedOriginalImage = uiImage
                                resetAnalysisData()
                            }
                        }
                    }
                }
            }
        }
        .alert("注意", isPresented: $showingAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("構図分析")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text("写真の構図を分析して最適な配置をアドバイスします")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }
    
    @ViewBuilder
    private var imageSelectionSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Photo Library Button
                PhotosPicker(
                    selection: $selectedItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    ActionCard(
                        icon: "photo.on.rectangle.angled",
                        title: "写真選択",
                        subtitle: "ライブラリから",
                        color: .blue
                    )
                }
                
                // Camera Button
                Button(action: {
                    if cameraAvailable {
                        showingCamera = true
                    } else {
                        alertMessage = "カメラが利用できません"
                        showingAlert = true
                    }
                }) {
                    ActionCard(
                        icon: "camera.fill",
                        title: "撮影",
                        subtitle: "カメラで撮影",
                        color: cameraAvailable ? .green : .gray
                    )
                }
                .disabled(!cameraAvailable)
            }
            
            // Auto Analysis Toggle
            Toggle(isOn: $autoAnalyzeAfterCapture) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.orange)
                    Text("撮影後に自動分析")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .orange))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    @ViewBuilder
    private var imageDisplayCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if originalImage != nil {
                Text("画像プレビュー")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
                    .aspectRatio(originalImage?.size ?? CGSize(width: 16, height: 9), contentMode: .fit)
                    .frame(maxHeight: 320)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
                
                if let image = originalImage, let unprocessedImage = unprocessedOriginalImage {
                    EnhancedImageDisplayView(
                        originalImage: image,
                        unprocessedOriginalImage: unprocessedImage,  // 未加工画像を渡す
                        binaryImage: binaryImage,
                        saliencyHeatMapImage: saliencyHeatMapImage,
                        showOriginalImage: showOriginalImage,
                        showBinaryImage: showBinaryImage,
                        showBoundingRects: showBoundingRects,
                        showCompositionGrid: showCompositionGrid,
                        showCentroids: showCentroids,
                        showVisualAdvice: showVisualAdvice,
                        boundingRects: boundingRects,
                        centroids: centroids,
                        visualAdvices: visualAdvices
                    )
                    //.aspectRatio(image.size, contentMode: .fit)
                    //.frame(maxHeight: 320)
                    //.clipped()
                } else {
                    ModernPlaceholderView()
                        .frame(height: 320)
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    @ViewBuilder
    private var analysisControlsSection: some View {
        VStack(spacing: 20) {
            // Main Analysis Button
            Button(action: {
                performSaliencyAnalysis()
            }) {
                HStack(spacing: 12) {
                    if isAnalyzing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "viewfinder.circle.fill")
                            .font(.title2)
                    }
                    
                    Text(isAnalyzing ? "分析中..." : "分析開始")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .disabled(isAnalyzing)
            }
            
            // Display Options
            if !boundingRects.isEmpty || binaryImage != nil {
                displayOptionsSection
            }
            
        }
        .padding(.horizontal, 20)
    }
    
    
    
    
    @ViewBuilder
    private var displayOptionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("表示オプション")
                .font(.headline)
                .fontWeight(.semibold)
                .padding(.horizontal, 4)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                OptionToggleCard(
                    isOn: $showOriginalImage,
                    icon: "photo",
                    title: "元画像のみ",  // より明確な名称に変更
                    color: .blue
                )
                
                OptionToggleCard(
                    isOn: $showBoundingRects,
                    icon: "rectangle.dashed",
                    title: "検出領域",
                    color: .red
                )
                
                OptionToggleCard(
                    isOn: $showCentroids,
                    icon: "target",
                    title: "重心点",
                    color: .purple
                )
                
                OptionToggleCard(
                    isOn: $showBinaryImage,
                    icon: "circle.lefthalf.filled",
                    title: "二値化画像",
                    color: .orange
                )
                
                OptionToggleCard(
                    isOn: $showCompositionGrid,
                    icon: "grid",
                    title: "構図グリッド",
                    color: .cyan
                )
            }
            // Composition Analysis and Visual Advice
            if !centroids.isEmpty {
                VStack(spacing: 12) {
                    Button(action: evaluateComposition) {
                        AnalysisButton(
                            icon: "chart.bar.fill",
                            title: "構図評価",
                            color: .indigo
                        )
                    }
                    
                    Button(action: {
                        if !showVisualAdvice {
                            generateVisualAdvice()
                        }
                        showVisualAdvice.toggle()
                    }) {
                        AnalysisButton(
                            icon: "lightbulb.fill",
                            title: showVisualAdvice ? "アドバイス非表示" : "視覚的アドバイス",
                            color: .pink
                        )
                    }
                }
            }
            
            // Advice Target Picker
            if showVisualAdvice {
                adviceTargetSection
            }
        }
    }
    
    @ViewBuilder
    private var adviceTargetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("目標構図")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            Picker("Target", selection: $selectedAdviceTarget) {
                Text("最適配置").tag(AdviceTarget.bestComposition)
                Text("三分割法").tag(AdviceTarget.ruleOfThirds)
                Text("中央配置").tag(AdviceTarget.centerComposition)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal, 4)
        }
        .onChange(of: selectedAdviceTarget) { _ in
            generateVisualAdvice()
        }
    }
    
    @ViewBuilder
    private var resultsSection: some View {
        VStack(spacing: 16) {
            if let evaluation = compositionEvaluation {
                compositionResultCard(evaluation)
            }

            if !boundingRects.isEmpty {
                detectionResultCard
            }

            if originalImage != nil {
                saveButton
                resetButton
            }
        }
    }

    @ViewBuilder
    private var saveButton: some View {
        Button(action: {
            // 表示中の画像を優先的に保存
            let imageToSave: UIImage?
            if showBinaryImage {
                imageToSave = binaryImage
            } else if showOriginalImage {
                imageToSave = unprocessedOriginalImage ?? originalImage
            } else {
                imageToSave = originalImage
            }
            saveImageToPhotos(imageToSave)
        }) {
            HStack {
                Image(systemName: "square.and.arrow.down")
                Text("写真を保存")
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                LinearGradient(
                    colors: [.green, .blue],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(12)
        }
    }
    
    @ViewBuilder
    private func compositionResultCard(_ evaluation: CompositionEvaluation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "ruler.fill")
                    .foregroundColor(.indigo)
                    .font(.title2)
                
                Text("構図評価結果")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                ScoreView(score: evaluation.overallScore)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("最適構図:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    Text(evaluation.bestRule)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
                
                HStack(spacing: 20) {
                    ScoreItem(
                        title: "三分割法",
                        score: evaluation.ruleOfThirdsScore,
                        color: .yellow
                    )
                    
                    ScoreItem(
                        title: "中央配置",
                        score: evaluation.centerCompositionScore,
                        color: .red
                    )
                }
                
                if !evaluation.recommendations.isEmpty {
                    recommendationsSection(evaluation.recommendations)
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    @ViewBuilder
    private func recommendationsSection(_ recommendations: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.orange)
                Text("改善提案")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(recommendations, id: \.self) { recommendation in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 4, height: 4)
                            .padding(.top, 6)
                        
                        Text(recommendation)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.leading, 8)
        }
    }
    
    @ViewBuilder
    private var detectionResultCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "viewfinder")
                    .foregroundColor(.green)
                    .font(.title2)
                
                Text("検出結果")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(boundingRects.count)個の領域")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            
            if boundingRects.count > 1 || boundingRects.count == 0 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("主題を明確にすると構図が改善されます")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    @ViewBuilder
    private var resetButton: some View {
        Button(action: resetImage) {
            HStack {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                Text("リセット")
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                LinearGradient(
                    colors: [.red, .pink],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(12)
        }
    }
    
    // MARK: - Functions
    
    // 処理用の低解像度画像を作成する関数
    func createProcessingImage(from originalImage: UIImage, maxDimension: CGFloat = 800) -> UIImage {
        let originalSize = originalImage.size
        let maxOriginalDimension = max(originalSize.width, originalSize.height)
        
        print("📊 元画像サイズ: \(Int(originalSize.width)) × \(Int(originalSize.height)) px")
        
        // 既に十分小さい場合はそのまま返す
        if maxOriginalDimension <= maxDimension {
            print("✅ 画像サイズが十分小さいため、リサイズをスキップ")
            return originalImage
        }
        
        // アスペクト比を保持しながらリサイズ
        let scale = maxDimension / maxOriginalDimension
        let newSize = CGSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )
        
        print("🔄 処理用サイズ: \(Int(newSize.width)) × \(Int(newSize.height)) px (縮小率: \(Int((1.0 - scale) * 100))%)")
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { _ in
            originalImage.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        return resizedImage
    }
    
    func performSaliencyAnalysis() {
        guard let image = originalImage, let cgImage = image.cgImage else { return }
        
        isAnalyzing = true
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // 処理用の低解像度画像を作成（最大800px）
        let processingImage = createProcessingImage(from: image, maxDimension: 800)
        guard let processingCGImage = processingImage.cgImage else {
            isAnalyzing = false
            return
        }
        
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        
        // 処理用画像の向きを考慮してVisionリクエストのオプションを設定
        let orientation = CGImagePropertyOrientation(processingImage.imageOrientation)
        let handler = VNImageRequestHandler(cgImage: processingCGImage, orientation: orientation, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async {
            let visionStartTime = CFAbsoluteTimeGetCurrent()
            do {
                try handler.perform([request])
                let visionEndTime = CFAbsoluteTimeGetCurrent()
                print("🔍 Vision分析時間: \(String(format: "%.3f", visionEndTime - visionStartTime))秒")
                
                DispatchQueue.main.async {
                    self.isAnalyzing = false
                    guard let observation = request.results?.first as? VNSaliencyImageObservation else {
                        return
                    }
                    
                    let processingStartTime = CFAbsoluteTimeGetCurrent()
                    
                    // 低解像度で顕著性マップを作成し、バウンディングボックス検出も低解像度で実行
                    if let heatmapImage = self.createSaliencyHeatmapImage(from: observation, targetSize: processingImage.size),
                       let binaryImage = self.binarizeAlphaWithKernel(heatmapImage, threshold: 0.05) {
                        
                        // 表示用に元画像サイズの顕著性マップを作成
                        if let displayHeatmap = self.createSaliencyHeatmapImage(from: observation, targetSize: image.size),
                           let displayBinary = self.binarizeAlphaWithKernel(displayHeatmap, threshold: 0.05) {
                            self.saliencyHeatMapImage = displayBinary
                            self.binaryImage = displayBinary
                        } else {
                            // フォールバック：低解像度画像をスケールアップ
                            self.saliencyHeatMapImage = binaryImage
                            self.binaryImage = binaryImage
                        }
                        
                        // 低解像度画像でバウンディングボックス検出を実行し、結果を元画像サイズにスケール
                        self.detectBoundingRects(from: binaryImage, originalImageSize: image.size, processingImageSize: processingImage.size)
                        
                        let processingEndTime = CFAbsoluteTimeGetCurrent()
                        let totalTime = processingEndTime - startTime
                        print("⚡ 後処理時間: \(String(format: "%.3f", processingEndTime - processingStartTime))秒")
                        print("🎯 総処理時間: \(String(format: "%.3f", totalTime))秒")
                        
                        if self.autoAnalyzeAfterCapture {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                self.evaluateComposition()
                            }
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isAnalyzing = false
                    self.alertMessage = "顕著性分析に失敗しました: \(error.localizedDescription)"
                    self.showingAlert = true
                }
            }
        }
    }
    
    func createSaliencyHeatmapImage(from observation: VNSaliencyImageObservation, targetSize: CGSize) -> UIImage? {
        let pixelBuffer = observation.pixelBuffer
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // 画像の向きを正しく設定
        let orientedImage = ciImage.oriented(forExifOrientation: Int32(CGImagePropertyOrientation.up.rawValue))
        
        let colorMatrixFilter = CIFilter.colorMatrix()
        colorMatrixFilter.inputImage = orientedImage
        
        let vector = CIVector(x: 1, y: 0, z: 0, w: 0)
        colorMatrixFilter.rVector = vector
        colorMatrixFilter.gVector = vector
        colorMatrixFilter.bVector = vector
        colorMatrixFilter.aVector = vector
        
        guard let outputCIImage = colorMatrixFilter.outputImage else { return nil }
        
        // 元画像のサイズ（targetSize）にリサイズ
        let scaleX = targetSize.width / outputCIImage.extent.width
        let scaleY = targetSize.height / outputCIImage.extent.height
        let scaledImage = outputCIImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: CGRect(origin: .zero, size: targetSize)) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    
    func binarizeAlphaWithKernel(_ inputImage: UIImage, threshold: Float = 0.5) -> UIImage? {
        guard let cgImage = inputImage.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        
        let kernelString = """
    kernel vec4 alphaThresholdFilter(__sample s, float threshold) {
        float alpha = s.a;
        float color = alpha > threshold ? 1.0 : 0.0;
        return vec4(vec3(color), 1.0);
    }
    """
        
        guard let kernel = CIColorKernel(source: kernelString) else { return nil }
        
        let extent = ciImage.extent
        let arguments = [ciImage, threshold] as [Any]
        
        guard let outputCIImage = kernel.apply(extent: extent, arguments: arguments) else { return nil }
        
        let context = CIContext()
        if let outputCGImage = context.createCGImage(outputCIImage, from: outputCIImage.extent) {
            return UIImage(cgImage: outputCGImage)
        }
        
        return nil
    }
    
    func detectBoundingRects(from binaryImage: UIImage, originalImageSize: CGSize, processingImageSize: CGSize) {
        guard let cgImage = binaryImage.cgImage else { return }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
        
        guard let ctx = context else { return }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var visited = Array(repeating: Array(repeating: false, count: width), count: height)
        var detectedRects: [CGRect] = []
        var detectedCentroids: [CGPoint] = []
        
        // スケール計算（処理画像 → 元画像）
        let scaleX = originalImageSize.width / processingImageSize.width
        let scaleY = originalImageSize.height / processingImageSize.height
        
        for y in 0..<height {
            for x in 0..<width {
                if !visited[y][x] && isWhitePixel(pixelData: pixelData, x: x, y: y, width: width) {
                    let (boundingRect, centroid, pixelCount) = getBoundingRectAndCentroid(
                        pixelData: pixelData,
                        startX: x,
                        startY: y,
                        width: width,
                        height: height,
                        visited: &visited
                    )
                    
                    // 最小サイズのフィルタリング（処理解像度基準）
                    let minSize = CGFloat(max(2, min(width, height) / 10)) // 処理画像に応じて調整、これより大きいバウンディングボックスを検出
                    let minPixelCount = max(10, (width * height) / 16000) // 処理画像に応じて調整
                    
                    if boundingRect.width > minSize && boundingRect.height > minSize && pixelCount > minPixelCount {
                        // 結果を元画像サイズにスケールアップ
                        let scaledRect = CGRect(
                            x: boundingRect.minX * scaleX,
                            y: boundingRect.minY * scaleY,
                            width: boundingRect.width * scaleX,
                            height: boundingRect.height * scaleY
                        )
                        
                        let scaledCentroid = CGPoint(
                            x: centroid.x * scaleX,
                            y: centroid.y * scaleY
                        )
                        
                        detectedRects.append(scaledRect)
                        detectedCentroids.append(scaledCentroid)
                    }
                }
            }
        }
        
        DispatchQueue.main.async {
            self.boundingRects = detectedRects
            self.centroids = detectedCentroids
        }
    }
    
    func isWhitePixel(pixelData: [UInt8], x: Int, y: Int, width: Int) -> Bool {
        let pixelIndex = (y * width + x) * 4
        let red = pixelData[pixelIndex]
        let green = pixelData[pixelIndex + 1]
        let blue = pixelData[pixelIndex + 2]
        
        // 二値化画像では純粋な白（255）である必要がある
        return red >= 250 && green >= 250 && blue >= 250
    }
    
    func getBoundingRectAndCentroid(pixelData: [UInt8], startX: Int, startY: Int, width: Int, height: Int, visited: inout [[Bool]]) -> (CGRect, CGPoint, Int) {
        var minX = startX, maxX = startX, minY = startY, maxY = startY
        var sumX = 0, sumY = 0, pixelCount = 0
        var stack: [(Int, Int)] = [(startX, startY)]
        
        while !stack.isEmpty {
            let (x, y) = stack.removeLast()
            
            if x < 0 || x >= width || y < 0 || y >= height || visited[y][x] {
                continue
            }
            
            if !isWhitePixel(pixelData: pixelData, x: x, y: y, width: width) {
                continue
            }
            
            visited[y][x] = true
            
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
            
            sumX += x
            sumY += y
            pixelCount += 1
            
            stack.append((x + 1, y))
            stack.append((x - 1, y))
            stack.append((x, y + 1))
            stack.append((x, y - 1))
        }
        
        let boundingRect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        let centroid = CGPoint(
            x: pixelCount > 0 ? CGFloat(sumX) / CGFloat(pixelCount) : CGFloat(minX),
            y: pixelCount > 0 ? CGFloat(sumY) / CGFloat(pixelCount) : CGFloat(minY)
        )
        
        return (boundingRect, centroid, pixelCount)
    }
    
    func evaluateComposition() {
        guard !centroids.isEmpty, let image = originalImage else { return }
        
        let imageSize = CGSize(width: image.size.width, height: image.size.height)
        let mainCentroid = centroids[0]
        
        let ruleOfThirdsScore = evaluateRuleOfThirds(centroid: mainCentroid, imageSize: imageSize)
        let centerCompositionScore = evaluateCenterComposition(centroid: mainCentroid, imageSize: imageSize)
        
        let scores = [
            ("三分割法", ruleOfThirdsScore),
            ("中央配置", centerCompositionScore)
        ]
        let bestRule = scores.max(by: { $0.1 < $1.1 })?.0 ?? "不明"
        
        let totalScore = max(ruleOfThirdsScore, centerCompositionScore)
        
        var recommendations = generateRecommendations(
            centroid: mainCentroid,
            imageSize: imageSize,
            ruleOfThirdsScore: ruleOfThirdsScore,
            centerScore: centerCompositionScore
        )
        
        if centroids.count > 1 {
            recommendations.append("主題を1つに絞ることで構図が改善されます")
        }
        
        self.compositionEvaluation = CompositionEvaluation(
            ruleOfThirdsScore: ruleOfThirdsScore,
            centerCompositionScore: centerCompositionScore,
            bestRule: bestRule,
            overallScore: totalScore,
            recommendations: recommendations
        )
        
        if autoAnalyzeAfterCapture {
            generateVisualAdvice()
        }
    }
    
    func evaluateRuleOfThirds(centroid: CGPoint, imageSize: CGSize) -> Double {
        let thirdX1 = imageSize.width / 3
        let thirdX2 = imageSize.width * 2 / 3
        let thirdY1 = imageSize.height / 3
        let thirdY2 = imageSize.height * 2 / 3
        
        let intersectionPoints = [
            CGPoint(x: thirdX1, y: thirdY1),
            CGPoint(x: thirdX2, y: thirdY1),
            CGPoint(x: thirdX1, y: thirdY2),
            CGPoint(x: thirdX2, y: thirdY2)
        ]
        
        var bestScore = 0.0
        for point in intersectionPoints {
            let distance = sqrt(pow(centroid.x - point.x, 2) + pow(centroid.y - point.y, 2))
            let maxDistance = sqrt(pow(imageSize.width/2, 2) + pow(imageSize.height/2, 2))
            let score = max(0, 100 - (distance / maxDistance) * 100)
            bestScore = max(bestScore, score)
        }
        
        return bestScore
    }
    
    func evaluateCenterComposition(centroid: CGPoint, imageSize: CGSize) -> Double {
        let center = CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let distance = sqrt(pow(centroid.x - center.x, 2) + pow(centroid.y - center.y, 2))
        let maxDistance = sqrt(pow(imageSize.width/2, 2) + pow(imageSize.height/2, 2))
        return max(0, 100 - (distance / maxDistance) * 100)
    }
    
    func generateRecommendations(centroid: CGPoint, imageSize: CGSize, ruleOfThirdsScore: Double, centerScore: Double) -> [String] {
        var recommendations: [String] = []
        
        if centroid.x < imageSize.width * 0.3 {
            recommendations.append("被写体をもう少し右に配置してみましょう")
        } else if centroid.x > imageSize.width * 0.7 {
            recommendations.append("被写体をもう少し左に配置してみましょう")
        }
        
        if centroid.y < imageSize.height * 0.3 {
            recommendations.append("被写体をもう少し下に配置してみましょう")
        } else if centroid.y > imageSize.height * 0.7 {
            recommendations.append("被写体をもう少し上に配置してみましょう")
        }
        
        if ruleOfThirdsScore < 50 && centerScore < 50 {
            recommendations.append("三分割点や中央付近への配置を検討してみましょう")
        }
        
        if max(ruleOfThirdsScore, centerScore) < 30 {
            recommendations.append("構図を大幅に変更することをお勧めします")
        }
        
        return Array(recommendations.prefix(3))
    }
    
    func resetAnalysisData() {
        saliencyHeatMapImage = nil
        binaryImage = nil
        boundingRects = []
        centroids = []
        showBoundingRects = false
        showCentroids = false
        showBinaryImage = false
        showOriginalImage = true
        compositionEvaluation = nil
        showCompositionGrid = false
        visualAdvices = []
        showVisualAdvice = false
        // unprocessedOriginalImageはリセットしない（元画像は保持）
    }
    
    func resetImage() {
        originalImage = nil
        unprocessedOriginalImage = nil  // こちらでリセット
        resetAnalysisData()
        selectedItem = nil
    }

    // 写真を写真ライブラリに保存する
    func saveImageToPhotos(_ image: UIImage?) {
        guard let image = image else {
            alertMessage = "保存する画像がありません"
            showingAlert = true
            return
        }

        // 写真ライブラリのアクセス権を確認し、保存する
        PHPhotoLibrary.requestAuthorization { status in
            switch status {
            case .authorized, .limited:
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }) { success, error in
                    DispatchQueue.main.async {
                        if success {
                            alertMessage = "写真を保存しました"
                        } else {
                            alertMessage = "写真の保存に失敗しました: \(error?.localizedDescription ?? "不明なエラー")"
                        }
                        showingAlert = true
                    }
                }
            case .denied, .restricted, .notDetermined:
                DispatchQueue.main.async {
                    alertMessage = "写真ライブラリへのアクセスが許可されていません"
                    showingAlert = true
                }
            @unknown default:
                DispatchQueue.main.async {
                    alertMessage = "予期しないエラー"
                    showingAlert = true
                }
            }
        }
    }
}

// MARK: - 視覚的アドバイス生成関数
extension ContentView {
    
    func generateVisualAdvice() {
        guard !centroids.isEmpty, let image = originalImage else { return }
        
        let imageSize = CGSize(width: image.size.width, height: image.size.height)
        let mainCentroid = centroids[0]
        var advices: [VisualAdvice] = []
        
        let ruleOfThirdsScore = evaluateRuleOfThirds(centroid: mainCentroid, imageSize: imageSize)
        let centerScore = evaluateCenterComposition(centroid: mainCentroid, imageSize: imageSize)
        
        let target = selectedAdviceTarget == .bestComposition
        ? determineBestTarget(ruleOfThirds: ruleOfThirdsScore, center: centerScore)
        : selectedAdviceTarget
        
        if let targetAdvice = generateTargetPositionAdvice(
            currentPosition: mainCentroid,
            target: target,
            imageSize: imageSize
        ) {
            advices.append(targetAdvice)
        }
        
        if centroids.count > 1 {
            let multiSubjectAdvice = VisualAdvice(
                type: .reduceSubjects,
                message: "主題を1つに絞りましょう",
                targetPosition: nil,
                currentPosition: mainCentroid,
                arrowDirection: nil,
                intensity: 0.8
            )
            advices.append(multiSubjectAdvice)
        }
        
        self.visualAdvices = advices
    }
    
    func determineBestTarget(ruleOfThirds: Double, center: Double) -> AdviceTarget {
        let scores = [
            (AdviceTarget.ruleOfThirds, ruleOfThirds),
            (AdviceTarget.centerComposition, center)
        ]
        
        return scores.max(by: { $0.1 < $1.1 })?.0 ?? .ruleOfThirds
    }
    
    func generateTargetPositionAdvice(
        currentPosition: CGPoint,
        target: AdviceTarget,
        imageSize: CGSize
    ) -> VisualAdvice? {
        
        let targetPosition = getTargetPosition(target: target, imageSize: imageSize, currentPosition: currentPosition)
        let direction = calculateDirection(from: currentPosition, to: targetPosition)
        let distance = sqrt(pow(currentPosition.x - targetPosition.x, 2) + pow(currentPosition.y - targetPosition.y, 2))
        let intensity = min(1.0, distance / 100.0)
        
        let message = generateDirectionalMessage(direction: direction, target: target)
        
        return VisualAdvice(
            type: getAdviceType(for: target),
            message: message,
            targetPosition: targetPosition,
            currentPosition: currentPosition,
            arrowDirection: direction,
            intensity: intensity
        )
    }
    
    func getTargetPosition(target: AdviceTarget, imageSize: CGSize, currentPosition: CGPoint) -> CGPoint {
        switch target {
        case .ruleOfThirds:
            let points = [
                CGPoint(x: imageSize.width / 3, y: imageSize.height / 3),
                CGPoint(x: imageSize.width * 2 / 3, y: imageSize.height / 3),
                CGPoint(x: imageSize.width / 3, y: imageSize.height * 2 / 3),
                CGPoint(x: imageSize.width * 2 / 3, y: imageSize.height * 2 / 3)
            ]
            
            return points.min(by: { point1, point2 in
                let dist1 = sqrt(pow(currentPosition.x - point1.x, 2) + pow(currentPosition.y - point1.y, 2))
                let dist2 = sqrt(pow(currentPosition.x - point2.x, 2) + pow(currentPosition.y - point2.y, 2))
                return dist1 < dist2
            }) ?? points[0]
            
        case .centerComposition:
            return CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
            
        case .bestComposition:
            return CGPoint(x: imageSize.width / 3, y: imageSize.height / 3)
        }
    }
    
    func calculateDirection(from: CGPoint, to: CGPoint) -> ArrowDirection {
        let dx = to.x - from.x
        let dy = to.y - from.y
        
        let angle = atan2(dy, dx)
        let degrees = angle * 180 / .pi
        
        if degrees >= -22.5 && degrees < 22.5 {
            return .right
        } else if degrees >= 22.5 && degrees < 67.5 {
            return .downRight
        } else if degrees >= 67.5 && degrees < 112.5 {
            return .down
        } else if degrees >= 112.5 && degrees < 157.5 {
            return .downLeft
        } else if degrees >= 157.5 || degrees < -157.5 {
            return .left
        } else if degrees >= -157.5 && degrees < -112.5 {
            return .upLeft
        } else if degrees >= -112.5 && degrees < -67.5 {
            return .up
        } else {
            return .upRight
        }
    }
    
    func generateDirectionalMessage(direction: ArrowDirection, target: AdviceTarget) -> String {
        let targetName = getTargetName(target)
        
        switch direction {
        case .up:
            return "\(targetName)に向けて上に移動"
        case .down:
            return "\(targetName)に向けて下に移動"
        case .left:
            return "\(targetName)に向けて左に移動"
        case .right:
            return "\(targetName)に向けて右に移動"
        case .upLeft:
            return "\(targetName)に向けて左上に移動"
        case .upRight:
            return "\(targetName)に向けて右上に移動"
        case .downLeft:
            return "\(targetName)に向けて左下に移動"
        case .downRight:
            return "\(targetName)に向けて右下に移動"
        }
    }
    
    func getTargetName(_ target: AdviceTarget) -> String {
        switch target {
        case .ruleOfThirds:
            return "三分割点"
        case .centerComposition:
            return "中央"
        case .bestComposition:
            return "最適位置"
        }
    }
    
    func getAdviceType(for target: AdviceTarget) -> AdviceType {
        switch target {
        case .ruleOfThirds:
            return .moveToRuleOfThirds
        case .centerComposition:
            return .moveToCenterComposition
        case .bestComposition:
            return .moveToRuleOfThirds
        }
    }
}

// MARK: - Extensions

extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

// MARK: - Modern UI Components

struct ActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            VStack(spacing: 2) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct OptionToggleCard: View {
    @Binding var isOn: Bool
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(isOn ? color : .secondary)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isOn ? .primary : .secondary)
                
                Spacer()
                
                Circle()
                    .fill(isOn ? color : Color(.systemGray4))
                    .frame(width: 12, height: 12)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isOn ? color.opacity(0.3) : Color(.separator), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct AnalysisButton: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
            
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
            LinearGradient(
                colors: [color, color.opacity(0.8)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(12)
    }
}

struct ScoreView: View {
    let score: Double
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(Int(score))")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(scoreColor)
            
            Text("点")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 60, height: 60)
        .background(
            Circle()
                .fill(scoreColor.opacity(0.1))
        )
        .overlay(
            Circle()
                .stroke(scoreColor, lineWidth: 2)
        )
    }
    
    var scoreColor: Color {
        if score >= 70 { return .green }
        else if score >= 50 { return .orange }
        else { return .red }
    }
}

struct ScoreItem: View {
    let title: String
    let score: Double
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            
            Text("\(Int(score))点")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
    }
}

struct ModernPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            VStack(spacing: 4) {
                Text("画像を選択してください")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("写真を選択するか撮影して構図分析を開始")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Enhanced Image Display Components

struct EnhancedImageDisplayView: View {
    let originalImage: UIImage
    let unprocessedOriginalImage: UIImage  // 未加工画像のパラメータを追加
    let binaryImage: UIImage?
    let saliencyHeatMapImage: UIImage?
    let showOriginalImage: Bool
    let showBinaryImage: Bool
    let showBoundingRects: Bool
    let showCompositionGrid: Bool
    let showCentroids: Bool
    let showVisualAdvice: Bool
    let boundingRects: [CGRect]
    let centroids: [CGPoint]
    let visualAdvices: [VisualAdvice]
    
    
    var body: some View {
        Group {
            if showBinaryImage && binaryImage != nil {
                BinaryImageView(binaryImage: binaryImage!)
            } else if showOriginalImage {
                // 未加工の元画像を表示
                UnprocessedImageView(unprocessedImage: unprocessedOriginalImage)
            } else {
                // 加工された画像（顕著性マップ付き）を表示
                OriginalImageView(
                    originalImage: originalImage,
                    saliencyHeatMapImage: saliencyHeatMapImage
                )
            }
        }
        .overlay(BoundingRectsOverlay(show: showBoundingRects, rects: boundingRects, imageSize: originalImage.size))
        .overlay(CompositionGridOverlay(show: showCompositionGrid))
        .overlay(CentroidsOverlay(show: showCentroids, centroids: centroids, imageSize: originalImage.size))
        .overlay(VisualAdviceOverlay(show: showVisualAdvice, advices: visualAdvices, imageSize: originalImage.size))
    }
}




struct UnprocessedImageView: View {
    let unprocessedImage: UIImage

    var body: some View {
        Image(uiImage: unprocessedImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
}

struct BinaryImageView: View {
    let binaryImage: UIImage

    var body: some View {
        Image(uiImage: binaryImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
}

struct OriginalImageView: View {
    let originalImage: UIImage
    let saliencyHeatMapImage: UIImage?

    var body: some View {
        ZStack {
            Image(uiImage: originalImage)
                .resizable()
                .aspectRatio(contentMode: .fit)

            HeatmapOverlay(heatmapImage: saliencyHeatMapImage)
        }
    }
}
               




struct HeatmapOverlay: View {
    let heatmapImage: UIImage?

    var body: some View {
        Group {
            if let heatmapImage = heatmapImage {
                Image(uiImage: heatmapImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .blendMode(.multiply)
            }
        }
    }
}

// Overlays used on top of the original image display. These map the internal analysis coordinates to the actual view size.
struct BoundingRectsOverlay: View {
    let show: Bool
    let rects: [CGRect] // in original image coordinate space
    let imageSize: CGSize

    var body: some View {
        GeometryReader { geo in
            if show {
                let scaleX = geo.size.width / imageSize.width
                let scaleY = geo.size.height / imageSize.height

                ForEach(Array(rects.enumerated()), id: \.offset) { _, rect in
                    // Map rect from original image size -> view size
                    let r = CGRect(x: rect.origin.x * scaleX,
                                   y: rect.origin.y * scaleY,
                                   width: rect.size.width * scaleX,
                                   height: rect.size.height * scaleY)

                    Path { path in
                        path.addRect(r)
                    }
                    .stroke(Color.yellow.opacity(0.9), lineWidth: 2)
                    .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct CompositionGridOverlay: View {
    let show: Bool

    var body: some View {
        GeometryReader { geo in
            if show {
                let w = geo.size.width
                let h = geo.size.height

                ZStack {
                    // 三分割法の線
                    Path { path in
                        path.move(to: CGPoint(x: w / 3, y: 0))
                        path.addLine(to: CGPoint(x: w / 3, y: h))
                        path.move(to: CGPoint(x: w * 2 / 3, y: 0))
                        path.addLine(to: CGPoint(x: w * 2 / 3, y: h))
                        path.move(to: CGPoint(x: 0, y: h / 3))
                        path.addLine(to: CGPoint(x: w, y: h / 3))
                        path.move(to: CGPoint(x: 0, y: h * 2 / 3))
                        path.addLine(to: CGPoint(x: w, y: h * 2 / 3))
                    }
                    .stroke(Color.white.opacity(0.85), lineWidth: 1.2)
                    .blendMode(.normal)
                    .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)

                    // 三分割法の交点
                    ForEach(0..<4, id: \.self) { index in
                        let points = [
                            CGPoint(x: w / 3, y: h / 3),
                            CGPoint(x: w * 2 / 3, y: h / 3),
                            CGPoint(x: w / 3, y: h * 2 / 3),
                            CGPoint(x: w * 2 / 3, y: h * 2 / 3)
                        ]
                        Circle()
                            .fill(Color.yellow)
                            .frame(width: min(w,h) * 0.025, height: min(w,h) * 0.025)
                            .overlay(
                                Circle().stroke(Color.white, lineWidth: 1.0)
                            )
                            .position(points[index])
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    }

                    // 中央点
                    Circle()
                        .fill(Color.red)
                        .frame(width: min(w,h) * 0.03, height: min(w,h) * 0.03)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.0))
                        .position(x: w / 2, y: h / 2)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)

                    // 凡例
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Circle().fill(Color.yellow).frame(width: 6, height: 6)
                            Text("三分割点").font(.caption2).fontWeight(.medium)
                        }
                        HStack(spacing: 4) {
                            Circle().fill(Color.red).frame(width: 6, height: 6)
                            Text("中央点").font(.caption2).fontWeight(.medium)
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.7))
                    )
                    .position(x: w * 0.85, y: h * 0.1)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct CentroidsOverlay: View {
    let show: Bool
    let centroids: [CGPoint] // in original image coordinate space
    let imageSize: CGSize

    var body: some View {
        GeometryReader { geo in
            if show {
                let scaleX = geo.size.width / imageSize.width
                let scaleY = geo.size.height / imageSize.height

                ForEach(Array(centroids.enumerated()), id: \.offset) { _, pt in
                    let mapped = CGPoint(x: pt.x * scaleX, y: pt.y * scaleY)
                    Circle()
                        .fill(Color.blue)//重心点の色
                        .frame(width: min(geo.size.width, geo.size.height) * 0.03,
                               height: min(geo.size.width, geo.size.height) * 0.03)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1))
                        .position(mapped)
                        .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct VisualAdviceOverlay: View {
    let show: Bool
    let advices: [VisualAdvice]
    let imageSize: CGSize

    var body: some View {
        GeometryReader { geo in
            if show {
                let scaleX = geo.size.width / imageSize.width
                let scaleY = geo.size.height / imageSize.height

                ForEach(Array(advices.enumerated()), id: \.offset) { index, advice in
                    // Draw arrow from currentPosition to targetPosition (if available)
                    if let target = advice.targetPosition {
                        let from = CGPoint(x: advice.currentPosition.x * scaleX,
                                           y: advice.currentPosition.y * scaleY)
                        let to = CGPoint(x: target.x * scaleX, y: target.y * scaleY)

                        ArrowShape(from: from, to: to)
                            .stroke(Color.green.opacity(0.95), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)

                        // Message bubble near the arrow head
                        Text(advice.message)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.7)))
                            .foregroundColor(.white)
                            .position(x: to.x, y: max(12, to.y - 24 - CGFloat(index) * 18))
                    } else {
                        // If no explicit target, show a hint near the current position
                        let pos = CGPoint(x: advice.currentPosition.x * scaleX, y: advice.currentPosition.y * scaleY)
                        Text(advice.message)
                            .font(.caption2)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.7)))
                            .foregroundColor(.white)
                            .position(x: pos.x, y: max(12, pos.y - 18))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// Small Shape for drawing an arrow with a triangular head
struct ArrowShape: Shape {
    var from: CGPoint
    var to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)

        // Arrow head
        let angle = atan2(to.y - from.y, to.x - from.x)
        let headLength: CGFloat = 12
        let headAngle: CGFloat = .pi / 6

        let p1 = CGPoint(x: to.x - cos(angle - headAngle) * headLength,
                         y: to.y - sin(angle - headAngle) * headLength)
        let p2 = CGPoint(x: to.x - cos(angle + headAngle) * headLength,
                         y: to.y - sin(angle + headAngle) * headLength)

        path.move(to: p1)
        path.addLine(to: to)
        path.addLine(to: p2)

        return path
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
