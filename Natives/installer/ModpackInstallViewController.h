#import <UIKit/UIKit.h>

typedef NS_ENUM(NSUInteger, ModrinthInstallMode) {
    ModrinthInstallModeModpack = 0,
    ModrinthInstallModeMod,
    ModrinthInstallModeResourcePack,
    ModrinthInstallModeDataPack,
    ModrinthInstallModeShader
};

@interface ModpackInstallViewController : UITableViewController<UISearchResultsUpdating>
@property(nonatomic) ModrinthInstallMode installMode;
@property(nonatomic, copy) NSString *installDestinationPath;
@end
