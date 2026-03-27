#import "LauncherMenuViewController.h"
#import "LauncherNavigationController.h"
#import "LauncherPreferences.h"
#import "LauncherPrefGameDirViewController.h"
#import "LauncherPrefManageJREViewController.h"
#import "LauncherProfileEditorViewController.h"
#import "LauncherProfilesViewController.h"
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

@interface LauncherProfilesViewController () //<UIContextMenuInteractionDelegate>

@property(nonatomic) UIBarButtonItem *createButtonItem;
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
    self.view.backgroundColor = UIColor.clearColor;
    self.tableView.backgroundColor = UIColor.clearColor;
    PLApplyCompactTableLayout(self.tableView, 42);
    [self applyLauncherAppearance];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleLauncherAppearanceDidChange:)
        name:PLLauncherAppearanceDidChangeNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyLauncherAppearance];

    // Put navigation buttons back in place
    self.navigationItem.rightBarButtonItems = @[[sidebarViewController drawAccountButton], self.createButtonItem];

    // Pickup changes made in the profile editor and switching instance
    [PLProfiles updateCurrent];
    [self.tableView reloadData];
    [self.navigationController performSelector:@selector(reloadProfileList)];
}

- (void)applyLauncherAppearance {
    self.tableView.separatorStyle = getLauncherOutlineControlsEnabled() ?
        UITableViewCellSeparatorStyleNone :
        UITableViewCellSeparatorStyleSingleLine;
}

- (void)handleLauncherAppearanceDidChange:(NSNotification *)notification {
    [self applyLauncherAppearance];
    [self.tableView reloadData];
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
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    if ([vc isKindOfClass:LauncherProfileEditorViewController.class]) {
        nav.preferredContentSize = PLCompactSheetSize(620, 360);
    } else if ([vc isKindOfClass:ModpackInstallViewController.class]) {
        nav.preferredContentSize = PLCompactSheetSize(700, 420);
    } else {
        nav.preferredContentSize = PLCompactSheetSize(620, 400);
    }
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = nav.sheetPresentationController;
        sheet.prefersEdgeAttachedInCompactHeight = YES;
        sheet.preferredCornerRadius = 18;
        sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = YES;
    }
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 4;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return 0.01;
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
    if (row == 0) {
        cell.imageView.image = [UIImage systemImageNamed:@"folder"];
        cell.textLabel.text = localize(@"preference.title.game_directory", nil);
        cell.detailTextLabel.text = nil;
    } else {
        NSString *imageName;
        if (@available(iOS 15.0, *)) {
            imageName = @"folder.badge.gearshape";
        } else {
            imageName = @"folder.badge.gear";
        }
        cell.imageView.image = [UIImage systemImageNamed:imageName];
        cell.textLabel.text = localize(@"profile.title.separate_preference", nil);
        cell.detailTextLabel.text = nil;
        UISwitch *view = [UISwitch new];
        [view setOn:getPrefBool(@"internal.isolated") animated:NO];
        [view addTarget:self action:@selector(actionTogglePrefIsolation:) forControlEvents:UIControlEventValueChanged];
        PLApplyCompactSwitch(view);
        cell.accessoryView = view;
    }
}

- (void)setupProfileCell:(UITableViewCell *) cell atRow:(NSInteger)row {
    NSMutableDictionary *profile = PLProfiles.current.profiles.allValues[row];

    cell.textLabel.text = profile[@"name"];
    cell.detailTextLabel.text = nil;
    cell.imageView.layer.magnificationFilter = kCAFilterNearest;

    UIImage *fallbackImage = [[UIImage imageNamed:@"DefaultProfile"] _imageWithSize:CGSizeMake(32, 32)];
    [cell.imageView setImageWithURL:[NSURL URLWithString:profile[@"icon"]] placeholderImage:fallbackImage];
}

- (UITableViewCell *)tableView:(nonnull UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *cellID = indexPath.section == kInstances ? @"InstanceCell" : @"ProfileCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellID];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        if (indexPath.section == kProfiles) {
            cell.imageView.frame = CGRectMake(0, 0, 32, 32);
            cell.imageView.isSizeFixed = YES;
        }
    } else {
        cell.imageView.image = nil;
        cell.userInteractionEnabled = YES;
        cell.accessoryView = nil;
    }
    PLApplyCompactTableCell(cell);
    if (getLauncherOutlineControlsEnabled()) {
        PLApplyLauncherCardChrome(cell, NO, NSDirectionalEdgeInsetsMake(0, 0, 0, 0), 12);
    } else {
        if (@available(iOS 14.0, *)) {
            cell.backgroundConfiguration = nil;
        }
        cell.layer.borderWidth = 0;
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

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

@end
