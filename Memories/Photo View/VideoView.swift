//
//  VideoView.swift
//  Memories
//
//  Created by Michael Brown on 04/11/2016.
//  Copyright © 2016 Michael Brown. All rights reserved.
//

import UIKit
import AVFoundation
import Cartography

class VideoView: UIView {

    let previewImageView = UIImageView().with {
        $0.translatesAutoresizingMaskIntoConstraints = false
    }
    
    var image: UIImage? {
        didSet {
            previewImageView.image = image
        }
    }
    
    deinit {
        player?.removeObserver(self, forKeyPath: "status")
        player?.removeObserver(self, forKeyPath: "rate")
    }

    var playerItem: AVPlayerItem? {
        set {
            self.player = AVPlayer()

            if let videoLayer = self.layer as? AVPlayerLayer {
                videoLayer.player = player
                videoLayer.videoGravity = AVLayerVideoGravityResizeAspect
            }
            // only set item once AVPlayerLayer has been setup
            // optimization recommended in Session 503 from WWDC 2016 (https://developer.apple.com/videos/play/wwdc2016/503/)
            self.player?.replaceCurrentItem(with: newValue)
        }
        get {
            return self.player?.currentItem
        }
    }
    
    var player: AVPlayer? {
        willSet {
            player?.removeObserver(self, forKeyPath: "status")
            player?.removeObserver(self, forKeyPath: "rate")
        }
        didSet {

            player?.addObserver(self, forKeyPath: "status", options: .new, context: nil)
            player?.addObserver(self, forKeyPath: "rate", options: .new, context: nil)
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        addSubview(previewImageView)
        constrain(self, previewImageView) {view, imageView in
            view.edges == imageView.edges
        }
    }

    convenience init() {
        self.init(frame: .zero)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override class var layerClass : AnyClass {
        return AVPlayerLayer.self
    }

    func reset() {
        setPreviewImage(visible: true)
    }
    
    func setPreviewImage(visible: Bool) {
        UIView.animate(withDuration: 0.3) { [weak self] in
            self?.previewImageView.alpha = visible ? 1 : 0
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if let status = player?.status,
            let rate = player?.rate,
            status == .readyToPlay,
            rate != 0 {
            setPreviewImage(visible: false)
        }
    }
    
}
