#import <Foundation/Foundation.h>

@interface OpenAIAuthSession : NSObject

+ (instancetype)sharedSession;

- (NSString *)statusSummary;
- (BOOL)isSignedIn;
- (BOOL)hasPendingManualSignIn;
- (NSString *)pendingManualSignInURL;
- (NSString *)prepareManualSignInURLWithError:(NSError **)error;
- (BOOL)completeManualSignInWithCallbackURLString:(NSString *)callbackURLString error:(NSError **)error;
- (void)startSignInWithCompletion:(void (^)(NSDictionary *result, NSError *error))completion;
- (void)signOut;

@end
