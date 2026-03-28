#import <AVFoundation/AVFoundation.h>

#import "LauncherSplitViewController.h"
#import "LauncherMenuViewController.h"
#import "LauncherProfilesViewController.h"
#import "LauncherNavigationController.h"
#import "LauncherPreferences.h"
#import "utils.h"

extern NSMutableDictionary *prefDict;

@interface LauncherSplitViewController ()<UISplitViewControllerDelegate>{
}
@property(nonatomic) UIView *backgroundVideoView;
@property(nonatomic) UIView *backgroundVideoContentView;
@property(nonatomic) UIView *backgroundDimView;
@property(nonatomic) AVQueuePlayer *backgroundPlayer;
@property(nonatomic) AVPlayerLooper *backgroundLooper;
@property(nonatomic) AVPlayerLayer *backgroundLayer;
@end

@implementation LauncherSplitViewController

- (void)applyBackgroundDimAppearance {
    CGFloat dimAlpha = 0.08;
    self.backgroundDimView.backgroundColor = [UIColor colorWithWhite:0 alpha:dimAlpha];
    self.backgroundDimView.hidden = self.backgroundVideoView.hidden || dimAlpha <= 0.001;
}

- (void)sendBackgroundViewsToBack {
    if (self.backgroundDimView.superview == self.view) {
        [self.view sendSubviewToBack:self.backgroundDimView];
    }
    if (self.backgroundVideoView.superview == self.view) {
        [self.view sendSubviewToBack:self.backgroundVideoView];
    }
}

- (void)updatePrimaryColumnWidthForSize:(CGSize)size {
    CGFloat compactWidth = MIN(300, MAX(260, size.width * 0.74));
    self.minimumPrimaryColumnWidth = compactWidth;
    self.maximumPrimaryColumnWidth = compactWidth;
    self.preferredPrimaryColumnWidthFraction = compactWidth / MAX(size.width, 1);
}

- (void)applyBackgroundVideoLayout {
    if (!self.backgroundLayer) {
        return;
    }

    CGRect bounds = self.backgroundVideoView.bounds;
    CGFloat scale = getLauncherBackgroundVideoScale();
    BOOL rotateVideo = getLauncherBackgroundVideoRotateEnabled();
    CGSize scaledSize = CGSizeMake(bounds.size.width * scale, bounds.size.height * scale);
    CGSize contentSize = rotateVideo ?
        CGSizeMake(scaledSize.height, scaledSize.width) :
        scaledSize;
    self.backgroundVideoContentView.transform = CGAffineTransformIdentity;
    self.backgroundVideoContentView.frame = CGRectMake(
        CGRectGetMidX(bounds) - contentSize.width * 0.5,
        CGRectGetMidY(bounds) - contentSize.height * 0.5,
        contentSize.width,
        contentSize.height);
    self.backgroundVideoContentView.transform = rotateVideo ?
        CGAffineTransformMakeRotation((CGFloat)M_PI_2) :
        CGAffineTransformIdentity;
    self.backgroundLayer.frame = self.backgroundVideoContentView.bounds;
}

- (void)resumeBackgroundPlaybackIfNeeded {
    if (!self.backgroundPlayer || self.backgroundVideoView.hidden || self.view.window == nil) {
        return;
    }
    if (self.backgroundPlayer.items.count == 0 || self.backgroundPlayer.currentItem.status == AVPlayerItemStatusFailed) {
        [self reloadBackgroundVideo];
        return;
    }
    [self.backgroundPlayer play];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    if ([getPrefObject(@"control.control_safe_area") length] == 0) {
        setPrefObject(@"control.control_safe_area", NSStringFromUIEdgeInsets(getDefaultSafeArea()));
    }

    self.delegate = self;
    self.backgroundVideoView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.backgroundVideoView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backgroundVideoView.clipsToBounds = YES;
    self.backgroundVideoView.userInteractionEnabled = NO;
    self.backgroundVideoView.backgroundColor = UIColor.clearColor;
    [self.view addSubview:self.backgroundVideoView];

    self.backgroundVideoContentView = [[UIView alloc] initWithFrame:self.backgroundVideoView.bounds];
    self.backgroundVideoContentView.userInteractionEnabled = NO;
    self.backgroundVideoContentView.backgroundColor = UIColor.clearColor;
    [self.backgroundVideoView addSubview:self.backgroundVideoContentView];

    self.backgroundDimView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.backgroundDimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backgroundDimView.userInteractionEnabled = NO;
    [self.view addSubview:self.backgroundDimView];
    [self applyBackgroundDimAppearance];

    UINavigationController *masterVc = [[UINavigationController alloc] initWithRootViewController:[[LauncherMenuViewController alloc] init]];
    LauncherNavigationController *detailVc = [[LauncherNavigationController alloc] initWithRootViewController:[[LauncherProfilesViewController alloc] init]];
    masterVc.view.backgroundColor = UIColor.clearColor;
    detailVc.view.backgroundColor = UIColor.clearColor;
    detailVc.toolbarHidden = NO;
    PLApplyLauncherNavigationBarChrome(masterVc.navigationBar);
    PLApplyLauncherNavigationBarChrome(detailVc.navigationBar);
    PLApplyLauncherToolbarChrome(detailVc.toolbar);

    self.viewControllers = @[masterVc, detailVc];
    [self changeDisplayModeForSize:self.view.frame.size];
    [self updatePrimaryColumnWidthForSize:self.view.bounds.size];
    [self reloadBackgroundVideo];
    [self sendBackgroundViewsToBack];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleLauncherBackgroundDidChange:)
        name:PLLauncherBackgroundDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleLauncherAppearanceDidChange:)
        name:PLLauncherAppearanceDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleApplicationDidBecomeActive:)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleApplicationWillResignActive:)
        name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleBackgroundPlaybackStalled:)
        name:AVPlayerItemPlaybackStalledNotification object:nil];
}

- (void)splitViewController:(UISplitViewController *)svc willChangeToDisplayMode:(UISplitViewControllerDisplayMode)displayMode {
    if (self.preferredDisplayMode != displayMode && self.displayMode != UISplitViewControllerDisplayModeSecondaryOnly) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.preferredDisplayMode = UISplitViewControllerDisplayModeSecondaryOnly;
        });
    }
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [self changeDisplayModeForSize:size];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        [self updatePrimaryColumnWidthForSize:size];
        [self applyBackgroundVideoLayout];
    } completion:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    PLApplyLauncherViewChrome(self.view);
    [self applyBackgroundVideoLayout];
    [self applyBackgroundDimAppearance];
    [self sendBackgroundViewsToBack];
}

- (void)changeDisplayModeForSize:(CGSize)size {
    BOOL isPortrait = size.height > size.width;
    if (self.preferredDisplayMode == 0 || self.displayMode != UISplitViewControllerDisplayModeSecondaryOnly) {
        if(!getPrefBool(@"general.hidden_sidebar")) {
            self.preferredDisplayMode = isPortrait ?
                UISplitViewControllerDisplayModeOneOverSecondary :
                UISplitViewControllerDisplayModeOneBesideSecondary;
        } else {
            self.preferredDisplayMode = UISplitViewControllerDisplayModeSecondaryOnly;
        }
    }
    self.preferredSplitBehavior = isPortrait ?
        UISplitViewControllerSplitBehaviorOverlay :
        UISplitViewControllerSplitBehaviorTile;
    [self updatePrimaryColumnWidthForSize:size];
}

- (void)dismissViewController {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self resumeBackgroundPlaybackIfNeeded];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.backgroundPlayer pause];
}

- (void)reloadBackgroundVideo {
    [self.backgroundPlayer pause];
    [self.backgroundPlayer removeAllItems];
    [self.backgroundLayer removeAllAnimations];
    self.backgroundLayer.player = nil;
    [self.backgroundLayer removeFromSuperlayer];
    self.backgroundLayer = nil;
    self.backgroundLooper = nil;
    self.backgroundPlayer = nil;

    NSString *path = getLauncherBackgroundVideoPath();
    if (path.length == 0) {
        self.backgroundVideoView.hidden = YES;
        self.backgroundDimView.hidden = YES;
        return;
    }

    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:path]];
    AVQueuePlayer *player = [AVQueuePlayer queuePlayerWithItems:@[]];
    player.muted = YES;

    self.backgroundLooper = [AVPlayerLooper playerLooperWithPlayer:player templateItem:item];
    self.backgroundPlayer = player;
    self.backgroundLayer = [AVPlayerLayer playerLayerWithPlayer:player];
    self.backgroundLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    self.backgroundLayer.backgroundColor = UIColor.clearColor.CGColor;
    [self.backgroundVideoContentView.layer addSublayer:self.backgroundLayer];
    [self applyBackgroundVideoLayout];

    self.backgroundVideoView.hidden = NO;
    [self applyBackgroundDimAppearance];
    [self sendBackgroundViewsToBack];
    [self resumeBackgroundPlaybackIfNeeded];
}

- (void)handleLauncherBackgroundDidChange:(NSNotification *)notification {
    [self reloadBackgroundVideo];
}

- (void)handleLauncherAppearanceDidChange:(NSNotification *)notification {
    UINavigationController *masterVc = (UINavigationController *)self.viewControllers.firstObject;
    LauncherNavigationController *detailVc = (LauncherNavigationController *)self.viewControllers.lastObject;
    PLApplyLauncherNavigationBarChrome(masterVc.navigationBar);
    PLApplyLauncherNavigationBarChrome(detailVc.navigationBar);
    PLApplyLauncherToolbarChrome(detailVc.toolbar);
    PLApplyLauncherViewChrome(self.view);
    [self applyBackgroundDimAppearance];
    [self applyBackgroundVideoLayout];
    [self resumeBackgroundPlaybackIfNeeded];
}

- (void)handleApplicationDidBecomeActive:(NSNotification *)notification {
    [self resumeBackgroundPlaybackIfNeeded];
}

- (void)handleApplicationWillResignActive:(NSNotification *)notification {
    [self.backgroundPlayer pause];
}

- (void)handleBackgroundPlaybackStalled:(NSNotification *)notification {
    if (notification.object != self.backgroundPlayer.currentItem) {
        return;
    }
    [self resumeBackgroundPlaybackIfNeeded];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

@end
