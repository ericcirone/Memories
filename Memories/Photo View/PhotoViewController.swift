//
//  PhotoViewController.swift
//  Memories
//
//  Created by Michael Brown on 08/07/2015.
//  Copyright © 2015 Michael Brown. All rights reserved.
//

import UIKit
import Photos

protocol PhotoViewControllerDelegate {
    func setSelected(index: Int)
    func imageView(atIndex: Int) -> UIImageView?
}

class PhotoViewController: UIViewController,
    UIScrollViewDelegate,
    UIViewControllerTransitioningDelegate,
    PHPhotoLibraryChangeObserver,
    ZoomingPhotoViewDelegate
{
    @IBOutlet var scrollView: UIScrollView!
    @IBOutlet weak var shareButton: UIButton!
    @IBOutlet weak var deleteButton: UIButton!
    @IBOutlet weak var closeButton: UIButton!
    @IBOutlet weak var heartButton: UIButton!
    @IBOutlet weak var yearLabel: UILabel!

    let padding = CGFloat(10);
    
    let heartFullImg = UIImage(named: "heart-full")!.withRenderingMode(.alwaysTemplate)
    let heartEmptyImg = UIImage(named: "heart-empty")!.withRenderingMode(.alwaysTemplate)
    
    var upgradePromptShown = false
    var initialOffsetSet = false
    var initialPage : Int!
    var model : PhotoViewModel!
    var pageViews = [ZoomingPhotoView?]()
    let imageManager : PHCachingImageManager
    var delegate: PhotoViewControllerDelegate?
    // If the size is too large then PhotoKit doesn't return an optimal image size
    // see rdar://25181601 (https://openradar.appspot.com/radar?id=6158824289337344)
    let cacheSize = CGSize(width: 256, height: 256)
    
    struct PanState {
        let imageView: UIView?
        let destImageView: UIImageView?
        let transform: CGAffineTransform
        let center: CGPoint
        let panHeight: CGFloat
    }
    
    var initialPanState = PanState(imageView: nil, destImageView: nil, transform: CGAffineTransform.identity, center: .zero, panHeight: 0)
    
    var presentTransition: PhotoViewPresentTransition?
    var dismissTransition: PhotoViewDismissTransition?
    
    required init?(coder aDecoder: NSCoder) {
        self.imageManager = PHCachingImageManager()
        super.init(coder: aDecoder)
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    var controlsHidden: Bool {
        get {
            return closeButton.alpha == 0
        }
    }
    
    private func buttonImage(forFavorite favorite: Bool) -> UIImage {
        return favorite ? heartFullImg : heartEmptyImg
    }
    
    // MARK: UIViewController
    
    override func viewDidLoad() {
        super.viewDidLoad()

        initialPage = model.selectedIndex
        imageManager.startCachingImages(for: model.assets, targetSize: cacheSize, contentMode: .aspectFill, options: nil)
        PHPhotoLibrary.shared().register(self);
        
        let panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(PhotoViewController.viewDidPan))
        view.addGestureRecognizer(panRecognizer)
    }

    override func viewDidLayoutSubviews() {
        setupViews()
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        initialPage = model.selectedIndex
        initialOffsetSet = false
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    // MARK: Actions
    @IBAction func sharePhoto(_ sender: UIButton) {
        let page = model.selectedIndex
        
        let asset = model.assets[page]
        let options = PHImageRequestOptions()
        options.version = .current
        options.isNetworkAccessAllowed = false
        PHImageManager.default().requestImageData(for: asset, options: options) {
            [weak self] imageData, dataUTI, orientation, info in
            guard let `self` = self else { return }

            if let imageData = imageData {
                let avc = UIActivityViewController(activityItems: [imageData], applicationActivities: nil)
                if let popover = avc.popoverPresentationController {
                    popover.sourceView = sender
                    popover.sourceRect = sender.bounds
                    popover.permittedArrowDirections = .down
                }
                
                self.present(avc, animated: true, completion: nil)
            }
        }
    }
    
    @IBAction func deletePhoto(_ sender: UIButton) {
        let asset = model.selectedAsset
        
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(NSArray(array: [asset]))
        }, completionHandler: nil)
    }
    
    @IBAction func toggleFavorite(_ sender: UIButton) {
        let asset = model.selectedAsset
        let newState = !asset.isFavorite
        
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetChangeRequest(for: asset)
            request.isFavorite = newState
        }, completionHandler: nil)
    }
    
    func doClose() {
        guard let delegate = delegate else {
            return
        }
        
        delegate.setSelected(index: model.selectedIndex)
        let imageView = delegate.imageView(atIndex: model.selectedIndex)!
        let pageView = pageViews[model.selectedIndex]!
            
        dismissTransition = PhotoViewDismissTransition(destImageView: imageView, sourceImageView: pageView.photoView)
        presentingViewController?.dismiss(animated: true) {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
            self.cancelAllImageRequests()
            self.purgeAllViews()
        }
    }
    
    @IBAction func close(_ sender: UIButton) {
        doClose()
    }
    
    func viewDidPan(_ gr: UIPanGestureRecognizer) {
        switch gr.state {
        case .began:
            let startPoint = gr.location(in: gr.view)
            
            let imageView = pageViews[model.selectedIndex]!.photoView
            initialPanState = PanState(imageView: imageView,
                                       destImageView: delegate?.imageView(atIndex: model.selectedIndex),
                                       transform: imageView.transform,
                                       center: imageView.center,
                                       panHeight: gr.view!.bounds.height - startPoint.y)
            initialPanState.destImageView?.isHidden = true
        case .changed:
            let translation = gr.translation(in: gr.view)
            let yPercent = translation.y / initialPanState.panHeight
            let percent = yPercent <= 0 ? 0 : yPercent
            let alpha = 1 - percent
            let scale = (1 - percent / 2)
            
            initialPanState.imageView?.center = CGPoint(x: initialPanState.center.x + translation.x, y: initialPanState.center.y + translation.y)
            initialPanState.imageView?.transform = initialPanState.transform.scaledBy(x: scale, y: scale)
            
            view.backgroundColor = UIColor.black.withAlphaComponent(alpha)
            if !controlsHidden { setControls(alpha: alpha) }

        case .ended, .cancelled:
            let velocity = gr.velocity(in: gr.view)
            if velocity.y < 0 || gr.state == .cancelled {
                UIView.animate(withDuration: 0.25, animations: {
                    self.initialPanState.imageView?.center = self.initialPanState.center
                    self.initialPanState.imageView?.transform = self.initialPanState.transform
                    self.view.backgroundColor = UIColor.black
                    if !self.controlsHidden { self.setControls(alpha: 1) }
                }) { finished in
                    self.initialPanState.destImageView?.isHidden = false
                }
            }
            else {
                doClose()
            }

        default:
            break
        }
    }
    
    // MARK: Internal implementation
    func setupViews() {
        let pageCount = model.assets.count

        if pageViews.count == 0 {
            for _ in 0..<pageCount {
                pageViews.append(nil)
            }
            initialPage = model.selectedIndex
            initialOffsetSet = false
        }

        let pagesScrollViewSize = scrollView.bounds.size
        scrollView.contentSize = CGSize(width: pagesScrollViewSize.width * CGFloat(pageCount),
            height: pagesScrollViewSize.height)
        
        loadVisiblePages()
    }
    
    func page(view pageView: ZoomingPhotoView, didLoad enable: Bool, for asset: PHAsset) {
        shareButton.isEnabled = enable
        deleteButton.isEnabled = enable
        heartButton.isEnabled = !asset.sourceType.contains(.typeiTunesSynced) && enable
        
        if asset.mediaSubtypes == .photoLive {
            pageView.didBecomeVisible()
        }
    }
    
    func load(page: Int, requestFullImage: Bool) {
        guard page >= 0 && page < model.assets.count else {
            return
        }

        // setup the frame for the view
        let bounds = scrollView.bounds
        var frame = bounds
        frame.size.width -= (2.0 * padding);
        frame.origin.x = bounds.size.width * CGFloat(page) + padding
        frame.origin.y = 0.0

        let asset = model.assets[page]
        if page == self.model.selectedIndex {
            heartButton.setImage(buttonImage(forFavorite: asset.isFavorite), for: UIControlState())
            yearLabel.text = String("  \(asset.creationDate!.year)  ")
        }
        
        // if we already have a view with a full image or
        // if we don't need the full image
        // make sure it's layed out correctly
        if let pageView = pageViews[page] {
            if !requestFullImage || !pageView.imageIsDegraded {
                pageView.frame = frame
                if requestFullImage {
                    self.page(view: pageView, didLoad: true, for: asset)
                }
                return
            }
        }

        let pageView: ZoomingPhotoView!
        
        if pageViews[page] != nil {
            pageView = pageViews[page]
        } else {
            pageView = ZoomingPhotoView()
            pageView.photoViewDelegate = self
            scrollView.addSubview(pageView)
            pageViews[page] = pageView
        }
        pageView.frame = frame

        // always get a thumbnail first
        pageView.imageIsDegraded = true
        imageManager.requestImage(for: asset, targetSize: cacheSize, contentMode: .aspectFill, options: nil, resultHandler: { result, userInfo in
            if let image = result {
                // NSLog("Cache Result with image for page \(page) requestFullImage: \(requestFullImage) iamgeSize: \(image.size.width), \(image.size.height)");
                pageView.photo = image
                if page == self.model.selectedIndex {
                    self.page(view: pageView, didLoad: false, for: asset)
                }
            }
        })
        
        // then get the full size image if required
        if requestFullImage {
            if !UpgradeManager.highQualityViewAllowed() {
                UpgradeManager.promptForUpgrade(in: self) {
                    if !$0 {
                        pageView.hideProgressView(true)
                    } else {
                        self.loadHighQualityImage(for: asset, page: page)
                    }
                }
                
                return
            }
            
            loadHighQualityImage(for: asset, page: page)
        }
    }

    func loadHighQualityImage(for asset: PHAsset, page: Int) {
        let pageView = pageViews[page]!
        let progressHandler: PHAssetImageProgressHandler = { progress, error, stop, userInfo in
            DispatchQueue.main.async {
                pageView.updateProgress(progress)
                
                if error != nil {
                    pageView.fullImageUnavailable = true
                }
            }
        }
        
        let configurePageView = { (isLivePhoto: Bool) in
            return { (ok: Bool, photo: UIImage?, livePhoto: PHLivePhoto?) in
                guard ok else {
                    pageView.fullImageUnavailable = true
                    return
                }
                UpgradeManager.highQualityViewCount += 1
                if isLivePhoto {
                    pageView.livePhoto = livePhoto
                } else {
                    pageView.photo = photo
                }
                pageView.imageIsDegraded = false
                if page == self.model.selectedIndex {
                    self.page(view: pageView, didLoad: true, for: asset)
                }
            }
        }
        
        if asset.mediaSubtypes == .photoLive {
            pageView.imageRequestId = loadLivePhoto(for: asset, progressHandler: progressHandler, completion: configurePageView(true))
        }
        else {
            pageView.imageRequestId = loadPhoto(for: asset, progressHandler: progressHandler, completion: configurePageView(false))
        }
    }
    
    func loadPhoto(for asset: PHAsset, progressHandler: @escaping PHAssetImageProgressHandler, completion: @escaping (Bool, UIImage?, PHLivePhoto?) -> ()) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        
        options.progressHandler = progressHandler
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false
        
        return PHImageManager.default().requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: options) { (result, userInfo) -> Void in
            if let image = result {
                completion(true, image, nil)
            }
            
            if let _ = userInfo?[PHImageErrorKey] as? NSError {
                completion(false, nil, nil)
            }
        }
    }
    
    func loadLivePhoto(for asset: PHAsset, progressHandler: @escaping PHAssetImageProgressHandler, completion: @escaping (Bool, UIImage?, PHLivePhoto?) -> ()) -> PHImageRequestID {
        let options = PHLivePhotoRequestOptions()
        
        options.progressHandler = progressHandler
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        
        return PHImageManager.default().requestLivePhoto(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: options) { (result, userInfo) -> Void in
            if let livePhoto = result {
                completion(true, nil, livePhoto)
            }
            
            if let _ = userInfo?[PHImageErrorKey] as? NSError {
                completion(false, nil, nil)
            }
        }
    }

    func purge(page: Int) {
        guard page >= 0 && page < pageViews.count else {
            return
        }
        
        // Remove a page from the scroll view and reset the container array
        if let pageView = pageViews[page] {
            if let requestId = pageView.imageRequestId {
                PHImageManager.default().cancelImageRequest(requestId)
                pageView.imageRequestId = nil
            }
            pageView.photo = nil
            pageView.removeFromSuperview()
            pageViews[page] = nil
        }
    }
    
    func cancelPageImageRequest(for page: Int) {
        guard page >= 0 && page < pageViews.count else {
            return
        }
        
        if let pageView = pageViews[page] {
            if let requestId = pageView.imageRequestId {
                PHImageManager.default().cancelImageRequest(requestId)
                pageView.imageRequestId = nil
            }
        }
    }
    
    func loadVisiblePages() {
        let initialLoad = !initialOffsetSet
        
        if (!initialOffsetSet) {
            scrollView.contentOffset = contentOffsetForPage(at: initialPage)
            initialOffsetSet = true
        }
        
        // First, determine which page is currently visible
        let pageWidth = scrollView.bounds.size.width
        let fractionalPage = scrollView.contentOffset.x / pageWidth;
        let page = lround(Double(fractionalPage))
        
        if !initialLoad &&
            page == model.selectedIndex {
            return
        }
        
        model.selectedIndex = page
        
        // Work out which pages you want to load
        let firstPage = page - 1
        let lastPage = page + 1
        
        // Purge anything before the first page
        stride(from: 0, to: firstPage, by: 1).forEach(purge)
        
        // Load pages in our range
        (firstPage...lastPage).forEach { load(page: $0, requestFullImage: $0 == page) }
        
        // Purge anything after the last page
        stride(from: model.assets.count, to: lastPage, by: -1).forEach(purge)
    }
    
    func cancelAllImageRequests() {
        pageViews.indices.forEach(cancelPageImageRequest)
    }
    
    func purgeAllViews() {
        pageViews.indices.forEach(purge)
    }
    
    func contentOffsetForPage(at index : Int) -> CGPoint {
        let pageWidth = scrollView.bounds.size.width;
        let newOffset = CGFloat(index) * pageWidth;
        return CGPoint(x: newOffset, y: 0);
    }
    
    // MARK: UIScrollViewDelegate
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == self.scrollView {
            loadVisiblePages()
        }
    }

    // MARK: UIViewControllerTransitioningDelegate
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return presentTransition
    }
    
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return dismissTransition
    }
    
    // MARK: PHPhotoLibraryChangeObserver
    
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async {
            self.processLibraryChange(changeInstance)
        }
    }
    
    private func processLibraryChange(_ changeInstance: PHChange) {
        let newAssets:[PHAsset] = model.assets.flatMap {
            if let changeDetails = changeInstance.changeDetails(for: $0) {
                return changeDetails.objectWasDeleted ? nil : changeDetails.objectAfterChanges as? PHAsset
            }
            else {
                return $0
            }
        }
        
        if newAssets.isEmpty {
            presentingViewController?.dismiss(animated: true, completion: nil);
            return
        }
        
        let assetsDeleted = newAssets.count < model.assets.count
        let newSelectedAsset = min(model.selectedIndex, newAssets.count - 1)
        model = PhotoViewModel(assets: newAssets, selectedAsset: newSelectedAsset)
        
        if assetsDeleted {
            purgeAllViews()
            pageViews = []
            
            setupViews()
        }
        else {
            let asset = model.selectedAsset
            heartButton.setImage(buttonImage(forFavorite: asset.isFavorite), for: UIControlState())
        }
    }
    
    // MARK: ZoomingPhotoViewDelegate
    func hideControls(_ hide: Bool) {
        guard hide != controlsHidden else {
            return
        }
        
        setControls(alpha: hide ? 0 : 1)
    }
    
    func setControls(alpha: CGFloat) {
        [shareButton, deleteButton, closeButton, heartButton, yearLabel].forEach {
            $0.alpha = alpha
        }
    }
    
    func toggleControlsHidden() {
        hideControls(!controlsHidden)
    }
}
