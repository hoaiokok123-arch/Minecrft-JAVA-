#import <UIKit/UIKit.h>

static inline UIColor *LauncherAccentColor(void) {
    return [UIColor colorWithRed:121/255.0 green:56/255.0 blue:162/255.0 alpha:1.0];
}

static inline UIColor *LauncherPanelColor(void) {
    return UIColor.secondarySystemGroupedBackgroundColor;
}

static inline UIColor *LauncherPanelMutedColor(void) {
    return UIColor.tertiarySystemGroupedBackgroundColor;
}

static inline UIColor *LauncherOutlineColor(void) {
    return [UIColor colorWithWhite:1.0 alpha:0.06];
}

static inline UIFont *LauncherTitleFont(CGFloat size) {
    return [UIFont systemFontOfSize:size weight:UIFontWeightSemibold];
}

static inline UIFont *LauncherBodyFont(CGFloat size) {
    return [UIFont systemFontOfSize:size weight:UIFontWeightRegular];
}

static inline UIFont *LauncherCaptionFont(CGFloat size) {
    return [UIFont systemFontOfSize:size weight:UIFontWeightMedium];
}

static inline UIImageSymbolConfiguration *LauncherSymbolConfig(CGFloat size) {
    return [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIFontWeightSemibold scale:UIImageSymbolScaleMedium];
}

static inline void LauncherStylePanel(UIView *view, CGFloat radius) {
    view.backgroundColor = LauncherPanelColor();
    view.layer.cornerRadius = radius;
    view.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    view.layer.borderColor = LauncherOutlineColor().CGColor;
    if ([view.layer respondsToSelector:@selector(setCornerCurve:)]) {
        view.layer.cornerCurve = kCACornerCurveContinuous;
    }
}

static inline void LauncherStyleField(UITextField *field) {
    field.borderStyle = UITextBorderStyleNone;
    field.backgroundColor = LauncherPanelMutedColor();
    field.layer.cornerRadius = 12.0;
    field.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    field.layer.borderColor = LauncherOutlineColor().CGColor;
    field.font = LauncherBodyFont(14.0);
    if ([field.layer respondsToSelector:@selector(setCornerCurve:)]) {
        field.layer.cornerCurve = kCACornerCurveContinuous;
    }

    UIView *paddingView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
    field.leftView = paddingView;
    field.leftViewMode = UITextFieldViewModeAlways;
}
