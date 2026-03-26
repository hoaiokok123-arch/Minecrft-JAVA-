#import "authenticator/BaseAuthenticator.h"
#import "AccountListViewController.h"
#import "AFNetworking.h"
#import "ALTServerConnection.h"
#import "LauncherNavigationController.h"
#import "LauncherMenuViewController.h"
#import "LauncherNewsViewController.h"
#import "LauncherPreferences.h"
#import "LauncherPreferencesViewController.h"
#import "LauncherProfilesViewController.h"
#import "LauncherUIStyle.h"
#import "PLProfiles.h"
#import "UIButton+AFNetworking.h"
#import "UIImageView+AFNetworking.h"
#import "UIKit+hook.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

#include <dlfcn.h>

static const CGFloat LauncherMenuIconSize = 34.0;
static const CGFloat LauncherAccountCompactSize = 34.0;
static const CGFloat LauncherAccountExpandedMaxWidth = 220.0;

@implementation LauncherMenuCustomItem

+ (LauncherMenuCustomItem *)title:(NSString *)title imageName:(NSString *)imageName action:(id)action {
    LauncherMenuCustomItem *item = [[LauncherMenuCustomItem alloc] init];
    item.title = title;
    item.imageName = imageName;
    item.action = action;
    return item;
}

+ (LauncherMenuCustomItem *)vcClass:(Class)class {
    id vc = [class new];
    LauncherMenuCustomItem *item = [[LauncherMenuCustomItem alloc] init];
    item.title = [vc title];
    item.imageName = [vc imageName];
    // View controllers are put into an array to keep its state
    item.vcArray = @[vc];
    return item;
}

@end

@interface LauncherMenuViewController()
@property(nonatomic) NSMutableArray<LauncherMenuCustomItem*> *options;
@property(nonatomic) UIView *heroCard;
@property(nonatomic) UIImageView *heroLogoView;
@property(nonatomic) UILabel *heroTitleLabel;
@property(nonatomic) UILabel *statusLabel;
@property(nonatomic) UIView *statusCard;
@property(nonatomic) UILabel *statusCaptionLabel;
@property(nonatomic) UILabel *heroSubtitleLabel;
@property(nonatomic) CGFloat lastSidebarLayoutWidth;
@property(nonatomic) NSString *lastAccountRenderSignature;
@property(nonatomic) int lastSelectedIndex;
@end

@implementation LauncherMenuViewController

#define contentNavigationController ((LauncherNavigationController *)self.splitViewController.viewControllers[1])

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    return self;
}

- (void)configureSidebarHeader {
    UIView *wrapper = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.tableView.bounds), 1.0)];
    self.heroCard = [[UIView alloc] initWithFrame:CGRectZero];
    LauncherStylePanel(self.heroCard, 24.0);

    self.heroLogoView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"AppLogo"]];
    self.heroLogoView.contentMode = UIViewContentModeScaleAspectFit;

    self.heroTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.heroTitleLabel.text = @"Angel Aura Amethyst";
    self.heroTitleLabel.font = LauncherTitleFont(22.0);
    self.heroTitleLabel.textColor = UIColor.labelColor;
    self.heroTitleLabel.numberOfLines = 2;

    self.heroSubtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.heroSubtitleLabel.font = LauncherBodyFont(13.0);
    self.heroSubtitleLabel.textColor = UIColor.secondaryLabelColor;
    self.heroSubtitleLabel.numberOfLines = 0;

    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0";
    NSString *build = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"";
    self.heroSubtitleLabel.text = [NSString stringWithFormat:@"%@ (%@)\n%@", version, build, UIDevice.currentDevice.completeOSVersion];

    [wrapper addSubview:self.heroCard];
    [self.heroCard addSubview:self.heroLogoView];
    [self.heroCard addSubview:self.heroTitleLabel];
    [self.heroCard addSubview:self.heroSubtitleLabel];
    self.tableView.tableHeaderView = wrapper;
}

- (void)configureSidebarFooter {
    UIView *wrapper = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.tableView.bounds), 1.0)];
    self.statusCard = [[UIView alloc] initWithFrame:CGRectZero];
    LauncherStylePanel(self.statusCard, 18.0);

    self.statusCaptionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusCaptionLabel.text = @"JIT";
    self.statusCaptionLabel.font = LauncherCaptionFont(12.0);
    self.statusCaptionLabel.textColor = UIColor.secondaryLabelColor;

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusLabel.font = LauncherTitleFont(15.0);
    self.statusLabel.textColor = UIColor.labelColor;
    self.statusLabel.text = isJITEnabled(false) ? localize(@"login.jit.enabled", nil) : localize(@"login.jit.checking", nil);
    self.statusLabel.numberOfLines = 0;

    [wrapper addSubview:self.statusCard];
    [self.statusCard addSubview:self.statusCaptionLabel];
    [self.statusCard addSubview:self.statusLabel];
    self.tableView.tableFooterView = wrapper;
}

- (void)layoutSidebarHeaderForWidth:(CGFloat)width {
    UIView *headerWrapper = self.tableView.tableHeaderView;
    if (!headerWrapper || width <= 0.0) {
        return;
    }

    CGFloat cardWidth = MAX(width - 32.0, 0.0);
    CGFloat textX = 108.0;
    CGFloat textWidth = MAX(cardWidth - textX - 20.0, 80.0);
    CGFloat titleHeight = ceil([self.heroTitleLabel sizeThatFits:CGSizeMake(textWidth, CGFLOAT_MAX)].height);
    CGFloat subtitleHeight = ceil([self.heroSubtitleLabel sizeThatFits:CGSizeMake(textWidth, CGFLOAT_MAX)].height);
    CGFloat textHeight = titleHeight + 6.0 + subtitleHeight;
    CGFloat cardHeight = MAX(MAX(72.0, textHeight) + 40.0, 128.0);
    CGFloat textY = (cardHeight - textHeight) / 2.0;
    CGFloat wrapperHeight = cardHeight + 16.0;
    BOOL needsReapply = fabs(CGRectGetWidth(headerWrapper.frame) - width) > 0.5 || fabs(CGRectGetHeight(headerWrapper.frame) - wrapperHeight) > 0.5;

    headerWrapper.frame = CGRectMake(0, 0, width, wrapperHeight);
    self.heroCard.frame = CGRectMake(16.0, 8.0, cardWidth, cardHeight);
    self.heroLogoView.frame = CGRectMake(20.0, (cardHeight - 72.0) / 2.0, 72.0, 72.0);
    self.heroTitleLabel.frame = CGRectMake(textX, textY, textWidth, titleHeight);
    self.heroSubtitleLabel.frame = CGRectMake(textX, CGRectGetMaxY(self.heroTitleLabel.frame) + 6.0, textWidth, subtitleHeight);

    if (needsReapply) {
        self.tableView.tableHeaderView = headerWrapper;
    }
}

- (void)layoutSidebarFooterForWidth:(CGFloat)width {
    UIView *footerWrapper = self.tableView.tableFooterView;
    if (!footerWrapper || width <= 0.0) {
        return;
    }

    CGFloat cardWidth = MAX(width - 32.0, 0.0);
    CGFloat labelWidth = MAX(cardWidth - 36.0, 80.0);
    CGFloat captionHeight = ceil([self.statusCaptionLabel sizeThatFits:CGSizeMake(labelWidth, CGFLOAT_MAX)].height);
    CGFloat statusHeight = ceil([self.statusLabel sizeThatFits:CGSizeMake(labelWidth, CGFLOAT_MAX)].height);
    CGFloat cardHeight = MAX(12.0 + captionHeight + 4.0 + statusHeight + 12.0, 58.0);
    CGFloat wrapperHeight = cardHeight + 16.0;
    BOOL needsReapply = fabs(CGRectGetWidth(footerWrapper.frame) - width) > 0.5 || fabs(CGRectGetHeight(footerWrapper.frame) - wrapperHeight) > 0.5;

    footerWrapper.frame = CGRectMake(0, 0, width, wrapperHeight);
    self.statusCard.frame = CGRectMake(16.0, 8.0, cardWidth, cardHeight);
    self.statusCaptionLabel.frame = CGRectMake(18.0, 12.0, labelWidth, captionHeight);
    self.statusLabel.frame = CGRectMake(18.0, CGRectGetMaxY(self.statusCaptionLabel.frame) + 4.0, labelWidth, statusHeight);

    if (needsReapply) {
        self.tableView.tableFooterView = footerWrapper;
    }
}

- (void)updateSidebarChromeLayout {
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    [self layoutSidebarHeaderForWidth:width];
    [self layoutSidebarFooterForWidth:width];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.isInitialVc = YES;
    
    UIImageView *titleView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"AppLogo"]];
    [titleView setContentMode:UIViewContentModeScaleAspectFit];
    titleView.frame = CGRectMake(0, 0, 124, 30);
    self.navigationItem.titleView = titleView;
    
    self.options = @[
        [LauncherMenuCustomItem vcClass:LauncherNewsViewController.class],
        [LauncherMenuCustomItem vcClass:LauncherProfilesViewController.class],
        [LauncherMenuCustomItem vcClass:LauncherPreferencesViewController.class],
    ].mutableCopy;
    if (realUIIdiom != UIUserInterfaceIdiomTV) {
        [self.options addObject:(id)[LauncherMenuCustomItem
                                     title:localize(@"launcher.menu.custom_controls", nil)
                                     imageName:@"MenuCustomControls" action:^{
            [contentNavigationController performSelector:@selector(enterCustomControls)];
        }]];
    }
    [self.options addObject:
     (id)[LauncherMenuCustomItem
          title:localize(@"launcher.menu.execute_jar", nil)
          imageName:@"MenuInstallJar" action:^{
        [contentNavigationController performSelector:@selector(enterModInstaller)];
    }]];
    
    // TODO: Finish log-uploading service integration
    [self.options addObject:
     (id)[LauncherMenuCustomItem
          title:localize(@"login.menu.sendlogs", nil)
          imageName:@"square.and.arrow.up" action:^{
        NSString *latestlogPath = [NSString stringWithFormat:@"file://%s/latestlog.old.txt", getenv("POJAV_HOME")];
        NSLog(@"Path is %@", latestlogPath);
        UIActivityViewController *activityVC;
        if (realUIIdiom != UIUserInterfaceIdiomTV) {
            activityVC = [[UIActivityViewController alloc]
                          initWithActivityItems:@[[NSURL URLWithString:latestlogPath]]
                          applicationActivities:nil];
        } else {
            dlopen("/System/Library/PrivateFrameworks/SharingUI.framework/SharingUI", RTLD_GLOBAL);
            activityVC =
            [[NSClassFromString(@"SFAirDropSharingViewControllerTV") alloc]
             performSelector:@selector(initWithSharingItems:)
             withObject:@[[NSURL URLWithString:latestlogPath]]];
        }
        activityVC.popoverPresentationController.sourceView = titleView;
        activityVC.popoverPresentationController.sourceRect = titleView.bounds;
        [self presentViewController:activityVC animated:YES completion:nil];
    }]];
    
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"MM-dd";
    NSString* date = [dateFormatter stringFromDate:NSDate.date];
    if([date isEqualToString:@"06-29"] || [date isEqualToString:@"06-30"] || [date isEqualToString:@"07-01"]) {
        [self.options addObject:(id)[LauncherMenuCustomItem
                                     title:@"Technoblade never dies!"
                                     imageName:@"" action:^{
            openLink(self, [NSURL URLWithString:@"https://youtu.be/DPMluEVUqS0"]);
        }]];
    }
    
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView.backgroundColor = self.view.backgroundColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = 54.0;
    self.tableView.sectionFooterHeight = 14.0;
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 12.0;
    }
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 20.0, 0);
    [self configureSidebarHeader];
    [self configureSidebarFooter];
    
    self.navigationController.toolbarHidden = NO;
    UIActivityIndicatorViewStyle indicatorStyle = UIActivityIndicatorViewStyleMedium;
    UIActivityIndicatorView *toolbarIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:indicatorStyle];
    [toolbarIndicator startAnimating];
    self.toolbarItems = @[
        [[UIBarButtonItem alloc] initWithCustomView:toolbarIndicator],
        [[UIBarButtonItem alloc] init]
    ];
    self.toolbarItems[1].tintColor = UIColor.labelColor;
    
    // Setup the account button
    self.accountBtnItem = [self drawAccountButton];
    
    [self updateAccountInfo];
    
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:1 inSection:0];
    [self.tableView selectRowAtIndexPath:indexPath animated:YES scrollPosition:UITableViewScrollPositionNone];
    [self tableView:self.tableView didSelectRowAtIndexPath:indexPath];
    self.lastSelectedIndex = 1;
    
    if (getEntitlementValue(@"get-task-allow")) {
        [self displayProgress:localize(@"login.jit.checking", nil)];
        if (isJITEnabled(false)) {
            [self displayProgress:localize(@"login.jit.enabled", nil)];
            [self displayProgress:nil];
        } else if (@available(iOS 17.0, *)) {
            // enabling JIT for 17.0+ is done when we actually launch the game
        } else {
            [self enableJITWithAltKit];
        }
    } else if (!NSProcessInfo.processInfo.macCatalystApp && !getenv("SIMULATOR_DEVICE_NAME")) {
        [self displayProgress:localize(@"login.jit.fail", nil)];
        [self displayProgress:nil];
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:localize(@"login.jit.fail.title", nil)
            message:localize(@"login.jit.fail.description_unsupported", nil)
            preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* okAction = [UIAlertAction actionWithTitle:localize(@"OK", nil) style:UIAlertActionStyleDefault handler:^(id action){
            exit(-1);
        }];
        [alert addAction:okAction];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self restoreHighlightedSelection];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (fabs(self.lastSidebarLayoutWidth - width) > 0.5) {
        self.lastSidebarLayoutWidth = width;
        [self updateSidebarChromeLayout];
        [self updateAccountInfo];
    }
}

- (UIBarButtonItem *)drawAccountButton {
    if (!self.accountBtnItem) {
        self.accountButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [self.accountButton addTarget:self action:@selector(selectAccount:) forControlEvents:UIControlEventPrimaryActionTriggered];
        self.accountButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        self.accountButton.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
        self.accountButton.contentEdgeInsets = UIEdgeInsetsMake(2, 0, 2, 6);
        self.accountButton.titleEdgeInsets = UIEdgeInsetsMake(0, 8, 0, -8);
        self.accountButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
        self.accountButton.imageView.clipsToBounds = YES;
        self.accountButton.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
        self.accountButton.titleLabel.numberOfLines = 2;
        self.accountButton.titleLabel.adjustsFontSizeToFitWidth = YES;
        self.accountButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        self.accountButton.tintColor = UIColor.labelColor;
        self.accountButton.frame = CGRectMake(0, 0, LauncherAccountCompactSize, LauncherAccountCompactSize);
        self.accountBtnItem = [[UIBarButtonItem alloc] initWithCustomView:self.accountButton];
    }

    [self updateAccountInfo];
    
    return self.accountBtnItem;
}

- (void)restoreHighlightedSelection {
    // Restore the selected row when the view appears again
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:self.lastSelectedIndex inSection:0];
    [self.tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.options.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"cell"];
    }

    cell.textLabel.text = [self.options[indexPath.row] title];
    cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    cell.textLabel.adjustsFontSizeToFitWidth = YES;
    cell.textLabel.minimumScaleFactor = 0.85;
    cell.accessoryType = self.options[indexPath.row].action ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
    UIView *selectedBackgroundView = [[UIView alloc] initWithFrame:CGRectZero];
    selectedBackgroundView.backgroundColor = LauncherPanelMutedColor();
    cell.selectedBackgroundView = selectedBackgroundView;
    
    UIImage *origImage = [UIImage systemImageNamed:[self.options[indexPath.row]
        performSelector:@selector(imageName)]];
    if (origImage) {
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(LauncherMenuIconSize, LauncherMenuIconSize)];
        UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext*_Nonnull myContext) {
            CGFloat scaleFactor = LauncherMenuIconSize / origImage.size.height;
            CGFloat originX = (LauncherMenuIconSize - origImage.size.width * scaleFactor) / 2.0;
            [origImage drawInRect:CGRectMake(originX, 0, origImage.size.width * scaleFactor, LauncherMenuIconSize)];
        }];
        cell.imageView.image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    
    if (cell.imageView.image == nil) {
        cell.imageView.layer.magnificationFilter = kCAFilterNearest;
        cell.imageView.layer.minificationFilter = kCAFilterNearest;
        cell.imageView.image = [UIImage imageNamed:[self.options[indexPath.row]
            performSelector:@selector(imageName)]];
        cell.imageView.image = [cell.imageView.image _imageWithSize:CGSizeMake(LauncherMenuIconSize, LauncherMenuIconSize)];
    }
    cell.imageView.preferredSymbolConfiguration = LauncherSymbolConfig(18.0);
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    LauncherMenuCustomItem *selected = self.options[indexPath.row];
    
    if (selected.action != nil) {
        [self restoreHighlightedSelection];
        ((LauncherMenuCustomItem *)selected).action();
    } else {
        BOOL shouldShowDetail = !self.isInitialVc;
        if(self.isInitialVc) {
            self.isInitialVc = NO;
        } else {
            self.options[self.lastSelectedIndex].vcArray = contentNavigationController.viewControllers;
            [contentNavigationController setViewControllers:selected.vcArray animated:NO];
            self.lastSelectedIndex = indexPath.row;
        }
        selected.vcArray[0].navigationItem.rightBarButtonItem = self.accountBtnItem;
        selected.vcArray[0].navigationItem.leftBarButtonItem = self.splitViewController.displayModeButtonItem;
        selected.vcArray[0].navigationItem.leftItemsSupplementBackButton = true;
        if (shouldShowDetail) {
            [self.splitViewController showDetailViewController:contentNavigationController sender:self];
        }
    }
}

- (void)selectAccount:(UIButton *)sender {
    AccountListViewController *vc = [[AccountListViewController alloc] init];
    vc.whenDelete = ^void(NSString* name) {
        if ([name isEqualToString:getPrefObject(@"internal.selected_account")]) {
            BaseAuthenticator.current = nil;
            setPrefObject(@"internal.selected_account", @"");
            [self updateAccountInfo];
        }
    };
    vc.whenItemSelected = ^void() {
        setPrefObject(@"internal.selected_account", BaseAuthenticator.current.authData[@"username"]);
        [self updateAccountInfo];
        if (sender != self.accountButton) {
            // Called from the play button, so call back to continue
            [sender sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
        }
    };
    vc.modalPresentationStyle = UIModalPresentationPopover;
    vc.preferredContentSize = CGSizeMake(350, 250);

    UIPopoverPresentationController *popoverController = vc.popoverPresentationController;
    popoverController.sourceView = sender;
    popoverController.sourceRect = sender.bounds;
    popoverController.permittedArrowDirections = UIPopoverArrowDirectionAny;
    popoverController.delegate = vc;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)updateAccountInfo {
    NSDictionary *selected = BaseAuthenticator.current.authData;
    CGSize size = CGSizeMake(contentNavigationController.view.frame.size.width, contentNavigationController.view.frame.size.height);
    BOOL shouldShowTitle = size.width >= 620.0;
    CGFloat avatarSize = size.width >= 900.0 ? 38.0 : LauncherAccountCompactSize;
    NSString *accountName = selected[@"username"] ?: @"";
    NSString *profilePicURL = selected[@"profilePicURL"] ?: @"";
    NSString *gamerTag = selected[@"xboxGamertag"] ?: @"";
    NSString *renderSignature = [NSString stringWithFormat:@"%@|%@|%@|%@|%d|%.1f",
        accountName,
        profilePicURL,
        gamerTag,
        selected ? @"selected" : @"empty",
        shouldShowTitle,
        avatarSize];
    if ([self.lastAccountRenderSignature isEqualToString:renderSignature]) {
        return;
    }
    self.lastAccountRenderSignature = renderSignature;

    self.accountButton.contentEdgeInsets = UIEdgeInsetsMake(2, 0, 2, shouldShowTitle ? 6 : 0);
    self.accountButton.titleEdgeInsets = shouldShowTitle ? UIEdgeInsetsMake(0, 8, 0, -8) : UIEdgeInsetsZero;
    
    if (selected == nil) {
        if (shouldShowTitle) {
            [self.accountButton setAttributedTitle:[[NSAttributedString alloc] initWithString:localize(@"login.option.select", nil)] forState:UIControlStateNormal];
        } else {
            [self.accountButton setAttributedTitle:(NSAttributedString *)@"" forState:UIControlStateNormal];
        }
        [self.accountButton setImage:[UIImage imageNamed:@"DefaultAccount"] forState:UIControlStateNormal];
        self.accountButton.frame = CGRectMake(0, 0, shouldShowTitle ? 148.0 : avatarSize, MAX(36.0, avatarSize));
        self.accountButton.imageView.layer.cornerRadius = avatarSize / 5.0;
        return;
    }

    // Remove the prefix "Demo." if there is
    BOOL isDemo = [selected[@"username"] hasPrefix:@"Demo."];
    NSMutableAttributedString *title = [[NSMutableAttributedString alloc] initWithString:[selected[@"username"] substringFromIndex:(isDemo?5:0)]];

    // Check if we're switching between demo and full mode
    BOOL shouldUpdateProfiles = (getenv("DEMO_LOCK")!=NULL) != isDemo;

    // Reset states
    unsetenv("DEMO_LOCK");
    setenv("POJAV_GAME_DIR", [NSString stringWithFormat:@"%s/Library/Application Support/minecraft", getenv("POJAV_HOME")].UTF8String, 1);

    id subtitle;
    if (isDemo) {
        subtitle = localize(@"login.option.demo", nil);
        setenv("DEMO_LOCK", "1", 1);
        setenv("POJAV_GAME_DIR", [NSString stringWithFormat:@"%s/.demo", getenv("POJAV_HOME")].UTF8String, 1);
    } else if (selected[@"xboxGamertag"] == nil) {
        subtitle = localize(@"login.option.local", nil);
    } else {
        // Display the Xbox gamertag for online accounts
        subtitle = selected[@"xboxGamertag"];
    }

    subtitle = [[NSAttributedString alloc] initWithString:subtitle attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12]}];
    [title appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:nil]];
    [title appendAttributedString:subtitle];
    
    if (shouldShowTitle) {
        [self.accountButton setAttributedTitle:title forState:UIControlStateNormal];
    } else {
        [self.accountButton setAttributedTitle:(NSAttributedString *)@"" forState:UIControlStateNormal];
    }
    
    // TODO: Add caching mechanism for profile pictures
    NSURL *url = [NSURL URLWithString:[selected[@"profilePicURL"] stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"]];
    UIImage *placeholder = [UIImage imageNamed:@"DefaultAccount"];
    [self.accountButton setImageForState:UIControlStateNormal withURL:url placeholderImage:placeholder];
    [self.accountButton.imageView setImageWithURL:url placeholderImage:placeholder];
    [self.accountButton sizeToFit];
    CGFloat buttonWidth = shouldShowTitle ? MIN(MAX(self.accountButton.bounds.size.width, avatarSize + 84.0), LauncherAccountExpandedMaxWidth) : avatarSize;
    self.accountButton.frame = CGRectMake(0, 0, buttonWidth, MAX(36.0, avatarSize));
    self.accountButton.imageView.layer.cornerRadius = avatarSize / 5.0;

    // Update profiles and local version list if needed
    if (shouldUpdateProfiles) {
        [contentNavigationController fetchLocalVersionList];
        [contentNavigationController performSelector:@selector(reloadProfileList)];
    }
}

- (void)displayProgress:(NSString *)status {
    if (status == nil) {
        [(UIActivityIndicatorView *)self.toolbarItems[0].customView stopAnimating];
    } else {
        self.toolbarItems[1].title = status;
        self.statusLabel.text = status;
        [self updateSidebarChromeLayout];
    }
}

- (void)enableJITWithAltKit {
    [ALTServerManager.sharedManager startDiscovering];
    [ALTServerManager.sharedManager autoconnectWithCompletionHandler:^(ALTServerConnection *connection, NSError *error) {
        if (error) {
            NSLog(@"[AltKit] Could not auto-connect to server. %@", error.localizedRecoverySuggestion);
            [self displayProgress:localize(@"login.jit.fail", nil)];
            [self displayProgress:nil];
        }
        [connection enableUnsignedCodeExecutionWithCompletionHandler:^(BOOL success, NSError *error) {
            if (success) {
                NSLog(@"[AltKit] Successfully enabled JIT compilation!");
                [ALTServerManager.sharedManager stopDiscovering];
                [self displayProgress:localize(@"login.jit.enabled", nil)];
                [self displayProgress:nil];
            } else {
                NSLog(@"[AltKit] Error enabling JIT: %@", error.localizedRecoverySuggestion);
                [self displayProgress:localize(@"login.jit.fail", nil)];
                [self displayProgress:nil];
            }
            [connection disconnect];
        }];
    }];
}

@end
