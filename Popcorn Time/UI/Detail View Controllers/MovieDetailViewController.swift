

import UIKit
import XCDYouTubeKit
import AlamofireImage
import ColorArt
import PopcornTorrent

class MovieDetailViewController: DetailItemOverviewViewController, PCTTablePickerViewDelegate, UIViewControllerTransitioningDelegate {
    
    @IBOutlet var torrentHealth: CircularView!
    @IBOutlet var qualityBtn: UIButton!
    @IBOutlet var subtitlesButton: UIButton!
    @IBOutlet var playButton: PCTBorderButton!
    @IBOutlet var watchedBtn: UIBarButtonItem!
    @IBOutlet var trailerBtn: UIButton!
    @IBOutlet var collectionView: UICollectionView!
    @IBOutlet var regularConstraints: [NSLayoutConstraint]!
    @IBOutlet var compactConstraints: [NSLayoutConstraint]!
    
    var currentItem: PCTMovie!
    var relatedItems = [PCTMovie]()
    var cast = [PCTActor]()
    var subtitlesTablePickerView: PCTTablePickerView!
    private var classContext = 0
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        WatchlistManager.movieManager.getProgress()
        view.addObserver(self, forKeyPath: "frame", options: .New, context: &classContext)
    }
    
    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        view.removeObserver(self, forKeyPath: "frame")
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        subtitlesTablePickerView?.setNeedsLayout()
        subtitlesTablePickerView?.layoutIfNeeded()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = currentItem.title
        currentItem.coverImageAsString = currentItem.coverImageAsString?.stringByReplacingOccurrencesOfString("thumb", withString: "medium")
        watchedBtn.image = getWatchedButtonImage()
        let adjustForTabbarInsets = UIEdgeInsetsMake(0, 0, CGRectGetHeight(tabBarController!.tabBar.frame), 0)
        scrollView.contentInset = adjustForTabbarInsets
        scrollView.scrollIndicatorInsets = adjustForTabbarInsets
        titleLabel.text = currentItem.title
        summaryView.text = currentItem.summary
        ratingView.rating = Float(currentItem.rating)
        infoLabel.text = "\(currentItem.year) ● \(currentItem.runtime) min ● \(currentItem.genres[0].capitalizedString)"
        playButton.borderColor = SLColorArt(image: backgroundImageView.image).secondaryColor
        trailerBtn.enabled = currentItem.trailerURLString != nil
        MovieAPI.sharedInstance.getMovieInfo(currentItem.id, completion: {
            self.currentItem.torrents = $0
            self.currentItem.currentTorrent = self.currentItem.torrents.filter({$0.quality == NSUserDefaults.standardUserDefaults().stringForKey("PreferredQuality")}).first ?? self.currentItem.torrents.first!
            self.torrentHealth.backgroundColor = self.currentItem.currentTorrent.health.color()
            self.playButton.enabled = self.currentItem.currentTorrent.url != nil
            self.qualityBtn?.userInteractionEnabled = self.currentItem.torrents.count > 1
            self.qualityBtn?.setTitle("\(self.currentItem.currentTorrent.quality! + (self.currentItem.torrents.count > 1 ? " ▾" : ""))", forState: .Normal)
        })
        OpenSubtitles.sharedInstance.login({
            OpenSubtitles.sharedInstance.search(imdbId: self.currentItem.id, completion: {
                subtitles in
                self.currentItem.subtitles = subtitles
                if subtitles.count == 0 {
                    self.subtitlesButton.setTitle("No Subtitles Available", forState: .Normal)
                } else {
                    self.subtitlesButton.setTitle("None ▾", forState: .Normal)
                    self.subtitlesButton.userInteractionEnabled = true
                    if let preferredSubtitle = NSUserDefaults.standardUserDefaults().objectForKey("PreferredSubtitleLanguage") as? String where preferredSubtitle != "None" {
                        let languages = subtitles.map({$0.language})
                        let index = languages.indexOf(languages.filter({$0 == preferredSubtitle}).first!)!
                        let subtitle = self.currentItem.subtitles![index]
                        self.currentItem.currentSubtitle = subtitle
                        self.subtitlesButton.setTitle(subtitle.language + " ▾", forState: .Normal)
                    }
                }
                self.subtitlesTablePickerView = PCTTablePickerView(superView: self.view, sourceDict: PCTSubtitle.dictValue(subtitles), self)
                if let link = self.currentItem.currentSubtitle?.link {
                    self.subtitlesTablePickerView.selectedItems = [link]
                }
                self.tabBarController?.view.addSubview(self.subtitlesTablePickerView)
            })
        })
        MovieAPI.sharedInstance.getDetailedMovieInfo(currentItem.id) { (actors, related) in
            self.relatedItems = related as! [PCTMovie]
            self.cast = actors
            self.collectionView.reloadData()
        }
    }
    
    func getWatchedButtonImage() -> UIImage {
        return WatchlistManager.movieManager.isWatched(currentItem.id) ? UIImage(named: "WatchedOn")! : UIImage(named: "WatchedOff")!
    }
    
    @IBAction func toggleWatched() {
        WatchlistManager.movieManager.toggleWatched(currentItem.id)
        watchedBtn.image = getWatchedButtonImage()
    }
    
    @IBAction func changeQualityTapped(sender: UIButton) {
        let quality = UIAlertController(title:"Select Quality", message:nil, preferredStyle:UIAlertControllerStyle.ActionSheet)
        for torrent in currentItem.torrents {
            quality.addAction(UIAlertAction(title: "\(torrent.quality!) \(torrent.size!)", style: .Default, handler: { action in
                self.currentItem.currentTorrent = torrent
                self.playButton.enabled = self.currentItem.currentTorrent.url != nil
                self.qualityBtn.setTitle("\(torrent.quality!) ▾", forState: .Normal)
                self.torrentHealth.backgroundColor = torrent.health.color()
            }))
        }
        quality.addAction(UIAlertAction(title: "Cancel", style: .Cancel, handler: nil))
        quality.popoverPresentationController?.sourceView = sender
        fixPopOverAnchor(quality)
        presentViewController(quality, animated: true, completion: nil)
    }
    
    @IBAction func changeSubtitlesTapped(sender: UIButton) {
        subtitlesTablePickerView.toggle()
    }
    
    @IBAction func watchNowTapped(sender: UIButton) {
        let onWifi: Bool = (UIApplication.sharedApplication().delegate! as! AppDelegate).reachability!.isReachableViaWiFi()
        let wifiOnly: Bool = !NSUserDefaults.standardUserDefaults().boolForKey("StreamOnCellular")
        if !wifiOnly || onWifi {
            loadMovieTorrent(currentItem)
        } else {
            let errorAlert = UIAlertController(title: "Cellular Data is Turned Off for streaming", message: "To enable it please go to settings.", preferredStyle: UIAlertControllerStyle.Alert)
            errorAlert.addAction(UIAlertAction(title: "OK", style: .Cancel, handler: nil))
            errorAlert.addAction(UIAlertAction(title: "Settings", style: .Default, handler: { _ in
                let settings = self.storyboard!.instantiateViewControllerWithIdentifier("SettingsTableViewController") as! SettingsTableViewController
                self.navigationController?.pushViewController(settings, animated: true)
            }))
            self.presentViewController(errorAlert, animated: true, completion: nil)
        }
    }
    
    func loadMovieTorrent(media: PCTMovie, onChromecast: Bool = GCKCastContext.sharedInstance().castState == .Connected) {
        let loadingViewController = storyboard!.instantiateViewControllerWithIdentifier("LoadingViewController") as! LoadingViewController
        loadingViewController.transitioningDelegate = self
        loadingViewController.backgroundImage = backgroundImageView.image
        presentViewController(loadingViewController, animated: true, completion: nil)
        downloadTorrentFile(media.currentTorrent.url!) { [unowned self] (url, error) in
            if let url = url {
                let moviePlayer = self.storyboard!.instantiateViewControllerWithIdentifier("PCTPlayerViewController") as! PCTPlayerViewController
                moviePlayer.delegate = self
                let currentProgress = WatchlistManager.movieManager.currentProgress(media.id)
                let castDevice = GCKCastContext.sharedInstance().sessionManager.currentSession?.device
                PTTorrentStreamer.sharedStreamer().startStreamingFromFileOrMagnetLink(url, progress: { status in
                    loadingViewController.progress = status.bufferingProgress
                    loadingViewController.speed = Int(status.downloadSpeed)
                    loadingViewController.seeds = Int(status.seeds)
                    loadingViewController.updateProgress()
                    moviePlayer.bufferProgressView?.progress = status.totalProgreess
                    }, readyToPlay: {(videoFileURL, videoFilePath) in
                        loadingViewController.dismissViewControllerAnimated(false, completion: nil)
                        if onChromecast {
                            if GCKCastContext.sharedInstance().sessionManager.currentSession == nil {
                                GCKCastContext.sharedInstance().sessionManager.startSessionWithDevice(castDevice!)
                            }
                            let castPlayerViewController = self.storyboard?.instantiateViewControllerWithIdentifier("CastPlayerViewController") as! CastPlayerViewController
                            let castMetadata = PCTCastMetaData(movie: media, url: videoFileURL.relativeString!, mediaAssetsPath: videoFilePath.URLByDeletingLastPathComponent!)
                            GoogleCastManager(castMetadata: castMetadata).sessionManager(GCKCastContext.sharedInstance().sessionManager, didStartSession: GCKCastContext.sharedInstance().sessionManager.currentSession!)
                            castPlayerViewController.backgroundImage = self.backgroundImageView.image
                            castPlayerViewController.title = media.title
                            castPlayerViewController.media = media
                            castPlayerViewController.startPosition = NSTimeInterval(currentProgress)
                            castPlayerViewController.directory = videoFilePath.URLByDeletingLastPathComponent!
                            self.presentViewController(castPlayerViewController, animated: true, completion: nil)
                        } else {
                            moviePlayer.play(media, fromURL: videoFileURL, progress: currentProgress, directory: videoFilePath.URLByDeletingLastPathComponent!)
                            moviePlayer.delegate = self
                            self.presentViewController(moviePlayer, animated: true, completion: nil)
                        }
                }) { error in
                    loadingViewController.cancelButtonPressed()
                    let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .Alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .Cancel, handler: nil))
                    self.presentViewController(alert, animated: true, completion: nil)
                    print("Error is \(error)")
                }
            } else if let error = error {
                loadingViewController.dismissViewControllerAnimated(true, completion: { [unowned self] in
                    let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .Alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .Cancel, handler: nil))
                    self.presentViewController(alert, animated: true, completion: nil)
                    })
            }
        }
    }
    
	@IBAction func watchTrailerTapped() {
        let vc = XCDYouTubeVideoPlayerViewController(videoIdentifier: currentItem.trailerURLString)
        presentViewController(vc, animated: true, completion: nil)
	}
    
    func tablePickerView(tablePickerView: PCTTablePickerView, didClose items: [String]) {
        if items.count == 0 {
            currentItem.currentSubtitle = nil
            subtitlesButton.setTitle("None ▾", forState: .Normal)
        } else {
            let links = currentItem.subtitles!.map({$0.link})
            let index = links.indexOf(links.filter({$0 == items.first!}).first!)!
            let subtitle = currentItem.subtitles![index]
            currentItem.currentSubtitle = subtitle
            subtitlesButton.setTitle(subtitle.language + " ▾", forState: .Normal)
        }
    }
    
    func animationControllerForPresentedController(presented: UIViewController, presentingController presenting: UIViewController, sourceController source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return presented is LoadingViewController ? PCTLoadingViewAnimatedTransitioning(isPresenting: true, sourceController: source) : nil
    }
    
    func animationControllerForDismissedController(dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return dismissed is LoadingViewController ? PCTLoadingViewAnimatedTransitioning(isPresenting: false, sourceController: self) : nil
    }
}

extension MovieDetailViewController: UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func numberOfSectionsInCollectionView(collectionView: UICollectionView) -> Int {
        var sections = 0
        if relatedItems.count > 0 {sections += 1}; if cast.count > 0 {sections += 1}
        return sections
    }
    func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return section == 0 ? relatedItems.count : cast.count
    }
    
    func collectionView(collectionView: UICollectionView,layout collectionViewLayout: UICollectionViewLayout,sizeForItemAtIndexPath indexPath: NSIndexPath) -> CGSize {
        var items = 1
        while (collectionView.bounds.width/CGFloat(items))-8 > 195 {
            items += 1
        }
        let width = (collectionView.bounds.width/CGFloat(items))-8
        let ratio = width/195.0
        let height = 280.0 * ratio
        return CGSizeMake(width, height)
    }
    
    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        if &classContext == context && keyPath == "frame" {
            collectionView.collectionViewLayout.invalidateLayout()
        }
    }
    
    func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        let cell: UICollectionViewCell
        if indexPath.section == 0 {
            cell = {
               let coverCell = collectionView.dequeueReusableCellWithReuseIdentifier("relatedCell", forIndexPath: indexPath) as! CoverCollectionViewCell
                coverCell.titleLabel.text = relatedItems[indexPath.row].title
                coverCell.yearLabel.text = relatedItems[indexPath.row].year
                if let image = relatedItems[indexPath.row].coverImageAsString,
                    let url = NSURL(string: image) {
                    coverCell.coverImage.af_setImageWithURL(url, placeholderImage: UIImage(named: "Placeholder"))
                }
                coverCell.watched = WatchlistManager.movieManager.isWatched(relatedItems[indexPath.row].id)
                return coverCell
            }()
        } else {
            cell = collectionView.dequeueReusableCellWithReuseIdentifier("castCell", forIndexPath: indexPath)
            let imageView = cell.viewWithTag(1) as! UIImageView
            if let image = cast[indexPath.row].imageAsString,
                let url = NSURL(string: image) {
                imageView.af_setImageWithURL(url, placeholderImage: UIImage(named: "Placeholder"))
            }
            imageView.layer.cornerRadius = self.collectionView(collectionView, layout: collectionView.collectionViewLayout, sizeForItemAtIndexPath: indexPath).width/2
            (cell.viewWithTag(2) as! UILabel).text = cast[indexPath.row].name
            (cell.viewWithTag(3) as! UILabel).text = cast[indexPath.row].character
        }
        return cell
    }
    func collectionView(collectionView: UICollectionView, didSelectItemAtIndexPath indexPath: NSIndexPath) {
        if indexPath.section == 0 {
            let movieDetail = storyboard?.instantiateViewControllerWithIdentifier("MovieDetailViewController") as! MovieDetailViewController
            movieDetail.currentItem = relatedItems[indexPath.row]
            navigationController?.pushViewController(movieDetail, animated: true)
        }
    }
    
    override func traitCollectionDidChange(previousTraitCollection: UITraitCollection?) {
        if let coverImageAsString = currentItem.coverImageAsString,
            let backgroundImageAsString = currentItem.backgroundImageAsString {
            backgroundImageView.af_setImageWithURLRequest(NSURLRequest(URL: NSURL(string: traitCollection.horizontalSizeClass == .Compact ? coverImageAsString : backgroundImageAsString)!), placeholderImage: UIImage(named: "Placeholder"), imageTransition: .CrossDissolve(animationLength), completion: {
                if let value = $0.result.value {
                    self.playButton.borderColor = SLColorArt(image: value).secondaryColor
                }
            })
        }
        
        for constraint in compactConstraints {
            constraint.priority = traitCollection.horizontalSizeClass == .Compact ? 999 : 240
        }
        for constraint in regularConstraints {
            constraint.priority = traitCollection.horizontalSizeClass == .Compact ? 240 : 999
        }
        UIView.animateWithDuration(animationLength, animations: {
            self.view.layoutIfNeeded()
            self.collectionView.collectionViewLayout.invalidateLayout()
        })
    }
    
    func collectionView(collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, atIndexPath indexPath: NSIndexPath) -> UICollectionReusableView {
        if kind == UICollectionElementKindSectionHeader {
            return {
               let element = collectionView.dequeueReusableSupplementaryViewOfKind(kind, withReuseIdentifier: "header", forIndexPath: indexPath)
                (element.viewWithTag(1) as! UILabel).text = indexPath.section == 0 ? "RELATED" : "CAST"
                return element
            }()
        }
        return collectionView.dequeueReusableSupplementaryViewOfKind(kind, withReuseIdentifier: "footer", forIndexPath: indexPath)
    }
    
    override func gestureRecognizer(gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWithGestureRecognizer otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return collectionView.gestureRecognizers?.filter({$0 == gestureRecognizer || $0 == otherGestureRecognizer}).first == nil
    }
}
