#import "AFNetworking.h"
#import "DownloadProgressViewController.h"
#import "LauncherNavigationController.h"
#import "ModpackInstallViewController.h"
#import "UIKit+AFNetworking.h"
#import "UIKit+hook.h"
#import "WFWorkflowProgressView.h"
#import "modpack/ModrinthAPI.h"
#import "config.h"
#import "ios_uikit_bridge.h"
#import "utils.h"
#include <dlfcn.h>

#define kCurseForgeGameIDMinecraft 432
#define kCurseForgeClassIDModpack 4471
#define kCurseForgeClassIDMod 6

static NSString *InstallerProjectTypeForMode(ModrinthInstallMode mode) {
    switch (mode) {
        case ModrinthInstallModeMod:
            return @"mod";
        case ModrinthInstallModeResourcePack:
            return @"resourcepack";
        case ModrinthInstallModeDataPack:
            return @"datapack";
        case ModrinthInstallModeShader:
            return @"shader";
        case ModrinthInstallModeModpack:
        default:
            return @"modpack";
    }
}

static NSString *InstallerTitleKeyForMode(ModrinthInstallMode mode) {
    switch (mode) {
        case ModrinthInstallModeMod:
            return @"installer.title.mod";
        case ModrinthInstallModeResourcePack:
            return @"installer.title.resourcepack";
        case ModrinthInstallModeDataPack:
            return @"installer.title.datapack";
        case ModrinthInstallModeShader:
            return @"installer.title.shader";
        case ModrinthInstallModeModpack:
        default:
            return @"installer.title.modpack";
    }
}

static NSString *InstallerSearchPlaceholderKeyForMode(ModrinthInstallMode mode) {
    switch (mode) {
        case ModrinthInstallModeMod:
            return @"installer.search.mod";
        case ModrinthInstallModeResourcePack:
            return @"installer.search.resourcepack";
        case ModrinthInstallModeDataPack:
            return @"installer.search.datapack";
        case ModrinthInstallModeShader:
            return @"installer.search.shader";
        case ModrinthInstallModeModpack:
        default:
            return @"installer.search.modpack";
    }
}

@interface ModpackInstallViewController()<UIContextMenuInteractionDelegate>
@property(nonatomic) UISearchController *searchController;
@property(nonatomic) UIMenu *currentMenu;
@property(nonatomic) NSMutableArray *list;
@property(nonatomic) NSMutableDictionary *filters;
@property(nonatomic) NSMutableArray<MinecraftResourceDownloadTask *> *activeTasks;
@property ModrinthAPI *modrinth;
@end

@implementation ModpackInstallViewController

- (BOOL)isInstallingModpack {
    return self.installMode == ModrinthInstallModeModpack;
}

- (void)startStandaloneProjectDownload:(NSDictionary *)item atIndex:(NSUInteger)index {
    MinecraftResourceDownloadTask *task = [MinecraftResourceDownloadTask new];
    [self.activeTasks addObject:task];
    [task downloadProjectFileFromDetail:item atIndex:index toPath:self.installDestinationPath];
    if (task.progress.cancelled) {
        [self.activeTasks removeObject:task];
        return;
    }
    DownloadProgressViewController *vc = [[DownloadProgressViewController alloc] initWithTask:task];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    //NSString *curseforgeAPIKey = CONFIG_CURSEFORGE_API_KEY;
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = localize(InstallerSearchPlaceholderKeyForMode(self.installMode), nil);
    self.navigationItem.searchController = self.searchController;
    self.title = localize(InstallerTitleKeyForMode(self.installMode), nil);
    self.activeTasks = [NSMutableArray array];
    self.modrinth = [ModrinthAPI new];
    self.filters = @{
        @"projectType": InstallerProjectTypeForMode(self.installMode),
        @"name": @" "
        // mcVersion
    }.mutableCopy;
    [self updateSearchResults];
}

- (void)loadSearchResultsWithPrevList:(BOOL)prevList {
    NSString *name = self.searchController.searchBar.text;
    if (!prevList && [self.filters[@"name"] isEqualToString:name]) {
        return;
    }

    [self switchToLoadingState];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        self.filters[@"name"] = name;
        self.list = [self.modrinth searchModWithFilters:self.filters previousPageResult:prevList ? self.list : nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.list) {
                [self switchToReadyState];
                [self.tableView reloadData];
            } else {
                showDialog(localize(@"Error", nil), self.modrinth.lastError.localizedDescription);
                [self actionClose];
            }
        });
    });
}

- (void)updateSearchResults {
    [self loadSearchResultsWithPrevList:NO];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateSearchResults) object:nil];
    [self performSelector:@selector(updateSearchResults) withObject:nil afterDelay:0.5];
}

- (void)actionClose {
    if (self.navigationController.viewControllers.firstObject == self) {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)switchToLoadingState {
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:indicator];
    [indicator startAnimating];
    self.navigationController.modalInPresentation = YES;
    self.tableView.allowsSelection = NO;
}

- (void)switchToReadyState {
    UIActivityIndicatorView *indicator = (id)self.navigationItem.rightBarButtonItem.customView;
    [indicator stopAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(actionClose)];
    self.navigationController.modalInPresentation = NO;
    self.tableView.allowsSelection = YES;
}

#pragma mark UIContextMenu

- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(CGPoint)location
{
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
        return self.currentMenu;
    }];
}

- (_UIContextMenuStyle *)_contextMenuInteraction:(UIContextMenuInteraction *)interaction styleForMenuWithConfiguration:(UIContextMenuConfiguration *)configuration
{
    _UIContextMenuStyle *style = [_UIContextMenuStyle defaultStyle];
    style.preferredLayout = 3; // _UIContextMenuLayoutCompactMenu
    return style;
}

#pragma mark UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.list.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"];
        cell.imageView.contentMode = UIViewContentModeScaleToFill;
        cell.imageView.clipsToBounds = YES;
    }

    NSDictionary *item = self.list[indexPath.row];
    cell.textLabel.text = item[@"title"];
    cell.detailTextLabel.text = item[@"description"];
    UIImage *fallbackImage = [UIImage imageNamed:@"DefaultProfile"];
    [cell.imageView setImageWithURL:[NSURL URLWithString:item[@"imageUrl"]] placeholderImage:fallbackImage];

    if (!self.modrinth.reachedLastPage && indexPath.row == self.list.count-1) {
        [self loadSearchResultsWithPrevList:YES];
    }

    return cell;
}

- (void)showDetails:(NSDictionary *)details atIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];

    NSMutableArray<UIAction *> *menuItems = [[NSMutableArray alloc] init];
    [details[@"versionNames"] enumerateObjectsUsingBlock:
    ^(NSString *name, NSUInteger i, BOOL *stop) {
        NSString *nameWithVersion = name;
        NSString *mcVersion = details[@"mcVersionNames"][i];
        if (![name hasSuffix:mcVersion]) {
            nameWithVersion = [NSString stringWithFormat:@"%@ - %@", name, mcVersion];
        }
        [menuItems addObject:[UIAction
            actionWithTitle:nameWithVersion
            image:nil identifier:nil
            handler:^(UIAction *action) {
            if (![self isInstallingModpack] && self.installDestinationPath.length == 0) {
                showDialog(localize(@"Error", nil), localize(@"installer.error.destination_missing", nil));
                return;
            }
            if ([self isInstallingModpack]) {
                [self actionClose];
                NSString *tmpIconPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"icon.png"];
                [UIImagePNGRepresentation([cell.imageView.image _imageWithSize:CGSizeMake(40, 40)]) writeToFile:tmpIconPath atomically:YES];
                [self.modrinth installModpackFromDetail:self.list[indexPath.row] atIndex:i];
            } else {
                [self startStandaloneProjectDownload:self.list[indexPath.row] atIndex:i];
            }
        }]];
    }];

    self.currentMenu = [UIMenu menuWithTitle:@"" children:menuItems];
    UIContextMenuInteraction *interaction = [[UIContextMenuInteraction alloc] initWithDelegate:self];
    cell.detailTextLabel.interactions = @[interaction];
    [interaction _presentMenuAtLocation:CGPointZero];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = self.list[indexPath.row];
    if ([item[@"versionDetailsLoaded"] boolValue]) {
        [self showDetails:item atIndexPath:indexPath];
        return;
    }
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    [self switchToLoadingState];
dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.modrinth loadDetailsOfMod:self.list[indexPath.row]];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self switchToReadyState];
            if ([item[@"versionDetailsLoaded"] boolValue]) {
                [self showDetails:item atIndexPath:indexPath];
            } else {
                showDialog(localize(@"Error", nil), self.modrinth.lastError.localizedDescription);
            }
        });
    });
}

@end
