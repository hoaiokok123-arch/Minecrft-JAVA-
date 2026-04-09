#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, AIModDoctorRunMode) {
    AIModDoctorRunModeAnalyzeOnly = 0,
    AIModDoctorRunModeAutoRepair
};

@interface AIModDoctorService : NSObject

@property(nonatomic, copy) NSDictionary *profile;
@property(nonatomic, copy) NSString *profileName;
@property(nonatomic, copy) NSString *instanceDirectory;
@property(nonatomic, copy) NSString *gameDirectory;
@property(nonatomic, copy) NSString *sharedModsDirectory;
@property(nonatomic, copy) void (^eventHandler)(NSString *event);

- (void)runWithMode:(AIModDoctorRunMode)mode
         completion:(void (^)(NSString *summary, NSError *error))completion;

@end
