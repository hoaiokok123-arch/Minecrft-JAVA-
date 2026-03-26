#import "LauncherSplitViewController.h"
#import "LauncherMenuViewController.h"
#import "LauncherProfilesViewController.h"
#import "LauncherNavigationController.h"
#import "LauncherPreferences.h"
#import "utils.h"

extern NSMutableDictionary *prefDict;

@interface LauncherSplitViewController ()<UISplitViewControllerDelegate>{
}
@property(nonatomic) CGSize lastAppliedLayoutSize;
@end

@implementation LauncherSplitViewController

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad || NSProcessInfo.processInfo.isMacCatalystApp) {
        return UIInterfaceOrientationMaskAll;
    }
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationPortrait;
}

- (BOOL)shouldUseTiledSidebarForSize:(CGSize)size {
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad || NSProcessInfo.processInfo.isMacCatalystApp) {
        return self.traitCollection.horizontalSizeClass != UIUserInterfaceSizeClassCompact && size.width >= 700.0;
    }
    return NO;
}

- (CGFloat)preferredSidebarWidthForSize:(CGSize)size {
    BOOL usesTiledSidebar = [self shouldUseTiledSidebarForSize:size];
    CGFloat shorterSide = MIN(size.width, size.height);
    CGFloat preferredWidth = shorterSide * (usesTiledSidebar ? 0.34 : 0.86);
    CGFloat maximumWidth = usesTiledSidebar ? 380.0 : MIN(MAX(size.width - 24.0, 300.0), 360.0);
    return MIN(MAX(preferredWidth, 300.0), maximumWidth);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    if ([getPrefObject(@"control.control_safe_area") length] == 0) {
        setPrefObject(@"control.control_safe_area", NSStringFromUIEdgeInsets(getDefaultSafeArea()));
    }

    self.delegate = self;
    self.presentsWithGesture = YES;

    UINavigationController *masterVc = [[UINavigationController alloc] initWithRootViewController:[[LauncherMenuViewController alloc] init]];
    LauncherNavigationController *detailVc = [[LauncherNavigationController alloc] initWithRootViewController:[[LauncherProfilesViewController alloc] init]];
    detailVc.toolbarHidden = NO;

    self.viewControllers = @[masterVc, detailVc];
    [self changeDisplayModeForSize:self.view.frame.size];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    if (fabs(self.lastAppliedLayoutSize.width - size.width) > 0.5 || fabs(self.lastAppliedLayoutSize.height - size.height) > 0.5) {
        self.lastAppliedLayoutSize = size;
        [self changeDisplayModeForSize:size];
    }
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        [self changeDisplayModeForSize:size];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        [self changeDisplayModeForSize:size];
    }];
}

- (void)changeDisplayModeForSize:(CGSize)size {
    if (size.width <= 0.0 || size.height <= 0.0) {
        return;
    }

    BOOL usesTiledSidebar = [self shouldUseTiledSidebarForSize:size];
    CGFloat sidebarWidth = [self preferredSidebarWidthForSize:size];
    self.minimumPrimaryColumnWidth = MIN(sidebarWidth, 300.0);
    self.preferredPrimaryColumnWidth = sidebarWidth;
    self.maximumPrimaryColumnWidth = MAX(self.minimumPrimaryColumnWidth, MIN(MAX(sidebarWidth + 24.0, sidebarWidth), size.width - 16.0));

    if (getPrefBool(@"general.hidden_sidebar")) {
        self.preferredDisplayMode = UISplitViewControllerDisplayModeSecondaryOnly;
    } else if (usesTiledSidebar) {
        self.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
    } else {
        self.preferredDisplayMode = UISplitViewControllerDisplayModeOneOverSecondary;
    }
    self.preferredSplitBehavior = usesTiledSidebar ?
        UISplitViewControllerSplitBehaviorTile :
        UISplitViewControllerSplitBehaviorOverlay;
}

- (void)dismissViewController {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
