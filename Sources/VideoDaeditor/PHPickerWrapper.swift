//
//  File.swift
//  VideoDaeditor
//
//  Created by 최대성 on 3/25/25.
//

import SwiftUI
import PhotosUI


struct PHPickerWrapper: UIViewControllerRepresentable {
    @Binding var pickerResults: [PHPickerResult]
    
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos       // 비디오만 선택
        config.selectionLimit = 1     // 한 번에 1개 선택
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        // 업데이트 로직이 필요 없다면 비워둡니다.
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PHPickerWrapper
        
        init(_ parent: PHPickerWrapper) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.pickerResults = results
            parent.dismiss() // 시트 닫기
        }
    }
}
