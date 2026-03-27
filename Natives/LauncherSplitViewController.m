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
@property(nonatomic) UIView *backgroundDimView;
@property(nonatomic) AVQueuePlayer *backgroundPlayer;
@property(nonatomic) AVPlayerLooper *backgroundLooper;
@property(nonatomic) AVPlayerLayer *backgroundLayer;
@end

@implementation LauncherSplitViewController

- (void)updatePrimaryColumnWidthForSize:(CGSize)size {
    CGFloat compactWidth = MIN(300, MAX(260, size.width * 0.74));
    self.minimumPrimaryColumnWidth = compactWidth;
    self.maximumPrimaryColumnWidth = compactWidth;
    self.preferredPrimaryColumnWidthFraction = compactWidth / MAX(size.width, 1);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    if ([getPrefObject(@"control.control_safe_area") length] == 0) {
        setPrefObject(@"control.control_safe_area", NSStringFromUIEdgeInsets(getDefaultSafeArea()));
    }

    self.delegate = self;
    self.backgroundVideoView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.backgroundVideoView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backgroundVideoView.userInteractionEnabled = NO;
    [self.view addSubview:self.backgroundVideoView];

    self.backgroundDimView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.backgroundDimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backgroundDimView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    self.backgroundDimView.userInteractionEnabled = NO;
    [self.view addSubview:self.backgroundDimView];

    UINavigationController *masterVc = [[UINavigationController alloc] initWithRootViewController:[[LauncherMenuViewController alloc] init]];
    LauncherNavigationController *detailVc = [[LauncherNavigationController alloc] initWithRootViewController:[[LauncherProfilesViewController alloc] init]];
    masterVc.view.backgroundColor = UIColor.clearColor;
    detailVc.view.backgroundColor = UIColor.clearColor;
    detailVc.toolbarHidden = NO;

    self.viewControllers = @[masterVc, detailVc];
    [self changeDisplayModeForSize:self.view.frame.size];
    [self updatePrimaryColumnWidthForSize:self.view.bounds.size];
    [self reloadBackgroundVideo];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleLauncherBackgroundDidChange:)
        name:PLLauncherBackgroundDidChangeNotification object:nil];
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
        self.backgroundLayer.frame = self.backgroundVideoView.bounds;
    } completion:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.backgroundLayer.frame = self.backgroundVideoView.bounds;
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
    [self.backgroundPlayer play];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.backgroundPlayer pause];
}

- (void)reloadBackgroundVideo {
    [self.backgroundPlayer pause];
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
    self.backgroundLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.backgroundLayer.frame = self.backgroundVideoView.bounds;
    [self.backgroundVideoView.layer addSublayer:self.backgroundLayer];

    self.backgroundVideoView.hidden = NO;
    self.backgroundDimView.hidden = NO;
    [player play];
}

- (void)handleLauncherBackgroundDidChange:(NSNotification *)notification {
    [self reloadBackgroundVideo];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

@end
