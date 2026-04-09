#import <Foundation/Foundation.h>

@interface OpenAIAuthSession : NSObject

+ (instancetype)sharedSession;

- (NSString *)statusSummary;
- (BOOL)isSignedIn;
- (void)startSignInWithCompletion:(void (^)(NSDictionary *result, NSError *error))completion;
- (void)signOut;

@end
