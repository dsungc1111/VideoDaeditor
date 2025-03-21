//
//  File.swift
//  VideoDaeditor
//
//  Created by 최대성 on 3/21/25.
//

import AVFoundation
import AVKit
import SwiftUI

public class VideoPlayerManager: ObservableObject {
    public private(set) var player: AVPlayer?
    private var timeObserverToken: Any?
    
    @Published public var currentPlayPosition: CGFloat = 0.0
    @Published public var isPlaying: Bool = false
    
    public init() { }
    
    public func setupPlayer(with url: URL, startTime: Double, endTime: Double, updateHandler: @escaping (Double, CGFloat) -> Void) {
        resetPlayer()
        player = AVPlayer(url: url)
        
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let currentSeconds = CMTimeGetSeconds(time)
            updateHandler(currentSeconds, self.currentPlayPosition)
            if currentSeconds >= endTime {
                self.player?.pause()
                self.player?.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
                self.isPlaying = false
            }
        }
        
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.isPlaying = false
            self.player?.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
        }
    }
    
    public func togglePlayPause(startTime: Double, endTime: Double) {
        guard let p = player else { return }
        if isPlaying {
            p.pause()
        } else {
            let currentSeconds = CMTimeGetSeconds(p.currentTime())
            if currentSeconds < startTime || currentSeconds >= endTime {
                p.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
            }
            p.play()
        }
        isPlaying.toggle()
    }
    
    public func resetPlayer() {
        if let p = player {
            p.pause()
            if let observer = timeObserverToken {
                p.removeTimeObserver(observer)
                timeObserverToken = nil
            }
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: p.currentItem)
        }
        player = nil
        isPlaying = false
        currentPlayPosition = 0.0
    }
}
