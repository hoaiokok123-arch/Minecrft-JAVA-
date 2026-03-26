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
- (CGSize)availableLayoutSizeForContainerSize:(CGSize)size;
- (void)changeDisplayModeForSize:(CGSize)size force:(BOOL)force;
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
    size = [self availableLayoutSizeForContainerSize:size];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad || NSProcessInfo.processInfo.isMacCatalystApp) {
        return self.traitCollection.horizontalSizeClass != UIUserInterfaceSizeClassCompact && size.width >= 700.0;
    }
    return NO;
}

- (CGSize)availableLayoutSizeForContainerSize:(CGSize)size {
    UIEdgeInsets safeInsets = self.view.safeAreaInsets;
    return CGSizeMake(MAX(size.width - safeInsets.left - safeInsets.right, 0.0),
                      MAX(size.height - safeInsets.top - safeInsets.bottom, 0.0));
}

- (CGFloat)preferredSidebarWidthForSize:(CGSize)size {
    size = [self availableLayoutSizeForContainerSize:size];
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
    self.primaryEdge = UISplitViewControllerPrimaryEdgeLeading;

    UINavigationController *masterVc = [[UINavigationController alloc] initWithRootViewController:[[LauncherMenuViewController alloc] init]];
    LauncherNavigationController *detailVc = [[LauncherNavigationController alloc] initWithRootViewController:[[LauncherProfilesViewController alloc] init]];
    detailVc.toolbarHidden = NO;

    self.viewControllers = @[masterVc, detailVc];
    [self changeDisplayModeForSize:self.view.bounds.size force:YES];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    if (fabs(self.lastAppliedLayoutSize.width - size.width) > 0.5 || fabs(self.lastAppliedLayoutSize.height - size.height) > 0.5) {
        self.lastAppliedLayoutSize = size;
        [self changeDisplayModeForSize:size force:NO];
    }
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    self.lastAppliedLayoutSize = CGSizeZero;
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        [self.view setNeedsLayout];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        [self changeDisplayModeForSize:self.view.bounds.size force:YES];
    }];
}

- (void)changeDisplayModeForSize:(CGSize)size force:(BOOL)force {
    if (size.width <= 0.0 || size.height <= 0.0) {
        return;
    }

    CGSize availableSize = [self availableLayoutSizeForContainerSize:size];
    BOOL usesTiledSidebar = [self shouldUseTiledSidebarForSize:size];
    CGFloat sidebarWidth = [self preferredSidebarWidthForSize:size];
    CGFloat minimumWidth = MIN(sidebarWidth, 300.0);
    CGFloat maximumWidth = MAX(minimumWidth, MIN(MAX(sidebarWidth + 24.0, sidebarWidth), MAX(availableSize.width - 16.0, minimumWidth)));
    UISplitViewControllerDisplayMode preferredDisplayMode = getPrefBool(@"general.hidden_sidebar") ?
        UISplitViewControllerDisplayModeSecondaryOnly :
        (usesTiledSidebar ? UISplitViewControllerDisplayModeOneBesideSecondary : UISplitViewControllerDisplayModeOneOverSecondary);
    UISplitViewControllerSplitBehavior preferredSplitBehavior = usesTiledSidebar ?
        UISplitViewControllerSplitBehaviorTile :
        UISplitViewControllerSplitBehaviorOverlay;
    BOOL layoutChanged =
        fabs(self.minimumPrimaryColumnWidth - minimumWidth) > 0.5 ||
        fabs(self.preferredPrimaryColumnWidth - sidebarWidth) > 0.5 ||
        fabs(self.maximumPrimaryColumnWidth - maximumWidth) > 0.5 ||
        self.preferredDisplayMode != preferredDisplayMode ||
        self.preferredSplitBehavior != preferredSplitBehavior;
    if (!force && !layoutChanged) {
        return;
    }

    [UIView performWithoutAnimation:^{
        self.minimumPrimaryColumnWidth = minimumWidth;
        self.preferredPrimaryColumnWidth = sidebarWidth;
        self.maximumPrimaryColumnWidth = maximumWidth;
        self.preferredDisplayMode = preferredDisplayMode;
        self.preferredSplitBehavior = preferredSplitBehavior;
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    }];
}

- (void)dismissViewController {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
