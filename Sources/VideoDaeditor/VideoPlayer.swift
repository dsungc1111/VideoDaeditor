//
//  VideoPlayerView.swift
//  VideoTest
//
//  Created by 최대성 on 3/24/25.
//

import SwiftUI
import AVKit

// MARK: - PlayerSettings
/// 비디오 트리밍 구간(startTime, selectedEndTime) 등의 정보를 담고 있는 ObservableObject
public class PlayerSettings: ObservableObject {
    @Published public var startTime: Double = 0        // 트리밍 시작 시점(초)
    @Published public var selectedEndTime: Double = 5  // 트리밍 종료 시점(초)
    
    public init() { }
}

// MARK: - VideoPlayerView
/// AVKit의 AVPlayerViewController를 SwiftUI에서 사용하기 위한 UIViewControllerRepresentable
public struct VideoPlayerView: UIViewControllerRepresentable {
    public var player: AVPlayer
    @Binding public var isPlaying: Bool
    
    public init(player: AVPlayer, isPlaying: Binding<Bool>) {
        self.player = player
        self._isPlaying = isPlaying
    }
    
    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        return controller
    }
    
    public func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if isPlaying {
            uiViewController.player?.play()
        } else {
            uiViewController.player?.pause()
        }
    }
}
