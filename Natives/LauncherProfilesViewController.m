#import "LauncherMenuViewController.h"
#import "LauncherNavigationController.h"
#import "LauncherPreferences.h"
#import "LauncherPrefGameDirViewController.h"
#import "LauncherPrefManageJREViewController.h"
#import "LauncherProfileEditorViewController.h"
#import "LauncherProfilesViewController.h"
#import "LauncherUIStyle.h"
//#import "NSFileManager+NRFileManager.h"
#import "PLProfiles.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
#import "UIKit+AFNetworking.h"
#pragma clang diagnostic pop
#import "UIKit+hook.h"
#import "installer/FabricInstallViewController.h"
#import "installer/ForgeInstallViewController.h"
#import "installer/ModpackInstallViewController.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

typedef NS_ENUM(NSUInteger, LauncherProfilesTableSection) {
    kInstances,
    kProfiles
};

static const CGFloat LauncherProfileIconSize = 34.0;

@interface LauncherProfilesViewController () //<UIContextMenuInteractionDelegate>

@property(nonatomic) UIBarButtonItem *createButtonItem;
@property(nonatomic) UIView *summaryCard;
@property(nonatomic) UIImageView *summaryImageView;
@property(nonatomic) UILabel *summaryTitleLabel;
@property(nonatomic) UILabel *summarySubtitleLabel;
@property(nonatomic) UILabel *summaryMetaLabel;
@property(nonatomic) CGFloat lastSummaryLayoutWidth;
@end

@implementation LauncherProfilesViewController

- (id)init {
    self = [super init];
    self.title = localize(@"Profiles", nil);
    return self;
}

- (NSString *)imageName {
    return @"MenuProfiles";
}

- (void)configureSummaryHeader {
    UIView *wrapper = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.tableView.bounds), 144.0)];
    self.summaryCard = [[UIView alloc] initWithFrame:CGRectMake(16.0, 8.0, wrapper.bounds.size.width - 32.0, 124.0)];
    LauncherStylePanel(self.summaryCard, 24.0);

    self.summaryImageView = [[UIImageView alloc] initWithFrame:CGRectMake(20.0, 22.0, 64.0, 64.0)];
    self.summaryImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.summaryImageView.layer.cornerRadius = 16.0;
    self.summaryImageView.clipsToBounds = YES;
    self.summaryImageView.layer.magnificationFilter = kCAFilterNearest;
    self.summaryImageView.layer.minificationFilter = kCAFilterNearest;

    UILabel *eyebrowLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    eyebrowLabel.text = localize(@"Profiles", nil);
    eyebrowLabel.font = LauncherCaptionFont(12.0);
    eyebrowLabel.textColor = UIColor.secondaryLabelColor;
    eyebrowLabel.tag = 101;

    self.summaryTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.summaryTitleLabel.font = LauncherTitleFont(22.0);
    self.summaryTitleLabel.textColor = UIColor.labelColor;
    self.summaryTitleLabel.numberOfLines = 2;

    self.summarySubtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.summarySubtitleLabel.font = LauncherBodyFont(13.0);
    self.summarySubtitleLabel.textColor = UIColor.secondaryLabelColor;
    self.summarySubtitleLabel.numberOfLines = 2;

    self.summaryMetaLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.summaryMetaLabel.font = LauncherCaptionFont(12.0);
    self.summaryMetaLabel.textColor = UIColor.secondaryLabelColor;

    [self.summaryCard addSubview:self.summaryImageView];
    [self.summaryCard addSubview:eyebrowLabel];
    [self.summaryCard addSubview:self.summaryTitleLabel];
    [self.summaryCard addSubview:self.summarySubtitleLabel];
    [self.summaryCard addSubview:self.summaryMetaLabel];
    [wrapper addSubview:self.summaryCard];
    self.tableView.tableHeaderView = wrapper;
}

- (void)updateSummaryHeader {
    NSMutableDictionary *selectedProfile = PLProfiles.current.selectedProfile;
    NSString *profileName = selectedProfile[@"name"] ?: PLProfiles.current.selectedProfileName ?: @"(Default)";
    NSString *versionId = selectedProfile[@"lastVersionId"] ?: @"latest-release";
    NSString *gameDir = getPrefObject(@"general.game_directory") ?: @"default";
    self.summaryTitleLabel.text = profileName;
    self.summarySubtitleLabel.text = [NSString stringWithFormat:@"%@\n%@", versionId, gameDir];
    self.summaryMetaLabel.text = [NSString stringWithFormat:@"%@ - %lu", localize(@"Profiles", nil), (unsigned long)PLProfiles.current.profiles.count];

    UIImage *fallbackImage = [[UIImage imageNamed:@"DefaultProfile"] _imageWithSize:CGSizeMake(64, 64)];
    NSString *iconURL = selectedProfile[@"icon"];
    [self.summaryImageView setImageWithURL:[NSURL URLWithString:iconURL] placeholderImage:fallbackImage];
}

- (void)updateSummaryHeaderLayout {
    UIView *wrapper = self.tableView.tableHeaderView;
    if (!wrapper) {
        return;
    }

    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    BOOL needsHeaderReapply = fabs(CGRectGetWidth(wrapper.frame) - width) > 0.5;
    wrapper.frame = CGRectMake(0, 0, width, 144.0);
    self.summaryCard.frame = CGRectMake(16.0, 8.0, width - 32.0, 124.0);
    self.summaryImageView.frame = CGRectMake(20.0, 22.0, 64.0, 64.0);
    CGFloat textX = 102.0;
    CGFloat textWidth = self.summaryCard.bounds.size.width - textX - 20.0;
    [self.summaryCard viewWithTag:101].frame = CGRectMake(textX, 18.0, textWidth, 16.0);
    self.summaryTitleLabel.frame = CGRectMake(textX, 36.0, textWidth, 30.0);
    self.summarySubtitleLabel.frame = CGRectMake(textX, 66.0, textWidth, 34.0);
    self.summaryMetaLabel.frame = CGRectMake(textX, 100.0, textWidth, 16.0);
    if (needsHeaderReapply) {
        self.tableView.tableHeaderView = wrapper;
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    UIMenu *createMenu = [UIMenu menuWithTitle:localize(@"profile.title.create", nil) image:nil identifier:nil
    options:UIMenuOptionsDisplayInline
    children:@[
        [UIAction
            actionWithTitle:@"Vanilla" image:nil
            identifier:@"vanilla" handler:^(UIAction *action) {
                [self actionEditProfile:@{
                    @"name": @"",
                    @"lastVersionId": @"latest-release"}];
            }],
#if 0 // TODO
        [UIAction
            actionWithTitle:@"OptiFine" image:nil
            identifier:@"optifine" handler:createHandler],
#endif
        [UIAction
            actionWithTitle:@"Fabric/Quilt" image:nil
            identifier:@"fabric_or_quilt" handler:^(UIAction *action) {
                [self actionCreateFabricProfile];
            }],
        [UIAction
            actionWithTitle:@"Forge" image:nil
            identifier:@"forge" handler:^(UIAction *action) {
                [self actionCreateForgeProfile];
            }],
        [UIAction
            actionWithTitle:@"Modpack" image:nil
            identifier:@"modpack" handler:^(UIAction *action) {
                [self actionCreateModpackProfile];
            }]
    ]];
    self.createButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd menu:createMenu];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.rowHeight = 60.0;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 8.0;
    }
    [self configureSummaryHeader];
    [self updateSummaryHeader];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // Put navigation buttons back in place
    self.navigationItem.rightBarButtonItems = @[[sidebarViewController drawAccountButton], self.createButtonItem];

    // Pickup changes made in the profile editor and switching instance
    [PLProfiles updateCurrent];
    [self.tableView reloadData];
    [self.navigationController performSelector:@selector(reloadProfileList)];
    [self updateSummaryHeader];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (fabs(self.lastSummaryLayoutWidth - width) > 0.5) {
        self.lastSummaryLayoutWidth = width;
        [self updateSummaryHeaderLayout];
    }
}

- (void)actionTogglePrefIsolation:(UISwitch *)sender {
    if (!sender.isOn) {
        setPrefBool(@"internal.isolated", NO);
    }
    toggleIsolatedPref(sender.isOn);
}

- (void)actionCreateFabricProfile {
    FabricInstallViewController *vc = [FabricInstallViewController new];
    [self presentNavigatedViewController:vc];
}

- (void)actionCreateForgeProfile {
    ForgeInstallViewController *vc = [ForgeInstallViewController new];
    [self presentNavigatedViewController:vc];
}

- (void)actionCreateModpackProfile {
    ModpackInstallViewController *vc = [ModpackInstallViewController new];
    [self presentNavigatedViewController:vc];
}

- (void)actionEditProfile:(NSDictionary *)profile {
    LauncherProfileEditorViewController *vc = [LauncherProfileEditorViewController new];
    vc.profile = profile.mutableCopy;
    [self presentNavigatedViewController:vc];
}

- (void)presentNavigatedViewController:(UIViewController *)vc {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    //nav.navigationBar.prefersLargeTitles = YES;
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return localize(@"profile.section.instance", nil);
        case 1: return localize(@"profile.section.profiles", nil);
    }
    return nil;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = [self tableView:tableView titleForHeaderInSection:section].uppercaseString;
    label.font = LauncherCaptionFont(12.0);
    label.textColor = UIColor.secondaryLabelColor;

    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    [view addSubview:label];
    label.frame = CGRectMake(22.0, 10.0, tableView.bounds.size.width - 44.0, 16.0);
    return view;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 32.0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 2;
        case 1: return [PLProfiles.current.profiles count];
    }
    return 0;
}

- (void)setupInstanceCell:(UITableViewCell *) cell atRow:(NSInteger)row {
    cell.userInteractionEnabled = !getenv("DEMO_LOCK");
    cell.textLabel.font = LauncherTitleFont(15.5);
    cell.detailTextLabel.font = LauncherBodyFont(12.5);
    if (row == 0) {
        cell.imageView.image = [UIImage systemImageNamed:@"folder"];
        cell.textLabel.text = localize(@"preference.title.game_directory", nil);
        cell.detailTextLabel.text = getenv("DEMO_LOCK") ? @".demo" : getPrefObject(@"general.game_directory");
    } else {
        NSString *imageName;
        if (@available(iOS 15.0, *)) {
            imageName = @"folder.badge.gearshape";
        } else {
            imageName = @"folder.badge.gear";
        }
        cell.imageView.image = [UIImage systemImageNamed:imageName];
        cell.textLabel.text = localize(@"profile.title.separate_preference", nil);
        cell.detailTextLabel.text = localize(@"profile.detail.separate_preference", nil);
        UISwitch *view = [UISwitch new];
        [view setOn:getPrefBool(@"internal.isolated") animated:NO];
        [view addTarget:self action:@selector(actionTogglePrefIsolation:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = view;
    }
}

- (void)setupProfileCell:(UITableViewCell *) cell atRow:(NSInteger)row {
    NSMutableDictionary *profile = PLProfiles.current.profiles.allValues[row];

    cell.textLabel.text = profile[@"name"];
    cell.detailTextLabel.text = profile[@"lastVersionId"];
    cell.textLabel.font = LauncherTitleFont(16.0);
    cell.detailTextLabel.font = LauncherBodyFont(12.5);
    cell.imageView.layer.magnificationFilter = kCAFilterNearest;

    UIImage *fallbackImage = [[UIImage imageNamed:@"DefaultProfile"] _imageWithSize:CGSizeMake(LauncherProfileIconSize, LauncherProfileIconSize)];
    [cell.imageView setImageWithURL:[NSURL URLWithString:profile[@"icon"]] placeholderImage:fallbackImage];
    cell.imageView.layer.cornerRadius = 8.0;
    cell.imageView.clipsToBounds = YES;
    cell.accessoryType = [profile[@"name"] isEqualToString:PLProfiles.current.selectedProfileName] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryDisclosureIndicator;
}

- (UITableViewCell *)tableView:(nonnull UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *cellID = indexPath.section == kInstances ? @"InstanceCell" : @"ProfileCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
        if (indexPath.section == kProfiles) {
            cell.imageView.frame = CGRectMake(0, 0, LauncherProfileIconSize, LauncherProfileIconSize);
            cell.imageView.isSizeFixed = YES;
        }
    } else {
        cell.imageView.image = nil;
        cell.userInteractionEnabled = YES;
        cell.accessoryView = nil;
    }

    if (indexPath.section == kInstances) {
        [self setupInstanceCell:cell atRow:indexPath.row];
    } else {
        [self setupProfileCell:cell atRow:indexPath.row];
    }

    cell.textLabel.enabled = cell.detailTextLabel.enabled = cell.userInteractionEnabled;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];

    if (indexPath.section == kInstances) {
        if (indexPath.row == 0) {
            [self.navigationController pushViewController:[LauncherPrefGameDirViewController new] animated:YES];
        }
        return;
    }

    [self actionEditProfile:PLProfiles.current.profiles.allValues[indexPath.row]];
}

#pragma mark Context Menu configuration

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle != UITableViewCellEditingStyleDelete) return;

    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    NSString *title = localize(@"preference.title.confirm", nil);
    // reusing the delete runtime message
    NSString *message = [NSString stringWithFormat:localize(@"preference.title.confirm.delete_runtime", nil), cell.textLabel.text];
    UIAlertController *confirmAlert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleActionSheet];
    confirmAlert.popoverPresentationController.sourceView = cell;
    confirmAlert.popoverPresentationController.sourceRect = cell.bounds;
    UIAlertAction *ok = [UIAlertAction actionWithTitle:localize(@"OK", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [PLProfiles.current.profiles removeObjectForKey:cell.textLabel.text];
        if ([PLProfiles.current.selectedProfileName isEqualToString:cell.textLabel.text]) {
            // The one being deleted is the selected one, switch to the random one now
            PLProfiles.current.selectedProfileName = PLProfiles.current.profiles.allKeys[0];
            [self.navigationController performSelector:@selector(reloadProfileList)];
        } else {
            [PLProfiles.current save];
        }
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil];
    [confirmAlert addAction:cancel];
    [confirmAlert addAction:ok];
    [self presentViewController:confirmAlert animated:YES completion:nil];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == kInstances || PLProfiles.current.profiles.count==1) {
        return UITableViewCellEditingStyleNone;
    }
    return UITableViewCellEditingStyleDelete;
}

@end
