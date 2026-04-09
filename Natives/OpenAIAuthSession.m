#import "OpenAIAuthSession.h"

#import <AuthenticationServices/AuthenticationServices.h>
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import <arpa/inet.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <unistd.h>

#import "LauncherPreferences.h"
#import "utils.h"

static NSString *const OpenAIAuthDefaultClientID = @"app_EMoamEEZ73f0CkXaXp7hrann";
static NSString *const OpenAIAuthDefaultOriginator = @"opencode";
static NSString *const OpenAIAuthAuthorizeURL = @"https://auth.openai.com/api/oauth/oauth2/auth";
static NSString *const OpenAIAuthRedirectScheme = @"amethyst";
static NSString *const OpenAIAuthRedirectHost = @"openai-auth";
static NSUInteger const OpenAIAuthLoopbackPort = 1455;

@interface OpenAIAuthSession()<ASWebAuthenticationPresentationContextProviding>
@property(nonatomic) ASWebAuthenticationSession *authSession;
@property(nonatomic) dispatch_queue_t serverQueue;
@property(nonatomic) dispatch_source_t acceptSource;
@property(nonatomic) int listenSocket;
@property(nonatomic, copy) NSString *expectedState;
@property(nonatomic, copy) NSString *codeVerifier;
@property(nonatomic, copy) void (^completionHandler)(NSDictionary *result, NSError *error);
@end

@implementation OpenAIAuthSession

+ (instancetype)sharedSession {
    static OpenAIAuthSession *sharedSession;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedSession = [OpenAIAuthSession new];
    });
    return sharedSession;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _listenSocket = -1;
        _serverQueue = dispatch_queue_create("org.amethyst.openai.auth", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (NSString *)statusSummary {
    if ([self isSignedIn]) {
        NSString *timestamp = [getPrefObject(@"ai.oauth_signed_in_at") description];
        if (timestamp.length > 0) {
            return [NSString stringWithFormat:localize(@"openai_auth.status.signed_in_at", nil), timestamp];
        }
        return localize(@"openai_auth.status.signed_in", nil);
    }
    return localize(@"openai_auth.status.signed_out", nil);
}

- (BOOL)isSignedIn {
    return getPrefBool(@"ai.oauth_signed_in");
}

- (void)startSignInWithCompletion:(void (^)(NSDictionary *result, NSError *error))completion {
    if (self.authSession != nil) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"OpenAIAuthSession"
                                                code:1
                                            userInfo:@{NSLocalizedDescriptionKey: localize(@"openai_auth.error.busy", nil)}]);
        }
        return;
    }

    self.completionHandler = completion;
    self.expectedState = [self randomBase64URLStringOfLength:32];
    self.codeVerifier = [self randomBase64URLStringOfLength:48];

    NSError *serverError = nil;
    if (![self startLoopbackServer:&serverError]) {
        [self finishWithResult:nil error:serverError ?: [NSError errorWithDomain:@"OpenAIAuthSession"
                                                                            code:2
                                                                        userInfo:@{NSLocalizedDescriptionKey: localize(@"openai_auth.error.server", nil)}]];
        return;
    }

    NSURL *url = [self authorizeURL];
    self.authSession = [[ASWebAuthenticationSession alloc] initWithURL:url
                                                     callbackURLScheme:OpenAIAuthRedirectScheme
                                                     completionHandler:^(NSURL * _Nullable callbackURL, NSError * _Nullable error) {
        NSDictionary *result = nil;
        NSError *resultError = error;
        if (callbackURL) {
            result = [self parsedQueryItemsFromURL:callbackURL];
            if (![result[@"state"] isEqualToString:self.expectedState]) {
                result = nil;
                resultError = [NSError errorWithDomain:@"OpenAIAuthSession"
                                                  code:3
                                              userInfo:@{NSLocalizedDescriptionKey: localize(@"openai_auth.error.state", nil)}];
            } else if (result[@"code"]) {
                [self storeSuccessfulResult:result callbackURL:callbackURL];
            } else if (result[@"error_description"]) {
                resultError = [NSError errorWithDomain:@"OpenAIAuthSession"
                                                  code:4
                                              userInfo:@{NSLocalizedDescriptionKey: result[@"error_description"]}];
            }
        } else if (error.code == ASWebAuthenticationSessionErrorCodeCanceledLogin) {
            resultError = [NSError errorWithDomain:@"OpenAIAuthSession"
                                              code:5
                                          userInfo:@{NSLocalizedDescriptionKey: localize(@"openai_auth.error.cancelled", nil)}];
        }

        [self stopLoopbackServer];
        self.authSession = nil;
        [self finishWithResult:result error:resultError];
    }];
    self.authSession.presentationContextProvider = self;
    self.authSession.prefersEphemeralWebBrowserSession = NO;

    if (![self.authSession start]) {
        [self stopLoopbackServer];
        self.authSession = nil;
        [self finishWithResult:nil error:[NSError errorWithDomain:@"OpenAIAuthSession"
                                                             code:6
                                                         userInfo:@{NSLocalizedDescriptionKey: localize(@"openai_auth.error.start", nil)}]];
    }
}

- (void)signOut {
    [self.authSession cancel];
    self.authSession = nil;
    [self stopLoopbackServer];
    setPrefBool(@"ai.oauth_signed_in", NO);
    setPrefObject(@"ai.oauth_authorization_code", nil);
    setPrefObject(@"ai.oauth_callback_url", nil);
    setPrefObject(@"ai.oauth_signed_in_at", nil);
}

#pragma mark Auth request

- (NSURL *)authorizeURL {
    NSString *clientId = [getPrefObject(@"ai.oauth_client_id") description];
    clientId = [clientId stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (clientId.length == 0) {
        clientId = OpenAIAuthDefaultClientID;
    }

    NSString *originator = [getPrefObject(@"ai.oauth_originator") description];
    originator = [originator stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (originator.length == 0) {
        originator = OpenAIAuthDefaultOriginator;
    }

    NSURLComponents *components = [NSURLComponents componentsWithString:OpenAIAuthAuthorizeURL];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"client_id" value:clientId],
        [NSURLQueryItem queryItemWithName:@"code_challenge" value:[self codeChallengeFromVerifier:self.codeVerifier]],
        [NSURLQueryItem queryItemWithName:@"code_challenge_method" value:@"S256"],
        [NSURLQueryItem queryItemWithName:@"codex_cli_simplified_flow" value:@"true"],
        [NSURLQueryItem queryItemWithName:@"id_token_add_organizations" value:@"true"],
        [NSURLQueryItem queryItemWithName:@"originator" value:originator],
        [NSURLQueryItem queryItemWithName:@"redirect_uri" value:[self loopbackRedirectURI]],
        [NSURLQueryItem queryItemWithName:@"response_type" value:@"code"],
        [NSURLQueryItem queryItemWithName:@"scope" value:@"openid profile email offline_access"],
        [NSURLQueryItem queryItemWithName:@"state" value:self.expectedState]
    ];
    return components.URL;
}

- (NSString *)loopbackRedirectURI {
    return [NSString stringWithFormat:@"http://localhost:%lu/auth/callback", (unsigned long)OpenAIAuthLoopbackPort];
}

- (void)storeSuccessfulResult:(NSDictionary *)result callbackURL:(NSURL *)callbackURL {
    setPrefBool(@"ai.oauth_signed_in", YES);
    setPrefObject(@"ai.oauth_authorization_code", result[@"code"]);
    setPrefObject(@"ai.oauth_callback_url", callbackURL.absoluteString);
    setPrefObject(@"ai.oauth_signed_in_at", [self isoTimestamp]);
}

- (NSString *)isoTimestamp {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    return [formatter stringFromDate:[NSDate date]];
}

- (NSDictionary *)parsedQueryItemsFromURL:(NSURL *)url {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSArray<NSURLQueryItem *> *queryItems = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems;
    for (NSURLQueryItem *item in queryItems) {
        result[item.name] = item.value ?: @"";
    }
    return result;
}

- (NSString *)randomBase64URLStringOfLength:(NSUInteger)length {
    NSMutableData *data = [NSMutableData dataWithLength:length];
    SecRandomCopyBytes(kSecRandomDefault, data.length, data.mutableBytes);
    return [self base64URLStringFromData:data];
}

- (NSString *)codeChallengeFromVerifier:(NSString *)verifier {
    NSData *data = [verifier dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    return [self base64URLStringFromData:[NSData dataWithBytes:digest length:sizeof(digest)]];
}

- (NSString *)base64URLStringFromData:(NSData *)data {
    NSString *value = [data base64EncodedStringWithOptions:0];
    value = [value stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    value = [value stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    value = [value stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return value;
}

#pragma mark Loopback server

- (BOOL)startLoopbackServer:(NSError **)error {
    [self stopLoopbackServer];

    int serverSocket = socket(AF_INET, SOCK_STREAM, 0);
    if (serverSocket < 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"OpenAIAuthSession"
                                         code:10
                                     userInfo:@{NSLocalizedDescriptionKey: localize(@"openai_auth.error.server", nil)}];
        }
        return NO;
    }

    int yes = 1;
    setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons((uint16_t)OpenAIAuthLoopbackPort);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    if (bind(serverSocket, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(serverSocket, 4) != 0) {
        close(serverSocket);
        if (error) {
            *error = [NSError errorWithDomain:@"OpenAIAuthSession"
                                         code:11
                                     userInfo:@{NSLocalizedDescriptionKey: localize(@"openai_auth.error.port_in_use", nil)}];
        }
        return NO;
    }

    self.listenSocket = serverSocket;
    self.acceptSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)serverSocket, 0, self.serverQueue);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(self.acceptSource, ^{
        __strong typeof(weakSelf) self = weakSelf;
        int clientSocket = accept(self.listenSocket, NULL, NULL);
        if (clientSocket >= 0) {
            [self handleClientSocket:clientSocket];
        }
    });
    dispatch_source_set_cancel_handler(self.acceptSource, ^{
        if (serverSocket >= 0) {
            close(serverSocket);
        }
    });
    dispatch_resume(self.acceptSource);
    return YES;
}

- (void)stopLoopbackServer {
    if (self.acceptSource) {
        dispatch_source_cancel(self.acceptSource);
        self.acceptSource = nil;
    } else if (self.listenSocket >= 0) {
        close(self.listenSocket);
    }
    self.listenSocket = -1;
}

- (void)handleClientSocket:(int)clientSocket {
    NSMutableData *requestData = [NSMutableData data];
    char buffer[4096];
    ssize_t bytesRead = recv(clientSocket, buffer, sizeof(buffer), 0);
    if (bytesRead > 0) {
        [requestData appendBytes:buffer length:(NSUInteger)bytesRead];
    }

    NSString *request = [[NSString alloc] initWithData:requestData encoding:NSUTF8StringEncoding] ?: @"";
    NSString *firstLine = [request componentsSeparatedByString:@"\r\n"].firstObject ?: @"";
    NSArray<NSString *> *parts = [firstLine componentsSeparatedByString:@" "];
    NSString *path = parts.count > 1 ? parts[1] : @"/";
    NSURL *requestURL = [NSURL URLWithString:[@"http://localhost" stringByAppendingString:path]];
    NSDictionary *queryItems = requestURL ? [self parsedQueryItemsFromURL:requestURL] : @{};

    NSURLComponents *redirectComponents = [NSURLComponents new];
    redirectComponents.scheme = OpenAIAuthRedirectScheme;
    redirectComponents.host = OpenAIAuthRedirectHost;
    redirectComponents.path = @"/callback";

    NSMutableArray<NSURLQueryItem *> *redirectQueryItems = [NSMutableArray array];
    for (NSString *key in @[@"code", @"state", @"error", @"error_description"]) {
        NSString *value = queryItems[key];
        if (value.length > 0) {
            [redirectQueryItems addObject:[NSURLQueryItem queryItemWithName:key value:value]];
        }
    }
    redirectComponents.queryItems = redirectQueryItems;

    NSString *location = redirectComponents.URL.absoluteString;
    if (location.length == 0) {
        location = [NSString stringWithFormat:@"%@://%@/callback", OpenAIAuthRedirectScheme, OpenAIAuthRedirectHost];
    }

    NSString *response = [NSString stringWithFormat:
        @"HTTP/1.1 302 Found\r\n"
        @"Content-Length: 0\r\n"
        @"Connection: close\r\n"
        @"Location: %@\r\n\r\n",
        location];
    const char *utf8 = response.UTF8String;
    send(clientSocket, utf8, (int)[response lengthOfBytesUsingEncoding:NSUTF8StringEncoding], 0);
    close(clientSocket);
}

#pragma mark Helpers

- (void)finishWithResult:(NSDictionary *)result error:(NSError *)error {
    void (^completion)(NSDictionary *result, NSError *error) = self.completionHandler;
    self.completionHandler = nil;
    self.expectedState = nil;
    self.codeVerifier = nil;

    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(result, error);
        });
    }
}

#pragma mark ASWebAuthenticationPresentationContextProviding

- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }

        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows) {
            if (window.isKeyWindow) {
                return window;
            }
        }
        if (windowScene.windows.firstObject) {
            return windowScene.windows.firstObject;
        }
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

@end
