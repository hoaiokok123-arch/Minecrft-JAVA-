#import "LauncherNavigationController.h"
#import "LauncherPreferences.h"
#import "LauncherProfileEditorViewController.h"
#import "MinecraftResourceUtils.h"
#import "PickTextField.h"
#import "PLProfiles.h"
#import "UIKit+hook.h"
#import "installer/ModpackInstallViewController.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

static NSString *const LauncherModDisabledSuffix = @".disabled";

static NSString *LauncherInstanceDirectory(NSString *instanceName) {
    if (instanceName.length == 0) {
        instanceName = @"default";
    }

    return [[NSString stringWithFormat:@"%s/instances/%@",
        getenv("POJAV_HOME"), instanceName] stringByStandardizingPath];
}

static NSString *LauncherProfileResolvedGameDirectory(NSDictionary *profile) {
    NSString *instanceName = getPrefObject(@"general.game_directory");
    NSString *profileGameDir = profile[@"gameDir"];
    if (profileGameDir.length == 0) {
        profileGameDir = @".";
    }

    return [[LauncherInstanceDirectory(instanceName)
        stringByAppendingPathComponent:profileGameDir] stringByStandardizingPath];
}

static NSString *LauncherDefaultInstanceDirectory(void) {
    return LauncherInstanceDirectory(@"default");
}

static NSString *LauncherProfileResolvedSubdirectory(NSDictionary *profile, NSString *directoryName) {
    return [LauncherProfileResolvedGameDirectory(profile) stringByAppendingPathComponent:directoryName];
}

static NSString *LauncherDefaultInstanceSubdirectory(NSString *directoryName) {
    return [LauncherDefaultInstanceDirectory() stringByAppendingPathComponent:directoryName];
}

static BOOL LauncherProfileUsesCustomGameDirectory(NSDictionary *profile) {
    NSString *profileGameDir = profile[@"gameDir"];
    if (profileGameDir.length == 0) {
        return NO;
    }

    NSString *normalizedGameDir = [profileGameDir stringByStandardizingPath];
    return normalizedGameDir.length > 0 && ![normalizedGameDir isEqualToString:@"."];
}

typedef NS_ENUM(NSUInteger, LauncherProfileManagedContentType) {
    LauncherProfileManagedContentTypeMod = 0,
    LauncherProfileManagedContentTypeResourcePack,
    LauncherProfileManagedContentTypeDataPack,
    LauncherProfileManagedContentTypeShader
};

static NSString *LauncherProfileDirectoryNameForManagedContent(LauncherProfileManagedContentType type) {
    switch (type) {
        case LauncherProfileManagedContentTypeResourcePack:
            return @"resourcepacks";
        case LauncherProfileManagedContentTypeDataPack:
            return @"datapacks";
        case LauncherProfileManagedContentTypeShader:
            return @"shaderpacks";
        case LauncherProfileManagedContentTypeMod:
        default:
            return @"mods";
    }
}

static NSString *LauncherProfileManageTitleKeyForManagedContent(LauncherProfileManagedContentType type) {
    switch (type) {
        case LauncherProfileManagedContentTypeResourcePack:
            return @"profile.title.manage_resourcepacks";
        case LauncherProfileManagedContentTypeDataPack:
            return @"profile.title.manage_datapacks";
        case LauncherProfileManagedContentTypeShader:
            return @"profile.title.manage_shaders";
        case LauncherProfileManagedContentTypeMod:
        default:
            return @"profile.title.manage_mods";
    }
}

static NSString *LauncherProfileManageEmptyKeyForManagedContent(LauncherProfileManagedContentType type) {
    switch (type) {
        case LauncherProfileManagedContentTypeResourcePack:
            return @"profile.detail.manage_resourcepacks.empty";
        case LauncherProfileManagedContentTypeDataPack:
            return @"profile.detail.manage_datapacks.empty";
        case LauncherProfileManagedContentTypeShader:
            return @"profile.detail.manage_shaders.empty";
        case LauncherProfileManagedContentTypeMod:
        default:
            return @"profile.detail.manage_mods.empty";
    }
}

static NSString *LauncherProfileIconNameForManagedContent(LauncherProfileManagedContentType type, BOOL isDirectory) {
    switch (type) {
        case LauncherProfileManagedContentTypeResourcePack:
            return isDirectory ? @"folder" : @"square.stack.3d.down.forward";
        case LauncherProfileManagedContentTypeDataPack:
            return isDirectory ? @"folder" : @"externaldrive.badge.plus";
        case LauncherProfileManagedContentTypeShader:
            return isDirectory ? @"folder" : @"sparkles";
        case LauncherProfileManagedContentTypeMod:
        default:
            return @"shippingbox";
    }
}

static NSString *LauncherManagedContentNormalizedName(NSString *fileName) {
    if ([fileName hasSuffix:LauncherModDisabledSuffix]) {
        return [fileName substringToIndex:fileName.length - LauncherModDisabledSuffix.length];
    }
    return fileName;
}

static BOOL LauncherManagedContentAllowsDirectories(LauncherProfileManagedContentType type) {
    return type != LauncherProfileManagedContentTypeMod;
}

static BOOL LauncherManagedContentLooksLikeItem(NSString *fileName, BOOL isDirectory, LauncherProfileManagedContentType type) {
    if (fileName.length == 0 || [fileName hasPrefix:@"."]) {
        return NO;
    }

    NSString *normalizedName = LauncherManagedContentNormalizedName(fileName);
    if (normalizedName.length == 0) {
        return NO;
    }

    if (isDirectory) {
        return LauncherManagedContentAllowsDirectories(type);
    }

    NSString *extension = normalizedName.pathExtension.lowercaseString;
    switch (type) {
        case LauncherProfileManagedContentTypeResourcePack:
        case LauncherProfileManagedContentTypeDataPack:
        case LauncherProfileManagedContentTypeShader:
            return [@[@"zip"] containsObject:extension];
        case LauncherProfileManagedContentTypeMod:
        default:
            return [@[@"jar", @"zip", @"litemod"] containsObject:extension];
    }
}

static NSMutableArray<NSMutableDictionary *> *LauncherEnumerateManagedContent(NSString *directory, LauncherProfileManagedContentType type) {
    NSMutableArray<NSMutableDictionary *> *items = [NSMutableArray array];
    NSArray<NSString *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:nil];
    for (NSString *fileName in files) {
        NSString *fullPath = [directory stringByAppendingPathComponent:fileName];
        BOOL isDirectory = NO;
        [NSFileManager.defaultManager fileExistsAtPath:fullPath isDirectory:&isDirectory];
        if (!LauncherManagedContentLooksLikeItem(fileName, isDirectory, type)) {
            continue;
        }

        BOOL enabled = ![fileName hasSuffix:LauncherModDisabledSuffix];
        [items addObject:@{
            @"fileName": fileName,
            @"displayName": LauncherManagedContentNormalizedName(fileName),
            @"enabled": @(enabled),
            @"isDirectory": @(isDirectory)
        }.mutableCopy];
    }

    [items sortUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
        BOOL leftEnabled = [lhs[@"enabled"] boolValue];
        BOOL rightEnabled = [rhs[@"enabled"] boolValue];
        if (leftEnabled != rightEnabled) {
            return leftEnabled ? NSOrderedAscending : NSOrderedDescending;
        }
        return [lhs[@"displayName"] localizedStandardCompare:rhs[@"displayName"]];
    }];
    return items;
}

static NSString *LauncherManagedContentSummary(NSString *directory, LauncherProfileManagedContentType type, NSString *emptyKey) {
    NSUInteger enabledCount = 0;
    NSUInteger disabledCount = 0;
    for (NSDictionary *item in LauncherEnumerateManagedContent(directory, type)) {
        if ([item[@"enabled"] boolValue]) {
            enabledCount++;
        } else {
            disabledCount++;
        }
    }

    if (enabledCount == 0 && disabledCount == 0) {
        return localize(emptyKey, nil);
    }
    return [NSString stringWithFormat:localize(@"profile.detail.manage_content.summary", nil),
        (unsigned long)enabledCount, (unsigned long)disabledCount];
}

@interface LauncherProfileContentManagerViewController : UITableViewController
@property(nonatomic, copy) NSString *directoryPath;
@property(nonatomic, copy) NSString *titleKey;
@property(nonatomic, copy) NSString *emptyKey;
@property(nonatomic) LauncherProfileManagedContentType contentType;
@property(nonatomic) NSMutableArray<NSMutableDictionary *> *items;
@property(nonatomic) UILabel *emptyViewLabel;
@end

@implementation LauncherProfileContentManagerViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = localize(self.titleKey ?: LauncherProfileManageTitleKeyForManagedContent(self.contentType), nil);
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.emptyViewLabel = [[UILabel alloc] initWithFrame:self.tableView.bounds];
    self.emptyViewLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.emptyViewLabel.text = localize(self.emptyKey ?: LauncherProfileManageEmptyKeyForManagedContent(self.contentType), nil);
    self.emptyViewLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyViewLabel.textColor = UIColor.secondaryLabelColor;
    self.emptyViewLabel.numberOfLines = 0;
    self.tableView.backgroundView = self.emptyViewLabel;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadItems];
}

- (void)reloadItems {
    self.items = LauncherEnumerateManagedContent(self.directoryPath, self.contentType);
    self.emptyViewLabel.hidden = self.items.count > 0;
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ContentCell"];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ContentCell"];
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }

    NSDictionary *item = self.items[indexPath.row];
    BOOL isDirectory = [item[@"isDirectory"] boolValue];
    cell.textLabel.text = item[@"displayName"];
    cell.detailTextLabel.text = localize([item[@"enabled"] boolValue] ? @"mods.status.enabled" : @"mods.status.disabled", nil);
    cell.imageView.image = [UIImage systemImageNamed:LauncherProfileIconNameForManagedContent(self.contentType, isDirectory)];

    UISwitch *toggle = [UISwitch new];
    [toggle setOn:[item[@"enabled"] boolValue] animated:NO];
    [toggle addTarget:self action:@selector(toggleItem:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;

    return cell;
}

- (void)toggleItem:(UISwitch *)sender {
    CGPoint point = [sender convertPoint:CGPointMake(CGRectGetMidX(sender.bounds), CGRectGetMidY(sender.bounds))
                                  toView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (!indexPath || indexPath.row >= self.items.count) {
        return;
    }

    NSDictionary *item = self.items[indexPath.row];
    NSString *sourceName = item[@"fileName"];
    NSString *targetName;
    if (sender.isOn) {
        if (![sourceName hasSuffix:LauncherModDisabledSuffix]) {
            return;
        }
        targetName = LauncherManagedContentNormalizedName(sourceName);
    } else {
        if ([sourceName hasSuffix:LauncherModDisabledSuffix]) {
            return;
        }
        targetName = [sourceName stringByAppendingString:LauncherModDisabledSuffix];
    }

    NSString *sourcePath = [self.directoryPath stringByAppendingPathComponent:sourceName];
    NSString *targetPath = [self.directoryPath stringByAppendingPathComponent:targetName];
    NSError *error;
    if (![NSFileManager.defaultManager moveItemAtPath:sourcePath toPath:targetPath error:&error]) {
        [sender setOn:!sender.isOn animated:YES];
        showDialog(localize(@"Error", nil), error.localizedDescription);
        return;
    }

    [self reloadItems];
}

- (void)confirmDeleteItemAtIndexPath:(NSIndexPath *)indexPath sourceView:(UIView *)sourceView completion:(void (^)(BOOL))completion {
    if (indexPath.row >= self.items.count) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    NSDictionary *item = self.items[indexPath.row];
    UIAlertController *confirmAlert = [UIAlertController
        alertControllerWithTitle:localize(@"preference.title.confirm", nil)
                         message:[NSString stringWithFormat:localize(@"profile.title.confirm.delete_content", nil), item[@"displayName"]]
                  preferredStyle:UIAlertControllerStyleActionSheet];
    if (sourceView == nil) {
        sourceView = self.view;
    }
    confirmAlert.popoverPresentationController.sourceView = sourceView;
    confirmAlert.popoverPresentationController.sourceRect = sourceView.bounds;

    UIAlertAction *cancel = [UIAlertAction actionWithTitle:localize(@"Cancel", nil)
                                                     style:UIAlertActionStyleCancel
                                                   handler:^(__unused UIAlertAction *action) {
        if (completion) {
            completion(NO);
        }
    }];
    UIAlertAction *deleteAction = [UIAlertAction actionWithTitle:localize(@"Delete", nil)
                                                           style:UIAlertActionStyleDestructive
                                                         handler:^(__unused UIAlertAction *action) {
        NSString *filePath = [self.directoryPath stringByAppendingPathComponent:item[@"fileName"]];
        NSError *error;
        if (![NSFileManager.defaultManager removeItemAtPath:filePath error:&error]) {
            showDialog(localize(@"Error", nil), error.localizedDescription);
            if (completion) {
                completion(NO);
            }
            return;
        }
        [self reloadItems];
        if (completion) {
            completion(YES);
        }
    }];

    [confirmAlert addAction:cancel];
    [confirmAlert addAction:deleteAction];
    [self presentViewController:confirmAlert animated:YES completion:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:localize(@"Delete", nil)
                                                                             handler:^(__unused UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        [self confirmDeleteItemAtIndexPath:indexPath sourceView:sourceView completion:completionHandler];
    }];
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

@end

@interface LauncherProfileEditorViewController()<UIPickerViewDataSource, UIPickerViewDelegate>
@property(nonatomic) NSString* oldName;

@property(nonatomic) NSArray<NSDictionary *> *versionList;
@property(nonatomic) UITextField* versionTextField;
@property(nonatomic) UISegmentedControl* versionTypeControl;
@property(nonatomic) UIPickerView* versionPickerView;
@property(nonatomic) UIToolbar* versionPickerToolbar;
@property(nonatomic) int versionSelectedAt;
@end

@implementation LauncherProfileEditorViewController

- (void)viewDidLoad {
    // Setup navigation bar & appearance
    self.title = localize(@"Edit profile", nil);
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(actionDone)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(actionClose)];
    self.navigationController.modalInPresentation = YES;
    self.prefSectionsVisible = YES;

    // Setup preference getter and setter
    __weak LauncherProfileEditorViewController *weakSelf = self;
    self.getPreference = ^id(NSString *section, NSString *key){
        if ([key isEqualToString:@"manageMods"]) {
            return LauncherManagedContentSummary([weakSelf profileManagedContentDirectoryForType:LauncherProfileManagedContentTypeMod],
                LauncherProfileManagedContentTypeMod, @"profile.detail.manage_mods.empty");
        } else if ([key isEqualToString:@"manageSharedMods"]) {
            return LauncherManagedContentSummary([weakSelf sharedManagedContentDirectoryForType:LauncherProfileManagedContentTypeMod],
                LauncherProfileManagedContentTypeMod, @"profile.detail.manage_shared_mods.empty");
        } else if ([key isEqualToString:@"manageResourcePacks"]) {
            return LauncherManagedContentSummary([weakSelf sharedManagedContentDirectoryForType:LauncherProfileManagedContentTypeResourcePack],
                LauncherProfileManagedContentTypeResourcePack, @"profile.detail.manage_resourcepacks.empty");
        } else if ([key isEqualToString:@"manageDataPacks"]) {
            return LauncherManagedContentSummary([weakSelf sharedManagedContentDirectoryForType:LauncherProfileManagedContentTypeDataPack],
                LauncherProfileManagedContentTypeDataPack, @"profile.detail.manage_datapacks.empty");
        } else if ([key isEqualToString:@"manageShaders"]) {
            return LauncherManagedContentSummary([weakSelf sharedManagedContentDirectoryForType:LauncherProfileManagedContentTypeShader],
                LauncherProfileManagedContentTypeShader, @"profile.detail.manage_shaders.empty");
        } else if ([key isEqualToString:@"downloadMods"]) {
            return localize(@"profile.detail.download_mods", nil);
        } else if ([key isEqualToString:@"downloadSharedMods"]) {
            return localize(@"profile.detail.download_shared_mods", nil);
        } else if ([key isEqualToString:@"downloadResourcePacks"]) {
            return localize(@"profile.detail.download_resourcepacks", nil);
        } else if ([key isEqualToString:@"downloadDataPacks"]) {
            return localize(@"profile.detail.download_datapacks", nil);
        } else if ([key isEqualToString:@"downloadShaders"]) {
            return localize(@"profile.detail.download_shaders", nil);
        }

        NSString *value = weakSelf.profile[key];
        if (value.length > 0 || ![weakSelf isPickFieldAtSection:section key:key]) {
            return value;
        } else {
            return @"(default)";
        }
    };
    self.setPreference = ^(NSString *section, NSString *key, NSString *value){
        if ([value isEqualToString:@"(default)"] && [weakSelf isPickFieldAtSection:section key:key]) {
            [weakSelf.profile removeObjectForKey:key];
        } else if (value) {
            weakSelf.profile[key] = value;
        }
    };

    // Obtain all the lists
    self.oldName = self.getPreference(nil, @"name");
    if ([self.oldName length] == 0) {
        self.setPreference(nil, @"name", @"New Profile");
    }
    NSArray *rendererKeys = getRendererKeys(YES);
    NSArray *rendererList = getRendererNames(YES);
    NSArray *touchControlList = [self listFilesAtPath:[NSString stringWithFormat:@"%s/controlmap", getenv("POJAV_HOME")]];
    NSArray *gamepadControlList = [self listFilesAtPath:[NSString stringWithFormat:@"%s/controlmap/gamepads", getenv("POJAV_HOME")]];
    NSMutableArray *javaList = [getPrefObject(@"java.java_homes") allKeys].mutableCopy;
    [javaList sortUsingSelector:@selector(compare:)];
    javaList[0] = @"(default)";

    // Setup version picker
    [self setupVersionPicker];
    id typeVersionPicker = ^void(UITableViewCell *cell, NSString *section, NSString *key, NSDictionary *item){
        self.typeTextField(cell, section, key, item);
        UITextField *textField = (id)cell.accessoryView;
        weakSelf.versionTextField = textField;
        textField.inputAccessoryView = weakSelf.versionPickerToolbar;
        textField.inputView = weakSelf.versionPickerView;
        // Auto pick version type
        if (self.versionList) return;
        if ([MinecraftResourceUtils findVersion:textField.text inList:localVersionList]) {
            self.versionTypeControl.selectedSegmentIndex = 0;
        } else {
            NSDictionary *selected = (id)[MinecraftResourceUtils findVersion:textField.text inList:remoteVersionList];
            if (selected) {
                NSArray *types = @[@"installed", @"release", @"snapshot", @"old_beta", @"old_alpha"];
                NSString *type = selected[@"type"];
                self.versionTypeControl.selectedSegmentIndex = [types indexOfObject:type];
            } else {
                // Version not found
                self.versionTypeControl.selectedSegmentIndex = 0;
            }
        }
        self.versionSelectedAt = -1;
        [self changeVersionType:nil];
    };

    BOOL showsSharedMods = LauncherProfileUsesCustomGameDirectory(self.profile);
    NSMutableArray<NSDictionary *> *generalPrefs = [NSMutableArray arrayWithArray:@[
        // General settings
        @{@"key": @"name",
          @"icon": @"tag",
          @"title": @"preference.profile.title.name",
          @"type": self.typeTextField,
          @"placeholder": self.oldName
        },
        @{@"key": @"lastVersionId",
          @"icon": @"archivebox",
          @"title": @"preference.profile.title.version",
          @"type": typeVersionPicker,
          @"placeholder": self.getPreference(nil, @"lastVersionId"),
          @"customClass": PickTextField.class
        },
        @{@"key": @"gameDir",
          @"icon": @"folder",
          @"title": @"preference.title.game_directory",
          @"type": self.typeTextField,
          @"placeholder": [NSString stringWithFormat:@". -> /Documents/instances/%@", getPrefObject(@"general.game_directory")]
        },
        @{@"key": @"manageMods",
          @"icon": @"shippingbox",
          @"title": @"preference.profile.title.manage_mods",
          @"type": self.typeChildPane
        },
    ]];
    if (showsSharedMods) {
        [generalPrefs addObject:@{@"key": @"manageSharedMods",
            @"icon": @"shippingbox.circle",
            @"title": @"preference.profile.title.manage_shared_mods",
            @"type": self.typeChildPane
        }];
    }
    [generalPrefs addObjectsFromArray:@[
        @{@"key": @"manageResourcePacks",
          @"icon": @"square.stack.3d.down.forward",
          @"title": @"preference.profile.title.manage_resourcepacks",
          @"type": self.typeChildPane
        },
        @{@"key": @"manageDataPacks",
          @"icon": @"externaldrive.badge.plus",
          @"title": @"preference.profile.title.manage_datapacks",
          @"type": self.typeChildPane
        },
        @{@"key": @"manageShaders",
          @"icon": @"sparkles",
          @"title": @"preference.profile.title.manage_shaders",
          @"type": self.typeChildPane
        },
        @{@"key": @"downloadMods",
          @"icon": @"arrow.down.circle",
          @"title": @"preference.profile.title.download_mods",
          @"type": self.typeChildPane
        }
    ]];
    if (showsSharedMods) {
        [generalPrefs addObject:@{@"key": @"downloadSharedMods",
            @"icon": @"arrow.down.circle.fill",
            @"title": @"preference.profile.title.download_shared_mods",
            @"type": self.typeChildPane
        }];
    }
    [generalPrefs addObjectsFromArray:@[
        @{@"key": @"downloadResourcePacks",
          @"icon": @"square.stack.3d.down.forward",
          @"title": @"preference.profile.title.download_resourcepacks",
          @"type": self.typeChildPane
        },
        @{@"key": @"downloadDataPacks",
          @"icon": @"externaldrive.badge.plus",
          @"title": @"preference.profile.title.download_datapacks",
          @"type": self.typeChildPane
        },
        @{@"key": @"downloadShaders",
          @"icon": @"sparkles",
          @"title": @"preference.profile.title.download_shaders",
          @"type": self.typeChildPane
        },
        // Video and renderer settings
        @{@"key": @"renderer",
          @"icon": @"cpu",
          @"type": self.typePickField,
          @"pickKeys": rendererKeys,
          @"pickList": rendererList
        },
        // Control settings
        @{@"key": @"defaultTouchCtrl",
          @"icon": @"hand.tap",
          @"title": @"preference.profile.title.default_touch_control",
          @"type": self.typePickField,
          @"pickKeys": touchControlList,
          @"pickList": touchControlList
        },
        @{@"key": @"defaultGamepadCtrl",
          @"icon": @"gamecontroller",
          @"title": @"preference.profile.title.default_gamepad_control",
          @"type": self.typePickField,
          @"pickKeys": gamepadControlList,
          @"pickList": gamepadControlList
        },
        // Java tweaks
        @{@"key": @"javaVersion",
          @"icon": @"cube",
          @"title": @"preference.manage_runtime.header.default",
          @"type": self.typePickField,
          @"pickKeys": javaList,
          @"pickList": javaList
        },
        @{@"key": @"javaArgs",
          @"icon": @"slider.vertical.3",
          @"title": @"preference.title.java_args",
          @"type": self.typeTextField,
          @"placeholder": @"(default)"
        }
    ]];

    self.prefContents = @[
        generalPrefs
    ];

    [super viewDidLoad];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)actionClose {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)actionDone {
    // We might be saving without ending editing, so make sure textFieldDidEndEditing is always called
    UITextField *currentTextField = [self performSelector:@selector(_firstResponder)];
    if ([currentTextField isKindOfClass:UITextField.class] && [currentTextField isDescendantOfView:self.tableView]) {
        [self textFieldDidEndEditing:currentTextField];
    }

    if ([self.profile[@"name"] length] == 0 && self.oldName.length > 0) {
        // Return to its old name
        self.profile[@"name"] = self.oldName;
    }

    if ([self.oldName isEqualToString:self.profile[@"name"]]) {
        // Not a rename, directly create/replace
        PLProfiles.current.profiles[self.oldName] = self.profile;
    } else if (!PLProfiles.current.profiles[self.profile[@"name"]]) {
        // A rename, remove then re-add to update its key name
        if (self.oldName.length > 0) {
            [PLProfiles.current.profiles removeObjectForKey:self.oldName];
        }
        PLProfiles.current.profiles[self.profile[@"name"]] = self.profile;
        // Update selected name
        if ([PLProfiles.current.selectedProfileName isEqualToString:self.oldName]) {
            PLProfiles.current.selectedProfileName = self.profile[@"name"];
        }
    } else {
        // Cancel rename since a profile with the same name already exists
        showDialog(localize(@"Error", nil), localize(@"profile.error.name_exists", nil));
        // Skip dismissing this view controller
        return;
    }

    [PLProfiles.current save];
    [self actionClose];

    // Call LauncherProfilesViewController's viewWillAppear
    UINavigationController *navVC = (id) ((UISplitViewController *)self.presentingViewController).viewControllers[1];
    [navVC.viewControllers[0] viewWillAppear:NO];
}

- (BOOL)isPickFieldAtSection:(NSString *)section key:(NSString *)key {
    NSDictionary *pref = [self.prefContents[0] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"(key == %@)", key]].firstObject;
    return pref[@"type"] == self.typePickField;
}

- (NSString *)profileManagedContentDirectoryForType:(LauncherProfileManagedContentType)type {
    return LauncherProfileResolvedSubdirectory(self.profile, LauncherProfileDirectoryNameForManagedContent(type));
}

- (NSString *)sharedManagedContentDirectoryForType:(LauncherProfileManagedContentType)type {
    return LauncherDefaultInstanceSubdirectory(LauncherProfileDirectoryNameForManagedContent(type));
}

- (void)openInstallerForMode:(ModrinthInstallMode)mode destinationPath:(NSString *)destinationPath {
    ModpackInstallViewController *vc = [ModpackInstallViewController new];
    vc.installMode = mode;
    vc.installDestinationPath = destinationPath;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openContentManagerForType:(LauncherProfileManagedContentType)type
                     directoryPath:(NSString *)directoryPath
                          titleKey:(NSString *)titleKey
                          emptyKey:(NSString *)emptyKey {
    LauncherProfileContentManagerViewController *vc = [LauncherProfileContentManagerViewController new];
    vc.directoryPath = directoryPath;
    vc.titleKey = titleKey;
    vc.emptyKey = emptyKey;
    vc.contentType = type;
    [self.navigationController pushViewController:vc animated:YES];
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = self.prefContents[indexPath.section][indexPath.row];
    if ([item[@"key"] isEqualToString:@"manageMods"]) {
        [tableView deselectRowAtIndexPath:indexPath animated:NO];
        [self.view endEditing:YES];
        [self openContentManagerForType:LauncherProfileManagedContentTypeMod
                           directoryPath:[self profileManagedContentDirectoryForType:LauncherProfileManagedContentTypeMod]
                                titleKey:@"profile.title.manage_mods"
                                emptyKey:@"profile.detail.manage_mods.empty"];
        return;
    } else if ([item[@"key"] isEqualToString:@"manageSharedMods"]) {
        [tableView deselectRowAtIndexPath:indexPath animated:NO];
        [self.view endEditing:YES];
        [self openContentManagerForType:LauncherProfileManagedContentTypeMod
                           directoryPath:[self sharedManagedContentDirectoryForType:LauncherProfileManagedContentTypeMod]
                                titleKey:@"profile.title.manage_shared_mods"
                                emptyKey:@"profile.detail.manage_shared_mods.empty"];
        return;
    } else if ([item[@"key"] isEqualToString:@"manageResourcePacks"]) {
        [tableView deselectRowAtIndexPath:indexPath animated:NO];
        [self.view endEditing:YES];
        [self openContentManagerForType:LauncherProfileManagedContentTypeResourcePack
                           directoryPath:[self sharedManagedContentDirectoryForType:LauncherProfileManagedContentTypeResourcePack]
                                titleKey:@"profile.title.manage_resourcepacks"
                                emptyKey:@"profile.detail.manage_resourcepacks.empty"];
        return;
    } else if ([item[@"key"] isEqualToString:@"manageDataPacks"]) {
        [tableView deselectRowAtIndexPath:indexPath animated:NO];
        [self.view endEditing:YES];
        [self openContentManagerForType:LauncherProfileManagedContentTypeDataPack
                           directoryPath:[self sharedManagedContentDirectoryForType:LauncherProfileManagedContentTypeDataPack]
                                titleKey:@"profile.title.manage_datapacks"
                                emptyKey:@"profile.detail.manage_datapacks.empty"];
        return;
    } else if ([item[@"key"] isEqualToString:@"manageShaders"]) {
        [tableView deselectRowAtIndexPath:indexPath animated:NO];
        [self.view endEditing:YES];
        [self openContentManagerForType:LauncherProfileManagedContentTypeShader
                           directoryPath:[self sharedManagedContentDirectoryForType:LauncherProfileManagedContentTypeShader]
                                titleKey:@"profile.title.manage_shaders"
                                emptyKey:@"profile.detail.manage_shaders.empty"];
        return;
    } else if ([item[@"key"] isEqualToString:@"downloadMods"]) {
        [tableView deselectRowAtIndexPath:indexPath animated:NO];
        [self.view endEditing:YES];
        [self openInstallerForMode:ModrinthInstallModeMod
                   destinationPath:[self profileManagedContentDirectoryForType:LauncherProfileManagedContentTypeMod]];
        return;
    } else if ([item[@"key"] isEqualToString:@"downloadSharedMods"]) {
        [tableView deselectRowAtIndexPath:indexPath animated:NO];
        [self.view endEditing:YES];
        [self openInstallerForMode:ModrinthInstallModeMod
                   destinationPath:[self sharedManagedContentDirectoryForType:LauncherProfileManagedContentTypeMod]];
        return;
    } else if ([item[@"key"] isEqualToString:@"downloadResourcePacks"]) {
        [tableView deselectRowAtIndexPath:indexPath animated:NO];
        [self.view endEditing:YES];
        [self openInstallerForMode:ModrinthInstallModeResourcePack
                   destinationPath:[self sharedManagedContentDirectoryForType:LauncherProfileManagedContentTypeResourcePack]];
        return;
    } else if ([item[@"key"] isEqualToString:@"downloadDataPacks"]) {
        [tableView deselectRowAtIndexPath:indexPath animated:NO];
        [self.view endEditing:YES];
        [self openInstallerForMode:ModrinthInstallModeDataPack
                   destinationPath:[self sharedManagedContentDirectoryForType:LauncherProfileManagedContentTypeDataPack]];
        return;
    } else if ([item[@"key"] isEqualToString:@"downloadShaders"]) {
        [tableView deselectRowAtIndexPath:indexPath animated:NO];
        [self.view endEditing:YES];
        [self openInstallerForMode:ModrinthInstallModeShader
                   destinationPath:[self sharedManagedContentDirectoryForType:LauncherProfileManagedContentTypeShader]];
        return;
    }

    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

- (NSArray *)listFilesAtPath:(NSString *)path {
    NSMutableArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:nil].mutableCopy;
    for (int i = 0; i < files.count;) {
        if ([files[i] hasSuffix:@".json"]) {
            i++;
        } else {
            [files removeObjectAtIndex:i];
        }
    }
    [files insertObject:@"(default)" atIndex:0];
    return files;
}

#pragma mark Version picker

- (void)setupVersionPicker {
    self.versionPickerView = [[UIPickerView alloc] init];
    self.versionPickerView.delegate = self;
    self.versionPickerView.dataSource = self;
    self.versionPickerToolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 390, 44.0)];
    self.versionTypeControl = [[UISegmentedControl alloc] initWithItems:@[
        localize(@"Installed", nil),
        localize(@"Releases", nil),
        localize(@"Snapshot", nil),
        localize(@"Old-beta", nil),
        localize(@"Old-alpha", nil)
    ]];
    self.versionTypeControl.frame = CGRectMake(0, 0, 390, 44.0);
    self.versionTypeControl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.versionTypeControl addTarget:self action:@selector(changeVersionType:) forControlEvents:UIControlEventValueChanged];
    // here we go some random private apis I found
    [[self.versionTypeControl _uiktest_labelsWithState:0] makeObjectsPerformSelector:@selector(setNumberOfLines:) withObject:nil];
    [self.versionPickerToolbar addSubview:self.versionTypeControl];
}

- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
    if (self.versionList.count == 0) {
        self.versionTextField.text = @"";
        return;
    }
    self.versionSelectedAt = row;
    self.versionTextField.text = [self pickerView:pickerView titleForRow:row forComponent:component];
}

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)thePickerView {
    return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    return self.versionList.count;
}

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
    if (self.versionList.count <= row) return nil;
    NSObject *object = self.versionList[row];
    if ([object isKindOfClass:[NSString class]]) {
        return (NSString*) object;
    } else {
        return [object valueForKey:@"id"];
    }
}

- (void)versionClosePicker {
    [self.versionTextField endEditing:YES];
    [self pickerView:self.versionPickerView didSelectRow:[self.versionPickerView selectedRowInComponent:0] inComponent:0];
}

- (void)changeVersionType:(UISegmentedControl *)sender {
    NSArray *newVersionList = self.versionList;
    if (sender || !self.versionList) {
        if (self.versionTypeControl.selectedSegmentIndex == 0) {
            // installed
            newVersionList = localVersionList;
        } else {
            NSString *type = @[@"installed", @"release", @"snapshot", @"old_beta", @"old_alpha"][self.versionTypeControl.selectedSegmentIndex];
            newVersionList = [remoteVersionList filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"(type == %@)", type]];
        }
    }

    if (self.versionSelectedAt == -1) {
        NSDictionary *selected = (id)[MinecraftResourceUtils findVersion:self.versionTextField.text inList:newVersionList];
        self.versionSelectedAt = [newVersionList indexOfObject:selected];
    } else {
        // Find the most matching version for this type
        NSObject *lastSelected = nil; 
        if (self.versionList.count > self.versionSelectedAt) {
            lastSelected = self.versionList[self.versionSelectedAt];
        }
        if (lastSelected != nil) {
            NSObject *nearest = [MinecraftResourceUtils findNearestVersion:lastSelected expectedType:self.versionTypeControl.selectedSegmentIndex];
            if (nearest != nil) {
                self.versionSelectedAt = [newVersionList indexOfObject:(id)nearest];
            }
        }
        lastSelected = nil;
        // Get back the currently selected in case none matching version found
        self.versionSelectedAt = MIN(abs(self.versionSelectedAt), newVersionList.count - 1);
    }

    self.versionList = newVersionList;
    [self.versionPickerView reloadAllComponents];
    if (self.versionSelectedAt != -1) {
        [self.versionPickerView selectRow:self.versionSelectedAt inComponent:0 animated:NO];
        [self pickerView:self.versionPickerView didSelectRow:self.versionSelectedAt inComponent:0];
    }
}

@end
