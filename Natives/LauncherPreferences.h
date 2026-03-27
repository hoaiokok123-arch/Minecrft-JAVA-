#import <UIKit/UIKit.h>

FOUNDATION_EXPORT NSString * const PLLauncherBackgroundDidChangeNotification;
FOUNDATION_EXPORT NSString * const PLLauncherAppearanceDidChangeNotification;

void loadPreferences(BOOL reset);
void toggleIsolatedPref(BOOL forceEnable);

id getPrefObject(NSString *key);
BOOL getPrefBool(NSString *key);
float getPrefFloat(NSString *key);
NSInteger getPrefInt(NSString *key);

void setPrefObject(NSString *key, id value);
void setPrefBool(NSString *key, BOOL value);
void setPrefFloat(NSString *key, float value);
void setPrefInt(NSString *key, NSInteger value);

void resetWarnings();

BOOL getEntitlementValue(NSString *key);

UIEdgeInsets getDefaultSafeArea();
CGRect getSafeArea(CGRect screenBounds);
void setSafeArea(CGSize screenSize, CGRect safeArea);

NSString* getSelectedJavaHome(NSString* defaultJRETag, int minVersion);

NSArray* getRendererKeys(BOOL containsDefault);
NSArray* getRendererNames(BOOL containsDefault);

NSString *getLauncherBackgroundVideoPath(void);
NSString *getLauncherBackgroundVideoDisplayName(void);
CGFloat getLauncherBackgroundVideoScale(void);
CGFloat getLauncherBackgroundVideoOffsetX(void);
CGFloat getLauncherBackgroundVideoOffsetY(void);
BOOL getLauncherOutlineControlsEnabled(void);
void resetLauncherBackgroundVideoAdjustments(void);
void postLauncherAppearanceDidChange(void);
NSError *setLauncherBackgroundVideoFromURL(NSURL *url);
void clearLauncherBackgroundVideo(void);
