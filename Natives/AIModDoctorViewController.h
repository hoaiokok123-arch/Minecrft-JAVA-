#import <UIKit/UIKit.h>

@interface AIModDoctorViewController : UIViewController

@property(nonatomic, copy) NSDictionary *profile;
@property(nonatomic, copy) NSString *profileName;
@property(nonatomic, copy) NSString *instanceDirectory;
@property(nonatomic, copy) NSString *gameDirectory;
@property(nonatomic, copy) NSString *sharedModsDirectory;

@end
