#import <SafariServices/SafariServices.h>
#import <AudioToolbox/AudioToolbox.h>
#import <objc/runtime.h>

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
        cell.detailTextLabel.textColor = PLLauncherGlassSecondaryTextColor();
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

UIColor *PLLauncherGlassPrimaryTextColor(void) {
    return [UIColor colorWithWhite:0.08 alpha:0.92];
}

UIColor *PLLauncherGlassSecondaryTextColor(void) {
    return [UIColor colorWithWhite:0.2 alpha:0.62];
}

UIColor *PLLauncherGlassIconTintColor(void) {
    return [UIColor colorWithWhite:0.1 alpha:0.68];
}

static const NSInteger kPLLauncherPreservedEffectTag = 0x504C4753;
static void *kPLLauncherButtonFeedbackKey = &kPLLauncherButtonFeedbackKey;

@interface PLLauncherButtonFeedbackTarget : NSObject
@end

@implementation PLLauncherButtonFeedbackTarget

- (void)handleTouchDown:(UIButton *)sender {
    PLAnimateLauncherPressView(sender, YES);
}

- (void)handleTouchUp:(UIButton *)sender {
    PLAnimateLauncherPressView(sender, NO);
}

- (void)handlePrimaryAction:(UIButton *)sender {
    PLPlayLauncherClickFeedback();
    PLAnimateLauncherPressView(sender, NO);
}

@end

@interface PLLauncherLensCardBackgroundView : UIView

@property(nonatomic) NSDirectionalEdgeInsets insets;
@property(nonatomic) CGFloat cornerRadius;
@property(nonatomic) BOOL emphasized;
@property(nonatomic) UIView *glassView;
@property(nonatomic) UIVisualEffectView *blurView;
@property(nonatomic) UIView *tintView;
@property(nonatomic) CAGradientLayer *topHighlightLayer;
@property(nonatomic) CAGradientLayer *coolTintLayer;
@property(nonatomic) CAGradientLayer *bottomShadeLayer;

- (instancetype)initWithInsets:(NSDirectionalEdgeInsets)insets cornerRadius:(CGFloat)cornerRadius emphasized:(BOOL)emphasized;

@end

@implementation PLLauncherLensCardBackgroundView

- (instancetype)initWithInsets:(NSDirectionalEdgeInsets)insets cornerRadius:(CGFloat)cornerRadius emphasized:(BOOL)emphasized {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.tag = kPLLauncherPreservedEffectTag;
        self.insets = insets;
        self.cornerRadius = cornerRadius;
        self.emphasized = emphasized;
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = NO;
        self.clipsToBounds = NO;

        self.glassView = [UIView new];
        self.glassView.backgroundColor = UIColor.clearColor;
        self.glassView.userInteractionEnabled = NO;
        self.glassView.clipsToBounds = YES;
        [self addSubview:self.glassView];

        UIBlurEffect *effect;
        if (@available(iOS 13.0, *)) {
            effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight];
        } else {
            effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleExtraLight];
        }
        self.blurView = [[UIVisualEffectView alloc] initWithEffect:effect];
        self.blurView.userInteractionEnabled = NO;
        [self.glassView addSubview:self.blurView];

        self.tintView = [UIView new];
        self.tintView.userInteractionEnabled = NO;
        [self.glassView addSubview:self.tintView];

        self.topHighlightLayer = [CAGradientLayer layer];
        self.topHighlightLayer.startPoint = CGPointMake(0.5, 0.0);
        self.topHighlightLayer.endPoint = CGPointMake(0.5, 1.0);
        [self.glassView.layer addSublayer:self.topHighlightLayer];

        self.coolTintLayer = [CAGradientLayer layer];
        self.coolTintLayer.startPoint = CGPointMake(0.0, 0.0);
        self.coolTintLayer.endPoint = CGPointMake(1.0, 1.0);
        [self.glassView.layer addSublayer:self.coolTintLayer];

        self.bottomShadeLayer = [CAGradientLayer layer];
        self.bottomShadeLayer.startPoint = CGPointMake(0.5, 0.58);
        self.bottomShadeLayer.endPoint = CGPointMake(0.5, 1.0);
        [self.glassView.layer addSublayer:self.bottomShadeLayer];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGRect glassFrame = UIEdgeInsetsInsetRect(self.bounds, UIEdgeInsetsMake(
        self.insets.top, self.insets.leading, self.insets.bottom, self.insets.trailing));
    self.glassView.frame = glassFrame;
    self.glassView.layer.cornerRadius = self.cornerRadius;
    if (@available(iOS 13.0, *)) {
        self.glassView.layer.cornerCurve = kCACornerCurveContinuous;
    }

    self.layer.shadowColor = [UIColor colorWithRed:8/255.0 green:22/255.0 blue:38/255.0 alpha:1.0].CGColor;
    self.layer.shadowOpacity = self.emphasized ? 0.04 : 0.022;
    self.layer.shadowRadius = self.emphasized ? 21 : 14;
    self.layer.shadowOffset = CGSizeMake(0, self.emphasized ? 9 : 4);
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:glassFrame cornerRadius:self.cornerRadius].CGPath;

    self.blurView.frame = self.glassView.bounds;
    self.blurView.alpha = self.emphasized ? 0.965 : 0.92;
    self.tintView.frame = self.glassView.bounds;
    self.tintView.backgroundColor = self.emphasized ?
        [UIColor colorWithRed:248/255.0 green:252/255.0 blue:255/255.0 alpha:0.22] :
        [UIColor colorWithRed:242/255.0 green:249/255.0 blue:255/255.0 alpha:0.14];

    self.topHighlightLayer.frame = self.glassView.bounds;
    self.topHighlightLayer.colors = @[
        (__bridge id)[UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:(self.emphasized ? 0.38 : 0.28)].CGColor,
        (__bridge id)[UIColor colorWithRed:243/255.0 green:251/255.0 blue:1.0 alpha:(self.emphasized ? 0.15 : 0.095)].CGColor,
        (__bridge id)UIColor.clearColor.CGColor
    ];
    self.topHighlightLayer.locations = @[@0.0, @0.13, @0.36];

    self.coolTintLayer.frame = self.glassView.bounds;
    self.coolTintLayer.colors = @[
        (__bridge id)[UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:(self.emphasized ? 0.16 : 0.11)].CGColor,
        (__bridge id)[UIColor colorWithRed:229/255.0 green:243/255.0 blue:1.0 alpha:(self.emphasized ? 0.10 : 0.06)].CGColor,
        (__bridge id)[UIColor colorWithRed:190/255.0 green:224/255.0 blue:246/255.0 alpha:(self.emphasized ? 0.09 : 0.055)].CGColor
    ];
    self.coolTintLayer.locations = @[@0.0, @0.48, @1.0];

    self.bottomShadeLayer.frame = self.glassView.bounds;
    self.bottomShadeLayer.colors = @[
        (__bridge id)UIColor.clearColor.CGColor,
        (__bridge id)[UIColor colorWithRed:8/255.0 green:24/255.0 blue:42/255.0 alpha:(self.emphasized ? 0.024 : 0.014)].CGColor
    ];
    self.bottomShadeLayer.locations = @[@0.0, @1.0];
}

@end

static void PLClearLauncherBackdropRecursive(UIView *view) {
    if (!view) {
        return;
    }

    if (view.tag == kPLLauncherPreservedEffectTag) {
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

UIView *PLCreateLauncherLensChromeBackground(NSDirectionalEdgeInsets insets, CGFloat cornerRadius, BOOL emphasized) {
    return [[PLLauncherLensCardBackgroundView alloc] initWithInsets:insets cornerRadius:cornerRadius emphasized:emphasized];
}

static void PLInstallLauncherLensSurface(UIView *host, NSDirectionalEdgeInsets insets, CGFloat cornerRadius, BOOL emphasized) {
    if (!host) {
        return;
    }

    for (UIView *subview in host.subviews.copy) {
        if ([subview isKindOfClass:PLLauncherLensCardBackgroundView.class]) {
            [subview removeFromSuperview];
        }
    }

    UIView *surface = PLCreateLauncherLensChromeBackground(insets, cornerRadius, emphasized);
    surface.frame = host.bounds;
    surface.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    host.backgroundColor = UIColor.clearColor;
    host.opaque = NO;
    host.clipsToBounds = NO;
    host.layer.masksToBounds = NO;
    [host insertSubview:surface atIndex:0];
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
    NSDirectionalEdgeInsets glassInsets = NSDirectionalEdgeInsetsMake(
        MAX(insets.top + 2.0, 2.0),
        insets.leading + 3.0,
        MAX(insets.bottom + 2.0, 2.0),
        insets.trailing + 3.0
    );

    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.clipsToBounds = NO;
    cell.layer.masksToBounds = NO;
    cell.layer.cornerRadius = cornerRadius;
    cell.layer.shadowColor = UIColor.blackColor.CGColor;
    cell.layer.shadowOpacity = selected ? 0.08 : 0.045;
    cell.layer.shadowRadius = selected ? 14 : 10;
    cell.layer.shadowOffset = CGSizeMake(0, selected ? 6 : 4);
    cell.backgroundConfiguration = nil;
    cell.backgroundView = PLCreateLauncherLensChromeBackground(glassInsets, cornerRadius, selected);
    cell.selectedBackgroundView = PLCreateLauncherLensChromeBackground(glassInsets, cornerRadius, YES);
    cell.tintColor = PLLauncherGlassIconTintColor();
    cell.imageView.tintColor = PLLauncherGlassIconTintColor();
    if (cell.textLabel) {
        cell.textLabel.textColor = PLLauncherGlassPrimaryTextColor();
    }
    if (cell.detailTextLabel) {
        cell.detailTextLabel.textColor = PLLauncherGlassSecondaryTextColor();
    }
}

void PLPlayLauncherClickFeedback(void) {
    static UISelectionFeedbackGenerator *selectionFeedback;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (@available(iOS 10.0, *)) {
            selectionFeedback = [UISelectionFeedbackGenerator new];
            [selectionFeedback prepare];
        }
    });

    if (@available(iOS 10.0, *)) {
        [selectionFeedback selectionChanged];
        [selectionFeedback prepare];
    }
    AudioServicesPlaySystemSound(1104);
}

void PLAnimateLauncherPressView(UIView *view, BOOL pressed) {
    if (!view) {
        return;
    }

    [UIView animateWithDuration:(pressed ? 0.09 : 0.18)
                          delay:0
         usingSpringWithDamping:(pressed ? 1.0 : 0.82)
          initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        view.transform = pressed ? CGAffineTransformMakeScale(0.982, 0.982) : CGAffineTransformIdentity;
        view.alpha = pressed ? 0.94 : 1.0;
    } completion:nil];
}

void PLApplyLauncherSelectableCellState(UITableViewCell *cell, BOOL pressed) {
    if (!cell) {
        return;
    }

    PLAnimateLauncherPressView(cell, pressed);
    [UIView animateWithDuration:(pressed ? 0.09 : 0.16)
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        cell.layer.shadowOpacity = pressed ? 0.09 : (cell.isSelected ? 0.08 : 0.045);
    } completion:nil];
}

static void PLInstallLauncherButtonFeedback(UIButton *button) {
    if (!button || objc_getAssociatedObject(button, kPLLauncherButtonFeedbackKey)) {
        return;
    }

    PLLauncherButtonFeedbackTarget *target = [PLLauncherButtonFeedbackTarget new];
    objc_setAssociatedObject(button, kPLLauncherButtonFeedbackKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [button addTarget:target action:@selector(handleTouchDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [button addTarget:target action:@selector(handleTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    [button addTarget:target action:@selector(handlePrimaryAction:) forControlEvents:UIControlEventPrimaryActionTriggered];
}

void PLApplyLauncherActionButtonChrome(UIButton *button) {
    UIColor *accentColor = PLLauncherAccentColor();
    UIColor *foregroundColor = button.buttonType == UIButtonTypeSystem ?
        accentColor : PLLauncherGlassPrimaryTextColor();
    CGFloat cornerRadius = MAX(button.layer.cornerRadius, 10);
    button.layer.cornerRadius = cornerRadius;
    button.layer.masksToBounds = NO;
    button.layer.borderWidth = 0.0;
    button.layer.borderColor = UIColor.clearColor.CGColor;
    button.layer.shadowOpacity = 0.0;
    PLInstallLauncherLensSurface(button, NSDirectionalEdgeInsetsZero, cornerRadius, YES);
    button.backgroundColor = UIColor.clearColor;
    button.tintColor = foregroundColor;
    [button setTitleColor:foregroundColor forState:UIControlStateNormal];
    [button setTitleColor:[foregroundColor colorWithAlphaComponent:0.45] forState:UIControlStateDisabled];
    PLInstallLauncherButtonFeedback(button);
}

void PLApplyLauncherInputChrome(UITextField *textField) {
    CGFloat cornerRadius = MAX(textField.layer.cornerRadius, 10);
    textField.borderStyle = UITextBorderStyleNone;
    textField.background = nil;
    textField.backgroundColor = UIColor.clearColor;
    textField.layer.cornerRadius = cornerRadius;
    textField.layer.borderWidth = 0.0;
    textField.layer.borderColor = UIColor.clearColor.CGColor;
    textField.layer.shadowOpacity = 0.0;
    textField.textColor = PLLauncherGlassPrimaryTextColor();
    textField.tintColor = PLLauncherAccentColor();
    if (textField.placeholder.length > 0) {
        textField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:textField.placeholder attributes:@{
            NSForegroundColorAttributeName: [PLLauncherGlassSecondaryTextColor() colorWithAlphaComponent:0.8]
        }];
    }
    PLInstallLauncherLensSurface(textField, NSDirectionalEdgeInsetsZero, cornerRadius, NO);
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
