//
//  File.swift
//  VideoDaeditor
//
//  Created by 최대성 on 3/21/25.
//

import AVFoundation
import SwiftUI

public struct ThumbnailGenerator {
    public static func generateThumbnails(for url: URL, frameCount: Int = 5, maxSize: CGSize = CGSize(width: 100, height: 100)) async -> [UIImage] {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize
        do {
            let duration = try await asset.load(.duration)
            let durationInSeconds = CMTimeGetSeconds(duration)
            let times: [CMTime] = (0..<frameCount).map { i in
                let second = Double(i) * (durationInSeconds / Double(frameCount))
                return CMTime(seconds: second, preferredTimescale: 600)
            }
            var thumbnails: [UIImage] = []
            for time in times {
                if let cgimage = try? generator.copyCGImage(at: time, actualTime: nil) {
                    thumbnails.append(UIImage(cgImage: cgimage))
                }
            }
            return thumbnails
        } catch {
            print("Thumbnail generation error: \(error.localizedDescription)")
            return []
        }
    }
}
