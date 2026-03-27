#import <SafariServices/SafariServices.h>

#include "jni.h"
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <dirent.h>

#import "LauncherPreferences.h"
#include "utils.h"

CFTypeRef SecTaskCopyValueForEntitlement(void* task, NSString* entitlement, CFErrorRef  _Nullable *error);
void* SecTaskCreateFromSelf(CFAllocatorRef allocator);

BOOL getEntitlementValue(NSString *key) {
    void *secTask = SecTaskCreateFromSelf(NULL);
    CFTypeRef value = SecTaskCopyValueForEntitlement(SecTaskCreateFromSelf(NULL), key, nil);
    if (value != nil) {
        CFRelease(value);
    }
    CFRelease(secTask);

    return value != nil && [(__bridge id)value boolValue];
}

BOOL isJITEnabled(BOOL checkCSFlags) {
    if (!checkCSFlags && (getEntitlementValue(@"dynamic-codesigning") || isJailbroken)) {
        return YES;
    }

    int flags;
    csops(getpid(), 0, &flags, sizeof(flags));
    return (flags & CS_DEBUGGED) != 0;
}

void openLink(UIViewController* sender, NSURL* link) {
    if (NSClassFromString(@"SFSafariViewController") == nil) {
        NSData *data = [link.absoluteString dataUsingEncoding:NSUTF8StringEncoding];
        CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
        [filter setValue:data forKey:@"inputMessage"];
        UIImage *image = [UIImage imageWithCIImage:filter.outputImage scale:1.0 orientation:UIImageOrientationUp];
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(300, 300), NO, 0.0);
        CGRect frame = CGRectMake(0, 0, 300, 300);
        [image drawInRect:frame];
        UIImageView *imageView = [[UIImageView alloc] initWithFrame:frame];
        imageView.image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        UIAlertController* alert = [UIAlertController alertControllerWithTitle:nil
            message:link.absoluteString
            preferredStyle:UIAlertControllerStyleAlert];

        UIViewController *vc = UIViewController.new;
        vc.view = imageView;
        [alert setValue:vc forKey:@"contentViewController"];

        UIAlertAction* doneAction = [UIAlertAction actionWithTitle:localize(@"Done", nil) style:UIAlertActionStyleCancel handler:nil];
        [alert addAction:doneAction];
        [sender presentViewController:alert animated:YES completion:nil];
    } else {
        SFSafariViewController *vc = [[SFSafariViewController alloc] initWithURL:link];
        [sender presentViewController:vc animated:YES completion:nil];
    }
}

void PLApplyCompactTableLayout(UITableView *tableView, CGFloat rowHeight) {
    tableView.rowHeight = rowHeight;
    tableView.estimatedRowHeight = rowHeight;
    tableView.estimatedSectionHeaderHeight = 0;
    tableView.estimatedSectionFooterHeight = 0;
    tableView.cellLayoutMarginsFollowReadableWidth = NO;
    tableView.contentInset = UIEdgeInsetsZero;
    tableView.opaque = NO;
    tableView.backgroundColor = UIColor.clearColor;
    if (!tableView.backgroundView) {
        tableView.backgroundView = [UIView new];
    }
    tableView.backgroundView.backgroundColor = UIColor.clearColor;
    if (@available(iOS 15.0, *)) {
        tableView.sectionHeaderTopPadding = 0;
    }
}

void PLApplyCompactTableCell(UITableViewCell *cell) {
    cell.layoutMargins = UIEdgeInsetsMake(0, 6, 0, 6);
    cell.separatorInset = UIEdgeInsetsMake(0, 10, 0, 10);
    cell.textLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightMedium];
    cell.textLabel.minimumScaleFactor = 0.75;
    if (cell.detailTextLabel) {
        cell.detailTextLabel.font = [UIFont systemFontOfSize:10.5];
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
        cell.detailTextLabel.minimumScaleFactor = 0.7;
    }
}

void PLApplyCompactTextField(UITextField *textField, CGFloat width, CGFloat height) {
    CGRect frame = textField.frame;
    frame.size.width = clamp(width, 104, 210);
    frame.size.height = clamp(height, 28, 32);
    textField.frame = frame;
    textField.font = [UIFont systemFontOfSize:13];
    textField.minimumFontSize = 10.5;
    textField.clearButtonMode = UITextFieldViewModeWhileEditing;
}

void PLApplyCompactSlider(UIView *view, CGFloat width, CGFloat height) {
    CGRect frame = view.frame;
    frame.size.width = clamp(width, 118, 208);
    frame.size.height = clamp(height, 28, 32);
    view.frame = frame;
    view.transform = CGAffineTransformMakeScale(0.92, 0.86);
}

void PLApplyCompactSwitch(UISwitch *toggle) {
    toggle.transform = CGAffineTransformMakeScale(0.82, 0.82);
}

UIColor *PLLauncherAccentColor(void) {
    return [UIColor colorWithRed:121/255.0 green:56/255.0 blue:162/255.0 alpha:1.0];
}

static void PLClearLauncherBackdropRecursive(UIView *view) {
    if (!view) {
        return;
    }

    NSString *className = NSStringFromClass(view.class);
    BOOL isBackdropView =
        [className containsString:@"BarBackground"] ||
        [className containsString:@"Backdrop"] ||
        [className containsString:@"DropShadow"] ||
        [className containsString:@"VisualEffect"] ||
        [className containsString:@"PopoverBackground"];

    if ([view isKindOfClass:UIVisualEffectView.class]) {
        ((UIVisualEffectView *)view).effect = nil;
        isBackdropView = YES;
    }

    if (isBackdropView) {
        view.opaque = NO;
        view.backgroundColor = UIColor.clearColor;
        if ([className containsString:@"Shadow"]) {
            view.hidden = YES;
        }
    }

    for (UIView *subview in view.subviews) {
        PLClearLauncherBackdropRecursive(subview);
    }
}

void PLApplyLauncherViewChrome(UIView *view) {
    if (!view) {
        return;
    }

    UIView *cursor = view;
    while (cursor && ![cursor isKindOfClass:UIWindow.class]) {
        cursor.opaque = NO;
        cursor.backgroundColor = UIColor.clearColor;
        if ([cursor isKindOfClass:UIVisualEffectView.class]) {
            ((UIVisualEffectView *)cursor).effect = nil;
        }
        cursor = cursor.superview;
    }

    PLClearLauncherBackdropRecursive(view);
}

void PLApplyLauncherNavigationBarChrome(UINavigationBar *navigationBar) {
    if (!navigationBar) {
        return;
    }

    navigationBar.translucent = YES;
    navigationBar.backgroundColor = UIColor.clearColor;
    navigationBar.barTintColor = UIColor.clearColor;

    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithTransparentBackground];
        appearance.backgroundColor = UIColor.clearColor;
        appearance.backgroundEffect = nil;
        appearance.shadowColor = UIColor.clearColor;
        navigationBar.standardAppearance = appearance;
        navigationBar.compactAppearance = appearance;
        navigationBar.scrollEdgeAppearance = appearance;
        if (@available(iOS 15.0, *)) {
            navigationBar.compactScrollEdgeAppearance = appearance;
        }
    } else {
        [navigationBar setBackgroundImage:[UIImage new] forBarMetrics:UIBarMetricsDefault];
        navigationBar.shadowImage = [UIImage new];
    }
    PLApplyLauncherViewChrome(navigationBar);
}

void PLApplyLauncherToolbarChrome(UIToolbar *toolbar) {
    if (!toolbar) {
        return;
    }

    toolbar.translucent = YES;
    toolbar.backgroundColor = UIColor.clearColor;
    toolbar.barTintColor = UIColor.clearColor;
    [toolbar setBackgroundImage:[UIImage new] forToolbarPosition:UIBarPositionAny barMetrics:UIBarMetricsDefault];
    [toolbar setBackgroundImage:[UIImage new] forToolbarPosition:UIBarPositionAny barMetrics:UIBarMetricsCompact];
    [toolbar setShadowImage:[UIImage new] forToolbarPosition:UIBarPositionAny];
    PLApplyLauncherViewChrome(toolbar);
}

void PLApplyLauncherCardChrome(UITableViewCell *cell, BOOL selected, NSDirectionalEdgeInsets insets, CGFloat cornerRadius) {
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    if (@available(iOS 14.0, *)) {
        UIBackgroundConfiguration *backgroundConfig = [UIBackgroundConfiguration clearConfiguration];
        backgroundConfig.backgroundInsets = insets;
        backgroundConfig.cornerRadius = cornerRadius;
        if (getLauncherOutlineControlsEnabled()) {
            backgroundConfig.strokeWidth = 1.0 / UIScreen.mainScreen.scale;
            backgroundConfig.strokeColor = selected ? PLLauncherAccentColor() : [UIColor colorWithWhite:1 alpha:0.18];
            backgroundConfig.backgroundColor = selected ? [PLLauncherAccentColor() colorWithAlphaComponent:0.14] : UIColor.clearColor;
        } else {
            backgroundConfig.backgroundColor = selected ? [PLLauncherAccentColor() colorWithAlphaComponent:0.16] : UIColor.clearColor;
        }
        cell.backgroundConfiguration = backgroundConfig;
    } else if (getLauncherOutlineControlsEnabled()) {
        cell.layer.cornerRadius = cornerRadius;
        cell.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        cell.layer.borderColor = (selected ? PLLauncherAccentColor() : [UIColor colorWithWhite:1 alpha:0.18]).CGColor;
    } else {
        cell.layer.borderWidth = 0;
        cell.contentView.backgroundColor = selected ? [PLLauncherAccentColor() colorWithAlphaComponent:0.16] : UIColor.clearColor;
    }
}

void PLApplyLauncherActionButtonChrome(UIButton *button) {
    BOOL outline = getLauncherOutlineControlsEnabled();
    UIColor *accentColor = PLLauncherAccentColor();
    button.layer.cornerRadius = MAX(button.layer.cornerRadius, 5);
    button.layer.borderWidth = outline ? 1.0 : 0.0;
    button.layer.borderColor = (outline ? accentColor : UIColor.clearColor).CGColor;
    button.backgroundColor = outline ? UIColor.clearColor : accentColor;
    button.tintColor = outline ? accentColor : UIColor.whiteColor;
}

void PLApplyLauncherInputChrome(UITextField *textField) {
    BOOL outline = getLauncherOutlineControlsEnabled();
    textField.borderStyle = UITextBorderStyleNone;
    textField.background = nil;
    textField.backgroundColor = UIColor.clearColor;
    textField.layer.cornerRadius = 6;
    textField.layer.borderWidth = outline ? 1.0 : 0.0;
    textField.layer.borderColor = (outline ? [UIColor colorWithWhite:1 alpha:0.22] : UIColor.clearColor).CGColor;
}

CGSize PLCompactPopoverSize(CGFloat width, CGFloat height) {
    return CGSizeMake(clamp(width, 280, 330), clamp(height, 200, 240));
}

CGSize PLCompactSheetSize(CGFloat width, CGFloat height) {
    return CGSizeMake(clamp(width, 540, 700), clamp(height, 320, 520));
}

NSMutableDictionary* parseJSONFromFile(NSString *path) {
    NSError *error;

    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    if (content == nil) {
        NSLog(@"[ParseJSON] Error: could not read %@: %@", path, error.localizedDescription);
        return @{@"NSErrorObject": error}.mutableCopy;
    }

    NSData* data = [content dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
    if (error) {
        NSLog(@"[ParseJSON] Error: could not parse JSON: %@", error.localizedDescription);
        return @{@"NSErrorObject": error}.mutableCopy;
    }
    return dict;
}

NSError* saveJSONToFile(NSDictionary *dict, NSString *path) {
    // TODO: handle rename
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:&error];
    if (jsonData == nil) {
        return error;
    }
    BOOL success = [jsonData writeToFile:path options:NSDataWritingAtomic error:&error];
    if (!success) {
        return error;
    }
    return nil;
}

NSString* localize(NSString* key, NSString* comment) {
    NSString *value = NSLocalizedString(key, nil);
    if (![NSLocale.preferredLanguages[0] isEqualToString:@"en"] && [value isEqualToString:key]) {
        NSString* path = [NSBundle.mainBundle pathForResource:@"en" ofType:@"lproj"];
        NSBundle* languageBundle = [NSBundle bundleWithPath:path];
        value = [languageBundle localizedStringForKey:key value:nil table:nil];

        if ([value isEqualToString:key]) {
            value = [[NSBundle bundleWithIdentifier:@"com.apple.UIKit"] localizedStringForKey:key value:nil table:nil];
        }
    }

    return value;
}

void customNSLog(const char *file, int lineNumber, const char *functionName, NSString *format, ...)
{
    va_list ap; 
    va_start (ap, format);
    NSString *body = [[NSString alloc] initWithFormat:format arguments:ap];
    printf("%s", [body UTF8String]);
    if (![format hasSuffix:@"\n"]) {
        printf("\n");
    }
    va_end (ap);
}

CGFloat MathUtils_dist(CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2) {
    const CGFloat x = (x2 - x1);
    const CGFloat y = (y2 - y1);
    return (CGFloat) hypot(x, y);
}

//Ported from https://www.arduino.cc/reference/en/language/functions/math/map/
CGFloat MathUtils_map(CGFloat x, CGFloat in_min, CGFloat in_max, CGFloat out_min, CGFloat out_max) {
    return (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min;
}

CGFloat dpToPx(CGFloat dp) {
    CGFloat screenScale = [[UIScreen mainScreen] scale];
    return dp * screenScale;
}

CGFloat pxToDp(CGFloat px) {
    CGFloat screenScale = [[UIScreen mainScreen] scale];
    return px / screenScale;
}

void setButtonPointerInteraction(UIButton *button) {
    button.pointerInteractionEnabled = YES;
    button.pointerStyleProvider = ^ UIPointerStyle* (UIButton* button, UIPointerEffect* proposedEffect, UIPointerShape* proposedShape) {
        UITargetedPreview *preview = [[UITargetedPreview alloc] initWithView:button];
        return [NSClassFromString(@"UIPointerStyle") styleWithEffect:[NSClassFromString(@"UIPointerHighlightEffect") effectWithPreview:preview] shape:proposedShape];
    };
}

__attribute__((noinline,optnone,naked))
void* JIT26CreateRegionLegacy(size_t len) {
    asm("brk #0x69 \n"
        "ret");
}
__attribute__((noinline,optnone,naked))
void* JIT26PrepareRegion(void *addr, size_t len) {
    asm("mov x16, #1 \n"
        "brk #0xf00d \n"
        "ret");
}
__attribute__((noinline,optnone,naked))
void BreakSendJITScript(char* script, size_t len) {
   asm("mov x16, #2 \n"
       "brk #0xf00d \n"
       "ret");
}
__attribute__((noinline,optnone,naked))
void JIT26SetDetachAfterFirstBr(BOOL value) {
   asm("mov x16, #3 \n"
       "brk #0xf00d \n"
       "ret");
}
__attribute__((noinline,optnone,naked))
void JIT26PrepareRegionForPatching(void *addr, size_t size) {
   asm("mov x16, #4 \n"
       "brk #0xf00d \n"
       "ret");
}
void JIT26SendJITScript(NSString* script) {
    NSCAssert(script, @"Script must not be nil");
    BreakSendJITScript((char*)script.UTF8String, script.length);
}
BOOL DeviceRequiresTXMWorkaround(void) {
    if (@available(iOS 26.0, *)) {
        DIR *d = opendir("/private/preboot");
        if(!d) return NO;
        struct dirent *dir;
        char txmPath[PATH_MAX];
        while ((dir = readdir(d)) != NULL) {
            if(strlen(dir->d_name) == 96) {
                snprintf(txmPath, sizeof(txmPath), "/private/preboot/%s/usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4", dir->d_name);
                break;
            }
        }
        closedir(d);
        return access(txmPath, F_OK) == 0;
    }
    return NO;
}
