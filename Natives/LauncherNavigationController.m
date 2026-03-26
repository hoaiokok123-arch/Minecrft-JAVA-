#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "authenticator/BaseAuthenticator.h"
#import "AFNetworking.h"
#import "ALTServerConnection.h"
#import "CustomControlsViewController.h"
#import "DownloadProgressViewController.h"
#import "JavaGUIViewController.h"
#import "LauncherMenuViewController.h"
#import "LauncherNavigationController.h"
#import "LauncherPreferences.h"
#import "LauncherUIStyle.h"
#import "MinecraftResourceDownloadTask.h"
#import "MinecraftResourceUtils.h"
#import "PickTextField.h"
#import "PLPickerView.h"
#import "PLProfiles.h"
#import "UIKit+AFNetworking.h"
#import "UIKit+hook.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

#import <objc/runtime.h>
#include <sys/time.h>

#define AUTORESIZE_MASKS UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin

static void *ProgressObserverContext = &ProgressObserverContext;

@interface LauncherNavigationController () <UIDocumentPickerDelegate, UIPickerViewDataSource, PLPickerViewDelegate, UIPopoverPresentationControllerDelegate> {
}

@property(nonatomic) MinecraftResourceDownloadTask* task;
@property(nonatomic) UINavigationController* progressVC;
@property(nonatomic) NSArray* globalToolbarItems;
@property(nonatomic) UIView* toolbarChromeView;
@property(nonatomic) UIView* toolbarContentView;
@property(nonatomic) PLPickerView* versionPickerView;
@property(nonatomic) UITextField* versionTextField;
@property(nonatomic) UIButton* buttonInstall;
@property(nonatomic) UIBarButtonItem* buttonInstallItem;
@property(nonatomic) BOOL usesLiquidGlassToolbar;
@property(nonatomic) int profileSelectedAt;

@end

@implementation LauncherNavigationController

static const CGFloat LauncherToolbarControlHeight = 36.0;
static const CGFloat LauncherToolbarPlayMinWidth = 86.0;
static const CGFloat LauncherToolbarPlayMaxWidth = 132.0;
static const CGFloat LauncherToolbarFieldMinWidth = 150.0;
static const CGFloat LauncherToolbarFieldMaxWidth = 420.0;

- (void)layoutToolbarControls {
    if (!self.toolbarContentView || !self.versionTextField) {
        return;
    }

    if (self.usesLiquidGlassToolbar) {
        CGFloat availableWidth = MAX(CGRectGetWidth(self.view.bounds) - self.view.safeAreaInsets.left - self.view.safeAreaInsets.right, 0.0);
        CGFloat containerWidth = MIN(MAX(availableWidth - 140.0, 180.0), LauncherToolbarFieldMaxWidth);
        self.toolbarContentView.frame = CGRectMake(0, 0, containerWidth, LauncherToolbarControlHeight);
        self.toolbarChromeView.frame = self.toolbarContentView.bounds;
        self.versionTextField.frame = self.toolbarContentView.bounds;
        self.progressText.frame = self.versionTextField.frame;
        self.progressViewMain.frame = CGRectMake(12.0, LauncherToolbarControlHeight - 3.0, MAX(containerWidth - 24.0, 0.0), 2.0);
        if (self.buttonInstallItem.buttonGlassView) {
            self.buttonInstallItem.buttonGlassView.backgroundColor = [UIColor colorWithRed:121/255.0 green:56/255.0 blue:162/255.0 alpha:0.5];
        }
    } else {
        UIToolbar *targetToolbar = self.toolbar;
        if (!targetToolbar) {
            return;
        }

        UIEdgeInsets safeInsets = targetToolbar.safeAreaInsets;
        CGFloat availableWidth = CGRectGetWidth(targetToolbar.bounds) - safeInsets.left - safeInsets.right;
        CGFloat horizontalPadding = MIN(MAX(availableWidth * 0.03, 8.0), 16.0);
        CGFloat gap = MIN(MAX(availableWidth * 0.025, 8.0), 12.0);
        CGFloat containerWidth = MAX(availableWidth - horizontalPadding * 2.0, 0.0);
        CGFloat containerHeight = MIN(MAX(CGRectGetHeight(targetToolbar.bounds) - 8.0, LauncherToolbarControlHeight), 44.0);
        self.toolbarContentView.frame = CGRectMake(safeInsets.left + horizontalPadding, (CGRectGetHeight(targetToolbar.bounds) - containerHeight) / 2.0, containerWidth, containerHeight);
        self.toolbarChromeView.frame = self.toolbarContentView.bounds;

        CGFloat playWidth = MIN(LauncherToolbarPlayMaxWidth, MAX(LauncherToolbarPlayMinWidth, containerWidth * 0.24));
        if (containerWidth - playWidth - gap < LauncherToolbarFieldMinWidth) {
            playWidth = MAX(76.0, containerWidth - gap - LauncherToolbarFieldMinWidth);
        }
        CGFloat fieldWidth = MAX(containerWidth - playWidth - gap, 0.0);
        self.versionTextField.frame = CGRectMake(0, 0, fieldWidth, containerHeight);
        self.buttonInstall.frame = CGRectMake(CGRectGetMaxX(self.versionTextField.frame) + gap, 0, playWidth, containerHeight);
        self.progressText.frame = self.versionTextField.frame;
        self.progressViewMain.frame = CGRectMake(12.0, containerHeight - 3.0, MAX(fieldWidth - 24.0, 0.0), 2.0);
    }

    CGFloat controlHeight = CGRectGetHeight(self.versionTextField.frame);
    CGFloat accessorySize = MIN(MAX(controlHeight - 10.0, 20.0), 28.0);
    UIImageView *leftView = (UIImageView *)self.versionTextField.leftView;
    UIImageView *rightView = (UIImageView *)self.versionTextField.rightView;
    leftView.frame = CGRectMake(0, 0, accessorySize + 14.0, controlHeight);
    rightView.frame = CGRectMake(0, 0, accessorySize + 8.0, controlHeight);
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    if ([self respondsToSelector:@selector(setNeedsUpdateOfScreenEdgesDeferringSystemGestures)]) {
        [self setNeedsUpdateOfScreenEdgesDeferringSystemGestures];
    }
    UIToolbar *targetToolbar = self.toolbar;
    BOOL hasLiquidGlass = _UISolariumEnabled && _UISolariumEnabled();
    self.usesLiquidGlassToolbar = hasLiquidGlass;
    self.toolbarContentView = [[UIView alloc] initWithFrame:CGRectZero];
    self.toolbarContentView.backgroundColor = UIColor.clearColor;
    self.toolbarChromeView = [[UIView alloc] initWithFrame:CGRectZero];
    self.toolbarChromeView.userInteractionEnabled = NO;
    LauncherStylePanel(self.toolbarChromeView, 18.0);
    self.versionTextField = [[PickTextField alloc] initWithFrame:CGRectMake(0, 0, LauncherToolbarFieldMaxWidth, LauncherToolbarControlHeight)];
    self.progressViewMain = [[UIProgressView alloc] initWithFrame:CGRectZero];
    [self.versionTextField addTarget:self.versionTextField action:@selector(resignFirstResponder) forControlEvents:UIControlEventEditingDidEndOnExit];
    self.versionTextField.placeholder = @"Specify version...";
    self.versionTextField.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.versionTextField.adjustsFontSizeToFitWidth = YES;
    self.versionTextField.minimumFontSize = 13.0;
    UIImageView *profileImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 34, 34)];
    profileImageView.contentMode = UIViewContentModeScaleAspectFit;
    profileImageView.isSizeFixed = YES;
    self.versionTextField.leftView = profileImageView;
    UIImageView *spinnerImageView = [[UIImageView alloc] initWithImage:[[UIImage imageNamed:@"SpinnerArrow"] _imageWithSize:CGSizeMake(24, 24)]];
    spinnerImageView.contentMode = UIViewContentModeScaleAspectFit;
    spinnerImageView.isSizeFixed = YES;
    self.versionTextField.rightView = spinnerImageView;
    self.versionTextField.leftViewMode = UITextFieldViewModeAlways;
    self.versionTextField.rightViewMode = UITextFieldViewModeAlways;
    self.versionTextField.textAlignment = NSTextAlignmentCenter;
    self.versionTextField.textColor = UIColor.labelColor;
    self.versionTextField.backgroundColor = LauncherPanelMutedColor();
    self.versionTextField.layer.cornerRadius = 14.0;
    self.versionTextField.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.versionTextField.layer.borderColor = LauncherOutlineColor().CGColor;
    if ([self.versionTextField.layer respondsToSelector:@selector(setCornerCurve:)]) {
        self.versionTextField.layer.cornerCurve = kCACornerCurveContinuous;
    }

    self.versionPickerView = [[PLPickerView alloc] init];
    self.versionPickerView.delegate = self;
    self.versionPickerView.dataSource = self;

    [self reloadProfileList];

    self.versionTextField.inputView = self.versionPickerView;

    [self.toolbarContentView addSubview:self.toolbarChromeView];
    [self.toolbarContentView addSubview:self.progressViewMain];
    [self.toolbarContentView addSubview:self.versionTextField];

    if(hasLiquidGlass) {
        self.buttonInstallItem = [[UIBarButtonItem alloc] initWithTitle:localize(@"Play", nil)
                                                                  style:UIBarButtonItemStylePlain
                                                                 target:self
                                                                 action:@selector(performInstallOrShowDetails:)];
        self.buttonInstallItem.enabled = NO;
        UIBarButtonItem *textFieldItem = [[UIBarButtonItem alloc] initWithCustomView:self.toolbarContentView];
        self.globalToolbarItems = @[
            textFieldItem,
            self.buttonInstallItem,
        ];
    } else {
        self.buttonInstall = [UIButton buttonWithType:UIButtonTypeSystem];
        setButtonPointerInteraction(self.buttonInstall);
        [self.buttonInstall setTitle:localize(@"Play", nil) forState:UIControlStateNormal];
        self.buttonInstall.autoresizingMask = AUTORESIZE_MASKS;
        self.buttonInstall.backgroundColor = LauncherAccentColor();
        self.buttonInstall.layer.cornerRadius = 16.0;
        self.buttonInstall.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        self.buttonInstall.tintColor = UIColor.whiteColor;
        self.buttonInstall.contentEdgeInsets = UIEdgeInsetsMake(0, 18, 0, 18);
        self.buttonInstall.enabled = NO;
        [self.buttonInstall addTarget:self action:@selector(performInstallOrShowDetails:) forControlEvents:UIControlEventPrimaryActionTriggered];
        [self.toolbarContentView addSubview:self.buttonInstall];
        [targetToolbar addSubview:self.toolbarContentView];
    }
    
    self.progressViewMain.hidden = YES;
    self.progressText = [[UILabel alloc] initWithFrame:CGRectZero];
    self.progressText.adjustsFontSizeToFitWidth = YES;
    self.progressText.font = LauncherCaptionFont(14.0);
    self.progressText.textColor = UIColor.secondaryLabelColor;
    self.progressText.textAlignment = NSTextAlignmentCenter;
    self.progressText.userInteractionEnabled = NO;
    self.progressText.minimumScaleFactor = 0.75;
    [self.toolbarContentView addSubview:self.progressText];
    self.progressViewMain.trackTintColor = UIColor.clearColor;

    [self layoutToolbarControls];

    [self fetchRemoteVersionList];
    [NSNotificationCenter.defaultCenter addObserver:self
        selector:@selector(receiveNotification:) 
        name:@"InstallModpack"
        object:nil];

    if ([BaseAuthenticator.current isKindOfClass:MicrosoftAuthenticator.class]) {
        // Perform token refreshment on startup
        [self setInteractionEnabled:NO forDownloading:NO];
        id callback = ^(id status, BOOL success) {
            status = [status description];
            self.progressText.text = status;
            if (status == nil) {
                [self setInteractionEnabled:YES forDownloading:NO];
            } else if (!success) {
                showDialog(localize(@"Error", nil), status);
            }
        };
        [BaseAuthenticator.current refreshTokenWithCallback:callback];
    }
}

- (void)setViewControllers:(NSArray<UIViewController *> *)viewControllers animated:(BOOL)animated {
    [super setViewControllers:viewControllers animated:animated];
    if (!viewControllers.firstObject.toolbarItems && self.globalToolbarItems) {
        viewControllers.firstObject.toolbarItems = self.globalToolbarItems;
    }
}

- (BOOL)isVersionInstalled:(NSString *)versionId {
    NSString *localPath = [NSString stringWithFormat:@"%s/versions/%@", getenv("POJAV_GAME_DIR"), versionId];
    BOOL isDirectory;
    [NSFileManager.defaultManager fileExistsAtPath:localPath isDirectory:&isDirectory];
    return isDirectory;
}

- (void)fetchLocalVersionList {
    if (!localVersionList) {
        localVersionList = [NSMutableArray new];
    }
    [localVersionList removeAllObjects];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *versionPath = [NSString stringWithFormat:@"%s/versions/", getenv("POJAV_GAME_DIR")];
    NSArray *list = [fileManager contentsOfDirectoryAtPath:versionPath error:Nil];
    for (NSString *versionId in list) {
        if (![self isVersionInstalled:versionId]) continue;
        [localVersionList addObject:@{
            @"id": versionId,
            @"type": @"custom"
        }];
    }
}

- (void)fetchRemoteVersionList {
    [(id)(self.buttonInstall ?: self.buttonInstallItem) setEnabled:NO];
    remoteVersionList = @[
        @{@"id": @"latest-release", @"type": @"release"},
        @{@"id": @"latest-snapshot", @"type": @"snapshot"}
    ].mutableCopy;

    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    [manager GET:@"https://piston-meta.mojang.com/mc/game/version_manifest_v2.json" parameters:nil headers:nil progress:^(NSProgress * _Nonnull progress) {
        self.progressViewMain.progress = progress.fractionCompleted;
    } success:^(NSURLSessionTask *task, NSDictionary *responseObject) {
        [remoteVersionList addObjectsFromArray:responseObject[@"versions"]];
        NSDebugLog(@"[VersionList] Got %d versions", remoteVersionList.count);
        setPrefObject(@"internal.latest_version", responseObject[@"latest"]);
        [(id)(self.buttonInstall ?: self.buttonInstallItem) setEnabled:YES];
    } failure:^(NSURLSessionTask *operation, NSError *error) {
        NSDebugLog(@"[VersionList] Warning: Unable to fetch version list: %@", error.localizedDescription);
        [(id)(self.buttonInstall ?: self.buttonInstallItem) setEnabled:YES];
    }];
}

// Invoked by: startup, instance change event
- (void)reloadProfileList {
    // Reload local version list
    [self fetchLocalVersionList];
    // Reload launcher_profiles.json
    [PLProfiles updateCurrent];
    [self.versionPickerView reloadAllComponents];
    // Reload selected profile info
    self.profileSelectedAt = [PLProfiles.current.profiles.allKeys indexOfObject:PLProfiles.current.selectedProfileName];
    if (self.profileSelectedAt == -1) {
        // This instance has no profiles?
        return;
    }
    [self.versionPickerView selectRow:self.profileSelectedAt inComponent:0 animated:NO];
    [self pickerView:self.versionPickerView didSelectRow:self.profileSelectedAt inComponent:0];
}

#pragma mark - Options
- (void)enterCustomControls {
    CustomControlsViewController *vc = [[CustomControlsViewController alloc] init];
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    vc.setDefaultCtrl = ^(NSString *name){
        setPrefObject(@"control.default_ctrl", name);
    };
    vc.getDefaultCtrl = ^{
        return getPrefObject(@"control.default_ctrl");
    };
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)enterModInstaller {
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[[UTType typeWithMIMEType:@"application/java-archive"]]
        asCopy:YES];
    documentPicker.delegate = self;
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:documentPicker animated:YES completion:nil];
}

- (void)enterModInstallerWithPath:(NSString *)path hitEnterAfterWindowShown:(BOOL)hitEnter {
    JavaGUIViewController *vc = [[JavaGUIViewController alloc] init];
    vc.filepath = path;
    vc.hitEnterAfterWindowShown = hitEnter;
    if (!vc.requiredJavaVersion) {
        return;
    }
    [self invokeAfterJITEnabled:^{
        vc.modalPresentationStyle = UIModalPresentationFullScreen;
        NSLog(@"[ModInstaller] launching %@", vc.filepath);
        [self presentViewController:vc animated:YES completion:nil];
    }];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    [self enterModInstallerWithPath:url.path hitEnterAfterWindowShown:NO];
}

- (void)setInteractionEnabled:(BOOL)enabled forDownloading:(BOOL)downloading {
    self.versionTextField.alpha = enabled ? 1 : 0.2;
    self.versionTextField.enabled = enabled;
    self.progressViewMain.hidden = enabled;
    self.progressText.text = nil;
    if (downloading) {
        if(self.buttonInstall) {
            [self.buttonInstall setTitle:localize(enabled ? @"Play" : @"Details", nil) forState:UIControlStateNormal];
            self.buttonInstall.enabled = YES;
        } else {
            self.buttonInstallItem.title = localize(enabled ? @"Play" : @"Details", nil);
            self.buttonInstallItem.enabled = YES;
        }
    } else {
        self.buttonInstall.enabled = enabled;
        self.buttonInstallItem.enabled = enabled;
    }
    UIApplication.sharedApplication.idleTimerDisabled = !enabled;
}

- (void)launchMinecraft:(UIButton *)sender {
    if (!self.versionTextField.hasText) {
        [self.versionTextField becomeFirstResponder];
        return;
    }

    if (BaseAuthenticator.current == nil) {
        // Present the account selector if none selected
        UIViewController *view = [(UINavigationController *)self.splitViewController.viewControllers[0]
        viewControllers][0];
        [view performSelector:@selector(selectAccount:) withObject:sender];
        return;
    }

    [self setInteractionEnabled:NO forDownloading:YES];

    NSString *versionId = PLProfiles.current.profiles[self.versionTextField.text][@"lastVersionId"];
    NSDictionary *object = [remoteVersionList filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"(id == %@)", versionId]].firstObject;
    if (!object) {
        object = @{
            @"id": versionId,
            @"type": @"custom"
        };
    }

    self.task = [MinecraftResourceDownloadTask new];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __weak LauncherNavigationController *weakSelf = self;
        self.task.handleError = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf setInteractionEnabled:YES forDownloading:YES];
                weakSelf.task = nil;
                weakSelf.progressVC = nil;
            });
        };
        [self.task downloadVersion:object];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressViewMain.observedProgress = self.task.progress;
            [self.task.progress addObserver:self
                forKeyPath:@"fractionCompleted"
                options:NSKeyValueObservingOptionInitial
                context:ProgressObserverContext];
        });
    });
}

- (void)performInstallOrShowDetails:(id)sender {
    BOOL usesBarButtonItem = [sender isKindOfClass:UIBarButtonItem.class];
    if (self.task) {
        if (!self.progressVC) {
            UIViewController *vc = [[DownloadProgressViewController alloc] initWithTask:self.task];
            self.progressVC = [[UINavigationController alloc] initWithRootViewController:vc];
            self.progressVC.modalPresentationStyle = UIModalPresentationPopover;
        } else if (self.progressVC.popoverPresentationController._isDismissing) {
            // FIXME: stock bug? it crashes when users dismisses and presents this vc too fast
            // "UIPopoverPresentationController () should have a non-nil sourceView or barButtonItem set before the presentation occurs."
            return;
        }
        
        if (usesBarButtonItem) {
            self.progressVC.popoverPresentationController.barButtonItem = sender;
        } else {
            self.progressVC.popoverPresentationController.sourceView = sender;
        }
        [self presentViewController:self.progressVC animated:YES completion:nil];
    } else {
        if (usesBarButtonItem) {
            sender = ((UIBarButtonItem *)sender).buttonGlassView;
        }
        [self launchMinecraft:sender];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != ProgressObserverContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }

    // Calculate download speed and ETA
    static CGFloat lastMsTime;
    static NSUInteger lastSecTime, lastCompletedUnitCount;
    NSProgress *progress = self.task.textProgress;
    struct timeval tv;
    gettimeofday(&tv, NULL); 
    NSInteger completedUnitCount = self.task.progress.totalUnitCount * self.task.progress.fractionCompleted;
    progress.completedUnitCount = completedUnitCount;
    if (lastSecTime < tv.tv_sec) {
        CGFloat currentTime = tv.tv_sec + tv.tv_usec / 1000000.0;
        NSInteger throughput = (completedUnitCount - lastCompletedUnitCount) / (currentTime - lastMsTime);
        progress.throughput = @(throughput);
        progress.estimatedTimeRemaining = @((progress.totalUnitCount - completedUnitCount) / throughput);
        lastCompletedUnitCount = completedUnitCount;
        lastSecTime = tv.tv_sec;
        lastMsTime = currentTime;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        self.progressText.text = progress.localizedAdditionalDescription;

        if (!progress.finished) return;
        [self.progressVC dismissModalViewControllerAnimated:NO];

        self.progressViewMain.observedProgress = nil;
        if (self.task.metadata) {
            __block NSDictionary *metadata = self.task.metadata;
            [self invokeAfterJITEnabled:^{
                UIKit_launchMinecraftSurfaceVC(self.view.window, metadata);
            }];
        } else {
            [self reloadProfileList];
        }
        self.task = nil;
        [self setInteractionEnabled:YES forDownloading:YES];
    });
}

- (void)receiveNotification:(NSNotification *)notification {
    if (![notification.name isEqualToString:@"InstallModpack"]) {
        return;
    }
    [self setInteractionEnabled:NO forDownloading:YES];
    self.task = [MinecraftResourceDownloadTask new];
    NSDictionary *userInfo = notification.userInfo;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __weak LauncherNavigationController *weakSelf = self;
        self.task.handleError = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf setInteractionEnabled:YES forDownloading:YES];
                weakSelf.task = nil;
                weakSelf.progressVC = nil;
            });
        };
        [self.task downloadModpackFromAPI:notification.object detail:userInfo[@"detail"] atIndex:[userInfo[@"index"] unsignedLongValue]];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressViewMain.observedProgress = self.task.progress;
            [self.task.progress addObserver:self
                forKeyPath:@"fractionCompleted"
                options:NSKeyValueObservingOptionInitial
                context:ProgressObserverContext];
        });
    });
}

- (void)invokeAfterJITEnabled:(void(^)(void))handler {
    localVersionList = remoteVersionList = nil;
    BOOL hasTrollStoreJIT = getEntitlementValue(@"jb.pmap_cs_custom_trust");
    BOOL isLiveContainer = getenv("LC_HOME_PATH") != NULL;

    if (isJITEnabled(false)) {
        [ALTServerManager.sharedManager stopDiscovering];
        handler();
        return;
    } else if (hasTrollStoreJIT) {
        NSURL *jitURL = [NSURL URLWithString:[NSString stringWithFormat:@"apple-magnifier://enable-jit?bundle-id=%@", NSBundle.mainBundle.bundleIdentifier]];
        [UIApplication.sharedApplication openURL:jitURL options:@{} completionHandler:nil];
        // Do not return, wait for TrollStore to enable JIT and jump back
    } else if (getPrefBool(@"debug.debug_skip_wait_jit")) {
        NSLog(@"Debug option skipped waiting for JIT. Java might not work.");
        handler();
        return;
    } else if (@available(iOS 17.4, *)) {
        NSString *scriptDataString = @"";
        if(DeviceRequiresTXMWorkaround()) {
            NSData *scriptData = [NSData dataWithContentsOfFile:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"UniversalJIT26.js"]];
            scriptDataString = [@"&script-data=" stringByAppendingString:[scriptData base64EncodedStringWithOptions:0]];
        }
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:[NSString stringWithFormat:@"stikjit://enable-jit?bundle-id=%@&pid=%d%@", NSBundle.mainBundle.bundleIdentifier, getpid(), scriptDataString]] options:@{} completionHandler:nil];
    } else {
        // Assuming 16.7-17.3.1. SideStore still lacks this URL scheme at the time of writing, so it only jumps to SideStore.
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:[NSString stringWithFormat:@"sidestore://sidejit-enable?pid=%d", getpid()]] options:@{} completionHandler:nil];
    }

    self.progressText.text = localize(@"launcher.wait_jit.title", nil);

    UIAlertController* alert = [UIAlertController alertControllerWithTitle:localize(@"launcher.wait_jit.title", nil)
        message:hasTrollStoreJIT ? localize(@"launcher.wait_jit_trollstore.message", nil) : localize(@"launcher.wait_jit.message", nil)
        preferredStyle:UIAlertControllerStyleAlert];
/* TODO:
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:^{
        
    }];
    [alert addAction:cancel];
*/
    [self presentViewController:alert animated:YES completion:nil];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        while (!isJITEnabled(false)) {
            // Perform check for every 200ms
            usleep(1000*200);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:handler];
        });
    });
}

#pragma mark - UIPopoverPresentationControllerDelegate
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller traitCollection:(UITraitCollection *)traitCollection {
    return UIModalPresentationNone;
}

#pragma mark - UIPickerView stuff
- (void)pickerView:(PLPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
    self.profileSelectedAt = row;
    //((UIImageView *)self.versionTextField.leftView).image = [pickerView imageAtRow:row column:component];
    ((UIImageView *)self.versionTextField.leftView).image = [pickerView imageAtRow:row column:component];
    self.versionTextField.text = [self pickerView:pickerView titleForRow:row forComponent:component];
    PLProfiles.current.selectedProfileName = self.versionTextField.text;
}

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
    return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    return PLProfiles.current.profiles.count;
}

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
    return PLProfiles.current.profiles.allValues[row][@"name"];
}

- (void)pickerView:(UIPickerView *)pickerView enumerateImageView:(UIImageView *)imageView forRow:(NSInteger)row forComponent:(NSInteger)component {
    UIImage *fallbackImage = [[UIImage imageNamed:@"DefaultProfile"] _imageWithSize:CGSizeMake(40, 40)];
    NSString *urlString = PLProfiles.current.profiles.allValues[row][@"icon"];
    [imageView setImageWithURL:[NSURL URLWithString:urlString] placeholderImage:fallbackImage];
}

- (void)versionClosePicker {
    [self.versionTextField endEditing:YES];
    [self pickerView:self.versionPickerView didSelectRow:[self.versionPickerView selectedRowInComponent:0] inComponent:0];
}

#pragma mark - View controller UI mode

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    [self layoutToolbarControls];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        [self layoutToolbarControls];
        [sidebarViewController updateAccountInfo];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        [self layoutToolbarControls];
        [sidebarViewController updateAccountInfo];
    }];
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [sidebarViewController updateAccountInfo];
    if (self.globalToolbarItems) {
        if (!self.viewControllers.firstObject.toolbarItems) {
            self.viewControllers.firstObject.toolbarItems = self.globalToolbarItems;
        }
    }
    [self layoutToolbarControls];
}

@end
