//
//  VideoTrimmerModule.swift
//  Created by 최대성 on 3/24/25.
//

import SwiftUI
import PhotosUI
import AVKit
import Combine
import AVFoundation
import UniformTypeIdentifiers

// MARK: - CustomVideoTrimmerView
/// 비디오 선택 → 재생 + 썸네일 타임라인 + 트리밍 핸들 + 트리밍된 영상 재생
/// 외부 모듈에서도 직접 View로 사용할 수 있도록 `public` 선언
@MainActor
public struct CustomVideoTrimmerView: View {
    // MARK: - Public State/Properties
    @State public var selectedItem: PhotosPickerItem? = nil  // PhotosPicker로 선택된 비디오
    @State public var originalVideoURL: URL? = nil           // 원본 비디오 URL
    @State public var trimmedVideoURL: URL? = nil            // 트리밍 완료 후 영상 URL
    
    @State public var player: AVPlayer? = nil               // AVPlayer
    @State public var isPlaying: Bool = false                // 플레이어 재생 상태
    @State public var timeObserverToken: Any? = nil
    
    @StateObject public var settings = PlayerSettings()
    @State public var endTime: Double = 5                    // 원본 비디오 전체 길이
    @State public var currentTime: Double = 0                // 플레이어의 현재 재생 위치(초)
    @State public var currentPlayPosition: CGFloat = 0       // 트리밍바 내 실제 위치(%)
    
    // 썸네일 관련
    @State public var thumbnails: [UIImage] = []
    @State public var isLoading: Bool = false                // 로딩 상태
    public let timelineWidth: CGFloat = 300                  // 타임라인 전체 폭
    
    // 트리밍 핸들 위치(픽셀 단위)
    @State public var startTrimPosition: CGFloat = 0
    @State public var endTrimPosition: CGFloat = 300
    
    // Combine: 드래그 제스처용
    @State public var dragValueSubject = PassthroughSubject<CGFloat, Never>()
    @State public var dragThrottleCancellable: AnyCancellable?
    
    // 최대 트리밍 구간 (픽셀 단위)
    private var maxSelectableWidth: CGFloat {
        // 트리밍은 최대 7초로 제한
        let maxSeconds = min(endTime, 7)
        return (CGFloat(maxSeconds) / CGFloat(endTime)) * timelineWidth
    }
    
    public var onTrimCompletion: ((URL) -> Void)? = nil
    
    // MARK: - Init
    public init() { }
    
    // MARK: - Body
    public var body: some View {
        VStack {
            // 1) 비디오 선택 버튼
            PhotosPicker(selection: $selectedItem, matching: .videos, photoLibrary: .shared()) {
                Image(systemName: "camera.circle")
            }
            .padding(.top, 16)
            
            if isLoading {
                ProgressView("비디오 로드 중...")
                    .padding()
            }
            
            // 2) 비디오 플레이어
    
            if let _ = originalVideoURL {
                
                
                VStack(spacing: 8) {
                    if let player = player {
                        VideoPlayerView(player: player, isPlaying: $isPlaying)
                            .frame(height: 300)
                            .cornerRadius(12)
                            .padding(.horizontal, 15)
                    } else {
                        ProgressView("플레이어 초기화 중...")
                            .frame(height: 300)
                            .padding(.horizontal, 15)
                    }
                    
                    Button(action: { togglePlayPause() }) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .resizable()
                            .frame(width: 60, height: 60)
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                    }
                }
                
                // 2) 타임라인은 trimmedVideoURL이 없을 때(즉, 아직 트리밍 안 했을 때)만 표시
                if !thumbnails.isEmpty, trimmedVideoURL == nil {
                    timelineWithHandles()
                        .padding(.top, 20)
                        .frame(width: timelineWidth + 120, height: 60)
                }
                
                // 트리밍 구간 표시
                if trimmedVideoURL == nil {
                    Text("트리밍: \(settings.startTime, specifier: "%.2f")초 ~ \(settings.selectedEndTime, specifier: "%.2f")초")
                        .font(.caption)
                        .padding(.top, 5)
                }
                
                // 3) "트리밍 완료" 버튼도 트리밍 전( trimmedVideoURL == nil )에만 보이게
                if trimmedVideoURL == nil {
                    Button("✂️ 트리밍 완료") {
                        Task {
                            await exportTrimmedVideo()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 10)
                }
                
                // 4) 트리밍된 영상이 있으면 안내
                if let trimmedVideoURL {
                    Text("트리밍된 영상: \(trimmedVideoURL.lastPathComponent)")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .padding(.top, 5)
                }
                
            } else {
                // 비디오 선택 전
                Text("선택된 비디오가 없습니다.")
                    .foregroundColor(.secondary)
                    .padding()
            }
            
            Spacer()
        }
        .onAppear {
            setupDragThrottle()
        }
        .onDisappear {
            dragThrottleCancellable?.cancel()
        }
        .onChange(of: selectedItem) { _, newItem in
            Task {
                await loadSelectedVideo(newItem)
            }
        }
    }
}

// MARK: - Public/Private Extension (CustomVideoTrimmerView)
extension CustomVideoTrimmerView {
    
    /// PhotosPickerItem으로부터 비디오 Data를 로드 → 임시 폴더에 저장 후 썸네일/플레이어 준비
    public func loadSelectedVideo(_ newItem: PhotosPickerItem?) async {
        guard let newItem = newItem else { return }
        isLoading = true
        resetPlayer()
        
        // Data 로드
        if let videoData = try? await newItem.loadTransferable(type: Data.self) {
            // 임시 파일에 저장
            let tempURL = saveVideoToTempFile(videoData)
            DispatchQueue.main.async {
                self.originalVideoURL = tempURL
            }
            
            // 썸네일 생성
            await generateThumbnails(for: tempURL)
            
            // 플레이어 준비
            DispatchQueue.main.async {
                self.setupPlayer(with: tempURL)
            }
        }
        isLoading = false
    }
    
    /// 임시 폴더에 비디오 파일로 저장
    public func saveVideoToTempFile(_ data: Data) -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("❌ 비디오 저장 실패: \(error.localizedDescription)")
            return tempDirectory
        }
    }
    
    /// iOS 17 / iOS 18 분기 처리하여 썸네일 생성
    ///
    /// - iOS 18+ : `AVAsset(url:)` 사용 (iOS 18부터 AVURLAsset이 deprecated)
    /// - iOS 17- : `AVURLAsset(url:)` 사용
    /// - iOS 17+ : `generator.image(at:)` (copyCGImage가 deprecated)
    /// - iOS 16- : `generator.copyCGImage(at:actualTime:)`
    public func generateThumbnails(for url: URL) async {
        // iOS 18 이상이면 AVAsset(url:) 사용, 그 이하면 AVURLAsset(url:)
        let asset: AVAsset
        if #available(iOS 18.0, *) {
            asset = AVAsset(url: url)
        } else {
            asset = AVURLAsset(url: url)  // iOS 18부터 deprecated
        }
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 100, height: 100)
        
        do {
            let duration = try await asset.load(.duration)  // iOS 16+ API
            let durationInSeconds = CMTimeGetSeconds(duration)
            let frameCount = 5
            let times: [CMTime] = (0..<frameCount).map { i in
                let second = Double(i) * (durationInSeconds / Double(frameCount))
                return CMTime(seconds: second, preferredTimescale: 600)
            }
            
            var tempThumbnails: [UIImage] = []
            for time in times {
                if #available(iOS 17.0, *) {
                    let (cgImage, _) = try await generator.image(at: time)
                    tempThumbnails.append(UIImage(cgImage: cgImage))
                } else {
                    if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                        tempThumbnails.append(UIImage(cgImage: cgImage))
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.thumbnails = tempThumbnails
                self.endTime = durationInSeconds
                // 7초보다 길면 7초까지만 트리밍
                if self.endTime >= 7 {
                    self.startTrimPosition = 0
                    self.endTrimPosition = (7 / self.endTime) * self.timelineWidth
                    self.settings.startTime = 0
                    self.settings.selectedEndTime = 7
                } else {
                    // 7초 미만이면 전체 사용
                    self.startTrimPosition = 0
                    self.endTrimPosition = self.timelineWidth
                    self.settings.startTime = 0
                    self.settings.selectedEndTime = self.endTime
                }
                self.currentPlayPosition = 0
            }
        } catch {
            print("❌ duration 로드 실패: \(error.localizedDescription)")
        }
    }
    
    /// AVPlayer를 완전히 초기화한 후, 새 URL로 인스턴스를 생성
    public func setupPlayer(with url: URL) {
        resetPlayer()
        player = AVPlayer(url: url)
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        
        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            
            Task { @MainActor in
                let currentSeconds = CMTimeGetSeconds(time)
                self.currentTime = currentSeconds
                
                if currentSeconds >= self.settings.startTime && currentSeconds <= self.settings.selectedEndTime {
                    let percentage = ((currentSeconds - self.settings.startTime)
                                      / (self.settings.selectedEndTime - self.settings.startTime)) * 100
                    self.currentPlayPosition = max(0, min(CGFloat(percentage), 100))
                }
                if currentSeconds >= self.settings.selectedEndTime {
                    self.player?.pause()
                    self.player?.seek(to: CMTime(seconds: self.settings.startTime, preferredTimescale: 600))
                    self.isPlaying = false
                }
            }
        }
        
        // 영상 끝까지 재생 시, 다시 트리밍 시작점으로
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            Task { @MainActor in
                self.isPlaying = false
                self.player?.seek(to: CMTime(seconds: self.settings.startTime, preferredTimescale: 600))
            }
        }
    }
    
    /// 플레이어 리셋
    public func resetPlayer() {
        if let p = player {
            p.pause()
            if let observer = timeObserverToken {
                p.removeTimeObserver(observer)
                timeObserverToken = nil
            }
            NotificationCenter.default.removeObserver(
                self,
                name: .AVPlayerItemDidPlayToEndTime,
                object: p.currentItem
            )
        }
        player = nil
        isPlaying = false
        currentPlayPosition = 0
    }
    
    /// 드래그 제스처에 Throttle 적용
    public func setupDragThrottle() {
        dragThrottleCancellable = dragValueSubject
            .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
            .sink { delta in
                let sensitivity: CGFloat = 0.09
                let throttledDelta = delta * sensitivity
                var newStart = startTrimPosition + throttledDelta
                var newEnd = endTrimPosition + throttledDelta
                
                // 최대 선택 구간(7초) 넘지 않도록
                if newEnd - newStart > maxSelectableWidth {
                    let overflow = (newEnd - newStart) - maxSelectableWidth
                    newStart += overflow / 2
                    newEnd -= overflow / 2
                }
                // 0보다 작아지면 보정
                if newStart < 0 {
                    let offset = -newStart
                    newStart = 0
                    newEnd += offset
                }
                // timelineWidth보다 커지면 보정
                if newEnd > self.timelineWidth {
                    let offset = newEnd - self.timelineWidth
                    newEnd = self.timelineWidth
                    newStart -= offset
                }
                startTrimPosition = newStart
                endTrimPosition = newEnd
                settings.startTime = (startTrimPosition / self.timelineWidth) * endTime
                settings.selectedEndTime = (endTrimPosition / self.timelineWidth) * endTime
            }
    }
    
    /// 트리밍 완료 → 실제로 새 영상을 Export 후, 그 URL로 재생
    public func exportTrimmedVideo() async {
        guard let originalURL = originalVideoURL else { return }
        
        // 트리밍 구간
        let start = settings.startTime
        let end = settings.selectedEndTime
        
        // 1) AVAssetExportSession을 이용하여 트리밍
        if let trimmedURL = await trimVideo(inputURL: originalURL, startTime: start, endTime: end) {
            // 2) 기존 플레이어를 완전히 초기화하고, 새 URL로 새 AVPlayer 인스턴스 생성
            DispatchQueue.main.async {
                self.trimmedVideoURL = trimmedURL
                self.setupPlayer(with: trimmedURL)
                self.onTrimCompletion?(trimmedURL)
            }
        }
    }
    
    /// 지정된 구간(startTime ~ endTime)으로 영상을 실제 잘라내어 Export
    public func trimVideo(inputURL: URL, startTime: Double, endTime: Double) async -> URL? {
        let asset = AVAsset(url: inputURL)
        
        // Export Session 생성
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            print("❌ AVAssetExportSession 생성 실패")
            return nil
        }
        
        let trimmedFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).mp4")
        
        // 내보낼 구간 설정
        let startCMTime = CMTime(seconds: startTime, preferredTimescale: 600)
        let endCMTime = CMTime(seconds: endTime, preferredTimescale: 600)
        let timeRange = CMTimeRange(start: startCMTime, end: endCMTime)
        
        exportSession.outputURL = trimmedFileURL
        exportSession.outputFileType = .mp4
        exportSession.timeRange = timeRange
        
        return await withCheckedContinuation { continuation in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    print("✅ 트리밍 완료: \(trimmedFileURL)")
                    continuation.resume(returning: trimmedFileURL)
                case .failed, .cancelled:
                    if let error = exportSession.error {
                        print("❌ 트리밍 실패: \(error.localizedDescription)")
                    }
                    continuation.resume(returning: nil)
                default:
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    // MARK: - UI: 타임라인 + 트리밍 핸들
    @ViewBuilder
    public func timelineWithHandles() -> some View {
        let offsetX: CGFloat = 80
        
        ZStack {
            // 배경
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.8))
                .frame(width: timelineWidth + 120, height: 60)
            
            // 플레이/일시정지 버튼
            Button(action: { togglePlayPause() }) {
                Image(systemName: isPlaying ? "pause.circle" : "play.circle")
                    .resizable()
                    .frame(width: 40, height: 40)
                    .foregroundColor(.white)
            }
            .position(x: 40, y: 30)
            .zIndex(10)
            
            // 썸네일
            thumbnailRow()
                .position(x: timelineWidth / 2 + offsetX, y: 30)
            
            // 현재 재생 위치 표시 (녹색 막대)
            Rectangle()
                .fill(Color.green)
                .frame(width: 2, height: 50)
                .position(x: startTrimPosition
                          + currentPlayPosition * (endTrimPosition - startTrimPosition) / 100
                          + offsetX,
                          y: 30)
                .zIndex(3)
            
            // 왼쪽/오른쪽 범위 밖 어둡게
            Rectangle()
                .fill(Color.black.opacity(0.5))
                .frame(width: startTrimPosition, height: 55)
                .position(x: startTrimPosition / 2 + offsetX - 10, y: 30)
                .zIndex(2)
            
            Rectangle()
                .fill(Color.black.opacity(0.5))
                .frame(width: timelineWidth - endTrimPosition, height: 55)
                .position(x: endTrimPosition + (timelineWidth - endTrimPosition) / 2 + offsetX + 10, y: 30)
                .zIndex(2)
            
            // 트리밍 범위 사각형
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.yellow, lineWidth: 3)
                .background(Color.white.opacity(0.000001)) // 제스처 인식
                .frame(width: endTrimPosition - startTrimPosition, height: 50)
                .position(x: (startTrimPosition + endTrimPosition) / 2 + offsetX, y: 30)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragValueSubject.send(value.translation.width)
                        }
                        .onEnded { _ in
                            pauseAndSeekToStart()
                        }
                )
                .zIndex(4)
            
            // 왼쪽 핸들
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.yellow)
                    .frame(width: 18, height: 55)
                Image(systemName: "chevron.left")
                    .foregroundColor(.black)
                    .font(.system(size: 14, weight: .bold))
            }
            .position(x: startTrimPosition + offsetX, y: 30)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        var newPos = max(0, min(value.location.x - offsetX, endTrimPosition - 20))
                        if endTrimPosition - newPos > maxSelectableWidth {
                            newPos = endTrimPosition - maxSelectableWidth
                        }
                        startTrimPosition = newPos
                        settings.startTime = (startTrimPosition / timelineWidth) * endTime
                        player?.seek(to: CMTime(seconds: settings.startTime, preferredTimescale: 600))
                    }
                    .onEnded { _ in
                        pauseAndSeekToStart()
                    }
            )
            .zIndex(5)
            
            // 오른쪽 핸들
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.yellow)
                    .frame(width: 18, height: 55)
                Image(systemName: "chevron.right")
                    .foregroundColor(.black)
                    .font(.system(size: 14, weight: .bold))
            }
            .position(x: endTrimPosition + offsetX, y: 30)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        var newPos = min(timelineWidth, max(value.location.x - offsetX, startTrimPosition + 20))
                        if newPos - startTrimPosition > maxSelectableWidth {
                            newPos = startTrimPosition + maxSelectableWidth
                        }
                        endTrimPosition = newPos
                        settings.selectedEndTime = (endTrimPosition / timelineWidth) * endTime
                    }
                    .onEnded { _ in
                        pauseAndSeekToStart()
                    }
            )
            .zIndex(5)
        }
    }
    
    /// 썸네일 Row
    @ViewBuilder
    public func thumbnailRow() -> some View {
        let count = thumbnails.count
        if count > 0 {
            let eachWidth = timelineWidth / CGFloat(count)
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { i in
                    Image(uiImage: thumbnails[i])
                        .resizable()
                        .scaledToFill()
                        .frame(width: eachWidth, height: 50)
                        .clipped()
                }
            }
        }
    }
    
    /// 플레이/일시정지 토글
    public func togglePlayPause() {
        guard let p = player else { return }
        if isPlaying {
            p.pause()
        } else {
            let currentSeconds = CMTimeGetSeconds(p.currentTime())
            if currentSeconds < settings.startTime || currentSeconds >= settings.selectedEndTime {
                p.seek(to: CMTime(seconds: settings.startTime, preferredTimescale: 600))
            }
            p.play()
        }
        isPlaying.toggle()
    }
    
    /// 드래그 끝나면 재생 멈추고 트리밍 시작점으로
    public func pauseAndSeekToStart() {
        guard let p = player else { return }
        p.pause()
        isPlaying = false
        p.seek(to: CMTime(seconds: settings.startTime, preferredTimescale: 600))
        currentPlayPosition = 0
    }
}
