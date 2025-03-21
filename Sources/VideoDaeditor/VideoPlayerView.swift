//
//  File.swift
//  VideoDaeditor
//
//  Created by 최대성 on 3/21/25.
//

import SwiftUI
import AVKit

public struct CustomVideoPlayerView: View {
    @ObservedObject private var manager: VideoPlayerManager
    
    public init(videoURL: URL, startTime: Double, endTime: Double) {
        self.manager = VideoPlayerManager()
        self.manager.setupPlayer(with: videoURL, startTime: startTime, endTime: endTime) { currentTime, progress in
            // 내부적으로 필요한 업데이트 처리
        }
    }
    
    public var body: some View {
        VideoPlayer(player: manager.player)
            .onDisappear {
                manager.resetPlayer()
            }
    }
}
