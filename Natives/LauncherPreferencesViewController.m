#import <Foundation/Foundation.h>

#import "DBNumberedSlider.h"
#import "HostManagerBridge.h"
#import "LauncherNavigationController.h"
#import "LauncherMenuViewController.h"
#import "LauncherPreferences.h"
#import "LauncherPrefBackgroundViewController.h"
#import "LauncherPreferencesViewController.h"
#import "LauncherPrefContCfgViewController.h"
#import "LauncherPrefManageJREViewController.h"
#import "UIKit+hook.h"

#import "config.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

@interface LauncherPreferencesViewController()
@property(nonatomic) NSArray<NSString*> *rendererKeys, *rendererList;
@property(nonatomic) NSArray<NSString*> *lwjglVersionKeys, *lwjglVersionList;
@end

@implementation LauncherPreferencesViewController

- (id)init {
    self = [super init];
    self.title = localize(@"Settings", nil);
    return self;
}

- (NSString *)imageName {
    return @"MenuSettings";
}

- (void)viewDidLoad
{
    self.getPreference = ^id(NSString *section, NSString *key){
        if ([key isEqualToString:@"launcher_background_video"]) {
            return getLauncherBackgroundVideoDisplayName();
        }
        NSString *keyFull = [NSString stringWithFormat:@"%@.%@", section, key];
        return getPrefObject(keyFull);
    };
    self.setPreference = ^(NSString *section, NSString *key, id value){
        NSString *keyFull = [NSString stringWithFormat:@"%@.%@", section, key];
        setPrefObject(keyFull, value);
    };
    
    self.hasDetail = NO;
    self.prefDetailVisible = NO;
    
    self.prefSections = @[@"general", @"video", @"control", @"java", @"debug"];

    self.rendererKeys = getRendererKeys(NO);
    self.rendererList = getRendererNames(NO);
    self.lwjglVersionKeys = @[@"3.3.3", @"3.3.1"];
    self.lwjglVersionList = @[
        localize(@"preference.title.lwjgl_version.333", nil),
        localize(@"preference.title.lwjgl_version.331", nil)
    ];
    
    BOOL(^whenNotInGame)() = ^BOOL(){
        return self.navigationController != nil;
    };
    self.prefContents = @[
        @[
            // General settings
            @{@"icon": @"cube"},
            @{@"key": @"check_sha",
              @"hasDetail": @YES,
              @"icon": @"lock.shield",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame
            },
            @{@"key": @"cosmetica",
              @"hasDetail": @YES,
              @"icon": @"eyeglasses",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame
            },
            @{@"key": @"debug_logging",
              @"hasDetail": @YES,
              @"icon": @"doc.badge.gearshape",
              @"type": self.typeSwitch,
              @"action": ^(BOOL enabled){
                  debugLogEnabled = enabled;
                  NSLog(@"[Debugging] Debug log enabled: %@", enabled ? @"YES" : @"NO");
              }
            },
            @{@"key": @"appicon",
              @"hasDetail": @YES,
              @"icon": @"paintbrush",
              @"type": self.typePickField,
              @"enableCondition": ^BOOL(){
                  return UIApplication.sharedApplication.supportsAlternateIcons;
              },
              @"action": ^void(NSString *iconName) {
                  if ([iconName isEqualToString:@"AppIcon-Light"]) {
                      iconName = nil;
                  }
                  [UIApplication.sharedApplication setAlternateIconName:iconName completionHandler:^(NSError * _Nullable error) {
                      if (error == nil) return;
                      NSLog(@"Error in appicon: %@", error);
                      showDialog(localize(@"Error", nil), error.localizedDescription);
                  }];
              },
              @"pickKeys": @[
                  @"AppIcon-Light",
              ],
              @"pickList": @[
                  localize(@"preference.title.appicon-default", nil)
              ]
            },
            @{@"key": @"launcher_background_video",
              @"icon": @"play.rectangle",
              @"title": @"preference.title.launcher_background_video",
              @"type": self.typeChildPane,
              @"class": LauncherPrefBackgroundViewController.class,
              @"canDismissWithSwipe": @YES,
              @"enableCondition": whenNotInGame
            },
            @{@"key": @"launcher_outline_controls",
              @"icon": @"square.dashed",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame,
              @"action": ^(BOOL enabled){
                  postLauncherAppearanceDidChange();
              }
            },
            @{@"key": @"hidden_sidebar",
              @"hasDetail": @YES,
              @"icon": @"sidebar.leading",
              @"type": self.typeSwitch,
              @"enableCondition": whenNotInGame
            },
            @{@"key": @"reset_warnings",
              @"icon": @"exclamationmark.triangle",
              @"type": self.typeButton,
              @"enableCondition": whenNotInGame,
              @"action": ^void(){
                  resetWarnings();
              }
            },
            @{@"key": @"reset_settings",
              @"icon": @"trash",
              @"type": self.typeButton,
              @"enableCondition": whenNotInGame,
              @"requestReload": @YES,
              @"showConfirmPrompt": @YES,
              @"destructive": @YES,
              @"action": ^void(){
                  loadPreferences(YES);
                  [self.tableView reloadData];
              }
            },
            @{@"key": @"erase_demo_data",
              @"icon": @"trash",
              @"type": self.typeButton,
              @"enableCondition": ^BOOL(){
                  NSString *demoPath = [NSString stringWithFormat:@"%s/.demo", getenv("POJAV_HOME")];
                  int count = [NSFileManager.defaultManager contentsOfDirectoryAtPath:demoPath error:nil].count;
                  return whenNotInGame() && count > 0;
              },
              @"showConfirmPrompt": @YES,
              @"destructive": @YES,
              @"action": ^void(){
                  NSString *demoPath = [NSString stringWithFormat:@"%s/.demo", getenv("POJAV_HOME")];
                  NSError *error;
                  if([NSFileManager.defaultManager removeItemAtPath:demoPath error:&error]) {
                      [NSFileManager.defaultManager createDirectoryAtPath:demoPath
                                              withIntermediateDirectories:YES attributes:nil error:nil];
                      [NSFileManager.defaultManager changeCurrentDirectoryPath:demoPath];
                      if (getenv("DEMO_LOCK")) {
                          [(LauncherNavigationController *)self.navigationController fetchLocalVersionList];
                      }
                  } else {
                      NSLog(@"Error in erase_demo_data: %@", error);
                      showDialog(localize(@"Error", nil), error.localizedDescription);
                  }
              }
            }
        ], @[
            // Video and renderer settings
            @{@"icon": @"video"},
            @{@"key": @"renderer",
              @"hasDetail": @YES,
              @"icon": @"cpu",
              @"type": self.typePickField,
              @"enableCondition": whenNotInGame,
              @"pickKeys": self.rendererKeys,
              @"pickList": self.rendererList
            },
            @{@"key": @"resolution",
              @"hasDetail": @YES,
              @"icon": @"viewfinder",
              @"type": self.typeSlider,
              @"min": @(25),
              @"max": @(150)
            },
            @{@"key": @"max_framerate",
              @"hasDetail": @YES,
              @"icon": @"timelapse",
              @"type": self.typeSwitch,
              @"enableCondition": ^BOOL(){
                  return whenNotInGame() && (UIScreen.mainScreen.maximumFramesPerSecond > 60);
              }
            },
            @{@"key": @"performance_hud",
              @"hasDetail": @YES,
              @"icon": @"waveform.path.ecg",
              @"type": self.typeSwitch,
              @"enableCondition": ^BOOL(){
                  return [CAMetalLayer instancesRespondToSelector:@selector(developerHUDProperties)];
              }
            },
            @{@"key": @"fullscreen_airplay",
              @"hasDetail": @YES,
              @"icon": @"airplayvideo",
              @"type": self.typeSwitch,
              @"action": ^(BOOL enabled){
                  if (self.navigationController != nil) return;
                  if (UIApplication.sharedApplication.connectedScenes.count < 2) return;
                  if (enabled) {
                      [self.presentingViewController performSelector:@selector(switchToExternalDisplay)];
                  } else {
                      [self.presentingViewController performSelector:@selector(switchToInternalDisplay)];
                  }
              }
            },
            @{@"key": @"silence_other_audio",
              @"hasDetail": @YES,
              @"icon": @"speaker.slash",
              @"type": self.typeSwitch
            },
            @{@"key": @"silence_with_switch",
              @"hasDetail": @YES,
              @"icon": @"speaker.zzz",
              @"type": self.typeSwitch
            },
            @{@"key": @"allow_microphone",
              @"hasDetail": @YES,
              @"icon": @"mic",
              @"type": self.typeSwitch
            },
        ], @[
            // Control settings
            @{@"icon": @"gamecontroller"},
            @{@"key": @"default_gamepad_ctrl",
                @"icon": @"hammer",
                @"type": self.typeChildPane,
                @"enableCondition": whenNotInGame,
                @"canDismissWithSwipe": @NO,
                @"class": LauncherPrefContCfgViewController.class
            },
            @{@"key": @"hardware_hide",
                @"icon": @"eye.slash",
                @"hasDetail": @YES,
                @"type": self.typeSwitch,
            },
            @{@"key": @"recording_hide",
                @"icon": @"eye.slash",
                @"hasDetail": @YES,
                @"type": self.typeSwitch,
            },
            @{@"key": @"gesture_mouse",
                @"icon": @"cursorarrow.click",
                @"hasDetail": @YES,
                @"type": self.typeSwitch,
            },
            @{@"key": @"gesture_hotbar",
                @"icon": @"hand.tap",
                @"hasDetail": @YES,
                @"type": self.typeSwitch,
            },
            @{@"key": @"disable_haptics",
                @"icon": @"wave.3.left",
                @"hasDetail": @NO,
                @"type": self.typeSwitch,
            },
            @{@"key": @"slideable_hotbar",
                @"hasDetail": @YES,
                @"icon": @"slider.horizontal.below.rectangle",
                @"type": self.typeSwitch
            },
            @{@"key": @"press_duration",
                @"hasDetail": @YES,
                @"icon": @"cursorarrow.click.badge.clock",
                @"type": self.typeSlider,
                @"min": @(100),
                @"max": @(1000),
            },
            @{@"key": @"button_scale",
                @"hasDetail": @YES,
                @"icon": @"aspectratio",
                @"type": self.typeSlider,
                @"min": @(50), // 80?
                @"max": @(500)
            },
            @{@"key": @"mouse_scale",
                @"hasDetail": @YES,
                @"icon": @"arrow.up.left.and.arrow.down.right.circle",
                @"type": self.typeSlider,
                @"min": @(25),
                @"max": @(300)
            },
            @{@"key": @"mouse_speed",
                @"hasDetail": @YES,
                @"icon": @"cursorarrow.motionlines",
                @"type": self.typeSlider,
                @"min": @(25),
                @"max": @(300)
            },
            @{@"key": @"virtmouse_enable",
                @"hasDetail": @YES,
                @"icon": @"cursorarrow.rays",
                @"type": self.typeSwitch
            },
            @{@"key": @"gyroscope_enable",
                @"hasDetail": @YES,
                @"icon": @"gyroscope",
                @"type": self.typeSwitch,
                @"enableCondition": ^BOOL(){
                    return realUIIdiom != UIUserInterfaceIdiomTV;
                }
            },
            @{@"key": @"gyroscope_invert_x_axis",
                @"hasDetail": @YES,
                @"icon": @"arrow.left.and.right",
                @"type": self.typeSwitch,
                @"enableCondition": ^BOOL(){
                    return realUIIdiom != UIUserInterfaceIdiomTV;
                }
            },
            @{@"key": @"gyroscope_sensitivity",
                @"hasDetail": @YES,
                @"icon": @"move.3d",
                @"type": self.typeSlider,
                @"min": @(50),
                @"max": @(300),
                @"enableCondition": ^BOOL(){
                    return realUIIdiom != UIUserInterfaceIdiomTV;
                }
            }
        ], @[
        // Java tweaks
            @{@"icon": @"sparkles"},
            @{@"key": @"manage_runtime",
                @"hasDetail": @YES,
                @"icon": @"cube",
                @"type": self.typeChildPane,
                @"canDismissWithSwipe": @YES,
                @"class": LauncherPrefManageJREViewController.class,
                @"enableCondition": whenNotInGame
            },
            @{@"key": @"java_args",
                @"hasDetail": @YES,
                @"icon": @"slider.vertical.3",
                @"type": self.typeTextField,
                @"enableCondition": whenNotInGame
            },
            @{@"key": @"lwjgl_version",
                @"hasDetail": @YES,
                @"icon": @"cube",
                @"type": self.typePickField,
                @"enableCondition": whenNotInGame,
                @"pickKeys": self.lwjglVersionKeys,
                @"pickList": self.lwjglVersionList
            },
            @{@"key": @"env_variables",
                @"hasDetail": @YES,
                @"icon": @"terminal",
                @"type": self.typeTextField,
                @"enableCondition": whenNotInGame
            },
            @{@"key": @"auto_ram",
                @"hasDetail": @YES,
                @"icon": @"slider.horizontal.3",
                @"type": self.typeSwitch,
                @"enableCondition": whenNotInGame,
                @"warnCondition": ^BOOL(){
                    return !isJailbroken;
                },
                @"warnKey": @"auto_ram_warn",
                @"requestReload": @YES
            },
            @{@"key": @"allocated_memory",
                @"hasDetail": @YES,
                @"icon": @"memorychip",
                @"type": self.typeSlider,
                @"min": @(250),
                @"max": @((NSProcessInfo.processInfo.physicalMemory / 1048576) * 0.85),
                @"enableCondition": ^BOOL(){
                    return !getPrefBool(@"java.auto_ram") && whenNotInGame();
                },
                @"warnCondition": ^BOOL(DBNumberedSlider *view){
                    return view.value >= NSProcessInfo.processInfo.physicalMemory / 1048576 * 0.37;
                },
                @"warnKey": @"mem_warn"
            }
        ], @[
            // Debug settings - only recommended for developer use
            @{@"icon": @"ladybug"},
            @{@"key": @"debug_always_attached_jit",
                @"hasDetail": @YES,
                @"icon": @"app.connected.to.app.below.fill",
                @"type": self.typeSwitch,
                @"enableCondition": ^BOOL(){
                    return DeviceRequiresTXMWorkaround() && whenNotInGame();
                },
            },
            @{@"key": @"debug_skip_wait_jit",
                @"hasDetail": @YES,
                @"icon": @"forward",
                @"type": self.typeSwitch,
                @"enableCondition": whenNotInGame
            },
            @{@"key": @"debug_hide_home_indicator",
                @"hasDetail": @YES,
                @"icon": @"iphone.and.arrow.forward",
                @"type": self.typeSwitch,
                @"enableCondition": ^BOOL(){
                    return
                        self.splitViewController.view.safeAreaInsets.bottom > 0 ||
                        self.view.safeAreaInsets.bottom > 0;
                }
            },
            @{@"key": @"debug_ipad_ui",
                @"hasDetail": @YES,
                @"icon": @"ipad",
                @"type": self.typeSwitch,
                @"enableCondition": whenNotInGame
            },
            @{@"key": @"debug_auto_correction",
                @"hasDetail": @YES,
                @"icon": @"textformat.abc.dottedunderline",
                @"type": self.typeSwitch
            }
        ]
    ];

    [super viewDidLoad];
    self.tableView.sectionHeaderHeight = 6;
    self.tableView.sectionFooterHeight = 0.01;
    if (NSProcessInfo.processInfo.isMacCatalystApp) {
        UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeClose];
        closeButton.frame = CGRectOffset(closeButton.frame, 10, 10);
        [closeButton addTarget:self action:@selector(actionClose) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:closeButton];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.navigationController == nil) {
        [self.presentingViewController performSelector:@selector(updatePreferenceChanges)];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.navigationController) {
        self.navigationItem.rightBarButtonItems = @[[sidebarViewController drawAccountButton]];
    }
}

- (void)actionClose {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark UITableView

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return section == 0 ? 8 : 4;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return 0.01;
}

@end
