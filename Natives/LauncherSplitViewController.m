#import "LauncherSplitViewController.h"
#import "LauncherMenuViewController.h"
#import "LauncherProfilesViewController.h"
#import "LauncherNavigationController.h"
#import "LauncherPreferences.h"
#import "utils.h"

extern NSMutableDictionary *prefDict;

@interface LauncherSplitViewController ()<UISplitViewControllerDelegate>{
}
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
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    if ([getPrefObject(@"control.control_safe_area") length] == 0) {
        setPrefObject(@"control.control_safe_area", NSStringFromUIEdgeInsets(getDefaultSafeArea()));
    }

    self.delegate = self;

    UINavigationController *masterVc = [[UINavigationController alloc] initWithRootViewController:[[LauncherMenuViewController alloc] init]];
    LauncherNavigationController *detailVc = [[LauncherNavigationController alloc] initWithRootViewController:[[LauncherProfilesViewController alloc] init]];
    detailVc.toolbarHidden = NO;

    self.viewControllers = @[masterVc, detailVc];
    [self changeDisplayModeForSize:self.view.frame.size];
    [self updatePrimaryColumnWidthForSize:self.view.bounds.size];
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
    } completion:nil];
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

@end
