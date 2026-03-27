#import "config.h"
#import "utils.h"
#import "LauncherPreferences.h"
#import "PLPreferences.h"
#import "UIKit+hook.h"
#import <CoreFoundation/CoreFoundation.h>

static PLPreferences* pref;
NSString * const PLLauncherBackgroundDidChangeNotification = @"PLLauncherBackgroundDidChangeNotification";
NSString * const PLLauncherAppearanceDidChangeNotification = @"PLLauncherAppearanceDidChangeNotification";
static NSString * const PLLauncherBackgroundVideoKey = @"general.launcher_background_video";
static NSString * const PLLauncherBackgroundVideoScaleKey = @"general.launcher_background_video_scale";
static NSString * const PLLauncherBackgroundVideoOffsetXKey = @"general.launcher_background_video_offset_x";
static NSString * const PLLauncherBackgroundVideoOffsetYKey = @"general.launcher_background_video_offset_y";
static NSString * const PLLauncherOutlineControlsKey = @"general.launcher_outline_controls";

static void PLRunLauncherBlockOnMainThread(dispatch_block_t block) {
    if (NSThread.isMainThread) {
        block();
    } else {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

static NSString *PLLauncherBackgroundDirectory(void) {
    NSString *directory = [@(getenv("POJAV_HOME")) stringByAppendingPathComponent:@"launcher_background"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return directory;
}

static BOOL PLLauncherBackgroundPathIsManaged(NSString *path) {
    return [path hasPrefix:PLLauncherBackgroundDirectory()];
}

static void PLCleanupManagedLauncherBackgrounds(NSString *keepPath) {
    NSString *directory = PLLauncherBackgroundDirectory();
    NSArray<NSString *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:nil];
    for (NSString *file in files) {
        NSString *path = [directory stringByAppendingPathComponent:file];
        if (keepPath.length > 0 && [path isEqualToString:keepPath]) {
            continue;
        }
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    }
}

static void PLPostLauncherBackgroundDidChange(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:PLLauncherBackgroundDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter postNotificationName:PLLauncherAppearanceDidChangeNotification object:nil];
}

void postLauncherAppearanceDidChange(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:PLLauncherAppearanceDidChangeNotification object:nil];
}

void loadPreferences(BOOL reset) {
    assert(getenv("POJAV_HOME"));
    if (reset) {
        [pref reset];
    } else {
        pref = [[PLPreferences alloc] initWithAutomaticMigrator];
    }
}

void toggleIsolatedPref(BOOL forceEnable) {
    if (!pref.instancePath) {
        pref.instancePath = [NSString stringWithFormat:@"%s/launcher_preferences.plist", getenv("POJAV_GAME_DIR")];
    }
    [pref toggleIsolationForced:forceEnable];
}

id getPrefObject(NSString *key) {
    return [pref getObject:key];
}
BOOL getPrefBool(NSString *key) {
    return [getPrefObject(key) boolValue];
}
float getPrefFloat(NSString *key) {
    return [getPrefObject(key) floatValue];
}
NSInteger getPrefInt(NSString *key) {
    return [getPrefObject(key) intValue];
}

void setPrefObject(NSString *key, id value) {
    [pref setObject:key value:value];
}
void setPrefBool(NSString *key, BOOL value) {
    setPrefObject(key, @(value));
}
void setPrefFloat(NSString *key, float value) {
    setPrefObject(key, @(value));
}
void setPrefInt(NSString *key, NSInteger value) {
    setPrefObject(key, @(value));
}

void resetWarnings() {
    for (int i = 0; i < pref.globalPref[@"warnings"].count; i++) {
        NSString *key = pref.globalPref[@"warnings"].allKeys[i];
        pref.globalPref[@"warnings"][key] = @YES;
    }
}

#pragma mark Safe area

CGRect getSafeArea(CGRect screenBounds) {
    UIEdgeInsets safeArea = UIEdgeInsetsFromString(getPrefObject(@"control.control_safe_area"));
    if (screenBounds.size.width < screenBounds.size.height) {
        safeArea = UIEdgeInsetsMake(safeArea.right, safeArea.top, safeArea.left, safeArea.bottom);
    }
    return UIEdgeInsetsInsetRect(screenBounds, safeArea);
}

void setSafeArea(CGSize screenSize, CGRect frame) {
    UIEdgeInsets safeArea;
    // TODO: make safe area consistent across opposite orientations?
    if (screenSize.width < screenSize.height) {
        safeArea = UIEdgeInsetsMake(
            frame.origin.x,
            screenSize.height - CGRectGetMaxY(frame),
            screenSize.width - CGRectGetMaxX(frame),
            frame.origin.y);
    } else {
        safeArea = UIEdgeInsetsMake(
            frame.origin.y,
            frame.origin.x,
            screenSize.height - CGRectGetMaxY(frame),
            screenSize.width - CGRectGetMaxX(frame));
    }
    setPrefObject(@"control.control_safe_area", NSStringFromUIEdgeInsets(safeArea));
}

UIEdgeInsets getDefaultSafeArea() {
    UIEdgeInsets safeArea = UIApplication.sharedApplication.windows.firstObject.safeAreaInsets;
    CGSize screenSize = UIScreen.mainScreen.bounds.size;
    if (screenSize.width < screenSize.height) {
        safeArea.left = safeArea.top;
        safeArea.right = safeArea.bottom;
    }
    safeArea.top = safeArea.bottom = 0;
    return safeArea;
}

#pragma mark Java runtime

NSString* getSelectedJavaHome(NSString* defaultJRETag, int minVersion) {
    NSDictionary *pref = getPrefObject(@"java.java_homes");
    NSDictionary<NSString *, NSString *> *selected = pref[@"0"];
    NSString *selectedVer = selected[defaultJRETag];
    if (minVersion > selectedVer.intValue) {
        NSArray *sortedVersions = [pref.allKeys valueForKeyPath:@"self.integerValue"];
        sortedVersions = [sortedVersions sortedArrayUsingSelector:@selector(compare:)];
        for (NSNumber *version in sortedVersions) {
            if (version.intValue >= minVersion) {
                selectedVer = version.stringValue;
                break;
            }
        }
        if (!selectedVer) {
            NSLog(@"Error: requested Java >= %d was not installed!", minVersion);
            return nil;
        }
    }

    id selectedDir = pref[selectedVer];
    if ([selectedDir isEqualToString:@"internal"]) {
        selectedDir = [NSString stringWithFormat:@"%@/java_runtimes/java-%@-openjdk", NSBundle.mainBundle.bundlePath, selectedVer];
    } else {
        selectedDir = [NSString stringWithFormat:@"%s/java_runtimes/%@", getenv("POJAV_HOME"), selectedDir];
    }

    if ([NSFileManager.defaultManager fileExistsAtPath:selectedDir]) {
        return selectedDir;
    } else {
        NSLog(@"Error: selected runtime for %@ does not exist: %@", defaultJRETag, selectedDir);
        return nil;
    }
}

#pragma mark Renderer
NSArray* getRendererKeys(BOOL containsDefault) {
    NSMutableArray *array = @[
        @"auto",
        @ RENDERER_NAME_GL4ES,
        @ RENDERER_NAME_MTL_ANGLE,
        @ RENDERER_NAME_MOBILEGLUES,
        @ RENDERER_NAME_VK_ZINK
    ].mutableCopy;

    if (containsDefault) {
        [array insertObject:@"(default)" atIndex:0];
    }
    
    return array;
}

NSArray* getRendererNames(BOOL containsDefault) {
    NSMutableArray *array;

    array = @[
        localize(@"preference.title.renderer.debug.auto", nil),
        localize(@"preference.title.renderer.debug.gl4es", nil),
        localize(@"preference.title.renderer.debug.angle", nil),
        localize(@"preference.title.renderer.debug.mg", nil),
        localize(@"preference.title.renderer.debug.zink", nil)
    ].mutableCopy;

    if (containsDefault) {
        [array insertObject:@"(default)" atIndex:0];
    }

    return array;
}

NSString *getLauncherBackgroundVideoPath(void) {
    NSString *path = getPrefObject(PLLauncherBackgroundVideoKey);
    if (![path isKindOfClass:NSString.class] || path.length == 0) {
        return nil;
    }
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        setPrefObject(PLLauncherBackgroundVideoKey, @"");
        return nil;
    }
    return path;
}

NSString *getLauncherBackgroundVideoDisplayName(void) {
    NSString *path = getLauncherBackgroundVideoPath();
    return path ? path.lastPathComponent : localize(@"preference.title.launcher_background_none", nil);
}

CGFloat getLauncherBackgroundVideoScale(void) {
    return clamp(getPrefInt(PLLauncherBackgroundVideoScaleKey), 50, 250) / 100.0;
}

CGFloat getLauncherBackgroundVideoOffsetX(void) {
    return clamp(getPrefInt(PLLauncherBackgroundVideoOffsetXKey), -100, 100) / 100.0;
}

CGFloat getLauncherBackgroundVideoOffsetY(void) {
    return clamp(getPrefInt(PLLauncherBackgroundVideoOffsetYKey), -100, 100) / 100.0;
}

BOOL getLauncherOutlineControlsEnabled(void) {
    return getPrefBool(PLLauncherOutlineControlsKey);
}

void resetLauncherBackgroundVideoAdjustments(void) {
    setPrefInt(PLLauncherBackgroundVideoScaleKey, 100);
    setPrefInt(PLLauncherBackgroundVideoOffsetXKey, 0);
    setPrefInt(PLLauncherBackgroundVideoOffsetYKey, 0);
    postLauncherAppearanceDidChange();
}

NSError *setLauncherBackgroundVideoFromURL(NSURL *url) {
    NSString *directory = PLLauncherBackgroundDirectory();
    __block NSString *currentPath = nil;
    PLRunLauncherBlockOnMainThread(^{
        currentPath = [getLauncherBackgroundVideoPath() copy];
    });

    NSString *extension = url.pathExtension.lowercaseString;
    if (extension.length == 0) {
        extension = @"mp4";
    }

    NSString *destination = [directory stringByAppendingPathComponent:
        [NSString stringWithFormat:@"launcher-background-%@.%@",
            NSUUID.UUID.UUIDString.lowercaseString, extension]];

    NSError *error;
    if (![NSFileManager.defaultManager copyItemAtURL:url toURL:[NSURL fileURLWithPath:destination] error:&error]) {
        return error;
    }

    PLRunLauncherBlockOnMainThread(^{
        setPrefObject(PLLauncherBackgroundVideoKey, destination);
        PLPostLauncherBackgroundDidChange();
    });
    if (currentPath.length > 0 && PLLauncherBackgroundPathIsManaged(currentPath)) {
        [NSFileManager.defaultManager removeItemAtPath:currentPath error:nil];
    }
    PLCleanupManagedLauncherBackgrounds(destination);
    return nil;
}

void clearLauncherBackgroundVideo(void) {
    NSString *path = getLauncherBackgroundVideoPath();
    setPrefObject(PLLauncherBackgroundVideoKey, @"");
    PLPostLauncherBackgroundDidChange();
    if (path.length > 0 && PLLauncherBackgroundPathIsManaged(path)) {
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    }
    PLCleanupManagedLauncherBackgrounds(nil);
}
