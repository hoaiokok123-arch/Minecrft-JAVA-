#import "TouchControllerProxy.h"

#import <arpa/inet.h>
#include <stdlib.h>
#include <string.h>

#import "LauncherPreferences.h"
#import "PLProfiles.h"
#import "utils.h"

typedef NS_ENUM(uint32_t, TouchControllerMessageType) {
    TouchControllerMessageTypeAdd = 1,
    TouchControllerMessageTypeRemove = 2,
    TouchControllerMessageTypeClear = 3,
    TouchControllerMessageTypeVibrate = 4,
};

typedef struct {
    char *token;
} TouchControllerTransportHandle;

@interface TouchControllerBridge : NSObject

@property(nonatomic, strong) NSMutableArray<NSData *> *launcherToModQueue;
@property(nonatomic, copy) NSString *sessionToken;
@property(nonatomic, copy) TouchControllerVibrationHandler vibrationHandler;
@property(nonatomic) BOOL sessionEnabled;
@property(nonatomic) BOOL modConnected;

- (void)prepareSessionForGameDirectory:(NSString *)gameDir;
- (void)reset;
- (BOOL)validateSessionToken:(NSString *)token;
- (BOOL)isHandleValid:(TouchControllerTransportHandle *)handle;
- (NSData *)dequeueMessageForHandle:(TouchControllerTransportHandle *)handle;
- (BOOL)enqueueLauncherMessage:(NSData *)message;
- (void)handleIncomingModMessage:(NSData *)message;
- (NSString *)currentSessionToken;
- (BOOL)isSessionEnabledValue;
- (void)setVibrationHandlerSafely:(TouchControllerVibrationHandler)handler;
- (void)disconnectCurrentHandle;

@end

@implementation TouchControllerBridge {
    dispatch_queue_t _queue;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("org.amethyst.touchcontroller.bridge", DISPATCH_QUEUE_SERIAL);
        _launcherToModQueue = [NSMutableArray array];
    }
    return self;
}

- (void)prepareSessionForGameDirectory:(NSString *)gameDir {
    BOOL enabled = TouchControllerShouldEnableForGameDirectory(gameDir);
    dispatch_sync(_queue, ^{
        self.sessionEnabled = enabled;
        self.modConnected = NO;
        [self.launcherToModQueue removeAllObjects];
        self.sessionToken = enabled ? [NSString stringWithFormat:@"touchcontroller-%@", [NSUUID UUID].UUIDString.lowercaseString] : nil;
        if (enabled) {
            NSLog(@"[TouchController] Prepared session for %@", gameDir);
        } else {
            NSLog(@"[TouchController] Mod not detected in %@", gameDir);
        }
    });
}

- (void)reset {
    dispatch_sync(_queue, ^{
        self.sessionEnabled = NO;
        self.modConnected = NO;
        self.sessionToken = nil;
        [self.launcherToModQueue removeAllObjects];
    });
}

- (BOOL)validateSessionToken:(NSString *)token {
    __block BOOL valid = NO;
    dispatch_sync(_queue, ^{
        valid = self.sessionEnabled && token.length > 0 && [self.sessionToken isEqualToString:token];
        if (valid) {
            self.modConnected = YES;
            [self.launcherToModQueue removeAllObjects];
        }
    });
    return valid;
}

- (BOOL)isHandleValid:(TouchControllerTransportHandle *)handle {
    if (handle == NULL || handle->token == NULL) {
        return NO;
    }

    NSString *token = [NSString stringWithUTF8String:handle->token];
    __block BOOL valid = NO;
    dispatch_sync(_queue, ^{
        valid = self.sessionEnabled && self.modConnected && token.length > 0 && [self.sessionToken isEqualToString:token];
    });
    return valid;
}

- (NSData *)dequeueMessageForHandle:(TouchControllerTransportHandle *)handle {
    if (![self isHandleValid:handle]) {
        return nil;
    }

    __block NSData *message = nil;
    dispatch_sync(_queue, ^{
        if (self.launcherToModQueue.count > 0) {
            message = self.launcherToModQueue.firstObject;
            [self.launcherToModQueue removeObjectAtIndex:0];
        }
    });
    return message;
}

- (BOOL)enqueueLauncherMessage:(NSData *)message {
    if (message.length == 0 || message.length > UINT8_MAX) {
        return NO;
    }

    __block BOOL queued = NO;
    dispatch_sync(_queue, ^{
        if (!self.sessionEnabled || !self.modConnected) {
            return;
        }
        if (self.launcherToModQueue.count >= 256) {
            [self.launcherToModQueue removeObjectAtIndex:0];
        }
        [self.launcherToModQueue addObject:[message copy]];
        queued = YES;
    });
    return queued;
}

- (void)handleIncomingModMessage:(NSData *)message {
    if (message.length < sizeof(uint32_t)) {
        return;
    }

    uint32_t type = 0;
    [message getBytes:&type length:sizeof(type)];
    type = ntohl(type);

    switch (type) {
        case TouchControllerMessageTypeVibrate: {
            if (message.length < sizeof(uint32_t) + sizeof(int32_t)) {
                return;
            }
            int32_t rawKind = 0;
            [message getBytes:&rawKind range:NSMakeRange(sizeof(uint32_t), sizeof(rawKind))];
            NSInteger kind = (NSInteger)(int32_t)ntohl((uint32_t)rawKind);
            __block TouchControllerVibrationHandler handler = nil;
            dispatch_sync(_queue, ^{
                handler = [self.vibrationHandler copy];
            });
            if (handler) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    handler(kind);
                });
            }
            break;
        }

        default:
            break;
    }
}

- (NSString *)currentSessionToken {
    __block NSString *token = nil;
    dispatch_sync(_queue, ^{
        token = [self.sessionToken copy];
    });
    return token;
}

- (BOOL)isSessionEnabledValue {
    __block BOOL enabled = NO;
    dispatch_sync(_queue, ^{
        enabled = self.sessionEnabled;
    });
    return enabled;
}

- (void)setVibrationHandlerSafely:(TouchControllerVibrationHandler)handler {
    dispatch_sync(_queue, ^{
        self.vibrationHandler = [handler copy];
    });
}

- (void)disconnectCurrentHandle {
    dispatch_sync(_queue, ^{
        self.modConnected = NO;
        [self.launcherToModQueue removeAllObjects];
    });
}

@end

static TouchControllerBridge *TouchControllerSharedBridge(void) {
    static TouchControllerBridge *bridge;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bridge = [TouchControllerBridge new];
    });
    return bridge;
}

static NSString *TouchControllerResolveCurrentProfileGameDirectory(void) {
    NSString *instanceName = getPrefObject(@"general.game_directory");
    if (instanceName.length == 0) {
        instanceName = @"default";
    }

    NSString *profileGameDir = [PLProfiles resolveKeyForCurrentProfile:@"gameDir"];
    if (profileGameDir.length == 0) {
        profileGameDir = @".";
    }

    return [[NSString stringWithFormat:@"%s/instances/%@/%@",
        getenv("POJAV_HOME"), instanceName, profileGameDir] stringByStandardizingPath];
}

static BOOL TouchControllerLooksEnabledJar(NSString *fileName) {
    if (fileName.length == 0) {
        return NO;
    }

    NSString *lowercaseName = fileName.lowercaseString;
    return [lowercaseName containsString:@"touchcontroller"] && [lowercaseName hasSuffix:@".jar"];
}

static void TouchControllerAppendUInt32(NSMutableData *data, uint32_t value) {
    uint32_t networkValue = htonl(value);
    [data appendBytes:&networkValue length:sizeof(networkValue)];
}

static void TouchControllerAppendFloat(NSMutableData *data, float value) {
    uint32_t rawValue = 0;
    memcpy(&rawValue, &value, sizeof(rawValue));
    rawValue = htonl(rawValue);
    [data appendBytes:&rawValue length:sizeof(rawValue)];
}

static NSData *TouchControllerCreatePointerMessage(TouchControllerMessageType type, uint32_t index, CGFloat x, CGFloat y) {
    NSMutableData *data = [NSMutableData data];
    TouchControllerAppendUInt32(data, type);

    if (type == TouchControllerMessageTypeAdd) {
        TouchControllerAppendUInt32(data, index);
        TouchControllerAppendFloat(data, (float)x);
        TouchControllerAppendFloat(data, (float)y);
    } else if (type == TouchControllerMessageTypeRemove) {
        TouchControllerAppendUInt32(data, index);
    }

    return data;
}

static void TouchControllerThrow(JNIEnv *env, const char *className, const char *message) {
    jclass exceptionClass = (*env)->FindClass(env, className);
    if (exceptionClass != NULL) {
        (*env)->ThrowNew(env, exceptionClass, message);
    }
}

static void TouchControllerThrowException(JNIEnv *env, const char *message) {
    TouchControllerThrow(env, "java/lang/RuntimeException", message);
}

static void TouchControllerThrowNullPointer(JNIEnv *env, const char *message) {
    TouchControllerThrow(env, "java/lang/NullPointerException", message);
}

BOOL TouchControllerShouldEnableForCurrentProfile(void) {
    return TouchControllerShouldEnableForGameDirectory(TouchControllerResolveCurrentProfileGameDirectory());
}

BOOL TouchControllerShouldEnableForGameDirectory(NSString *gameDir) {
    if (gameDir.length == 0) {
        return NO;
    }

    NSString *modsDirectory = [gameDir stringByAppendingPathComponent:@"mods"];
    NSArray<NSString *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:modsDirectory error:nil];
    for (NSString *fileName in files) {
        if (TouchControllerLooksEnabledJar(fileName)) {
            return YES;
        }
    }
    return NO;
}

NSString *TouchControllerPrepareSessionForGameDirectory(NSString *gameDir) {
    TouchControllerBridge *bridge = TouchControllerSharedBridge();
    [bridge prepareSessionForGameDirectory:gameDir];
    return [bridge currentSessionToken];
}

void TouchControllerResetSession(void) {
    [TouchControllerSharedBridge() reset];
}

BOOL TouchControllerIsSessionEnabled(void) {
    return [TouchControllerSharedBridge() isSessionEnabledValue];
}

void TouchControllerSetVibrationHandler(TouchControllerVibrationHandler handler) {
    [TouchControllerSharedBridge() setVibrationHandlerSafely:handler];
}

BOOL TouchControllerSendAddPointer(uint32_t index, CGFloat x, CGFloat y) {
    return [TouchControllerSharedBridge() enqueueLauncherMessage:
        TouchControllerCreatePointerMessage(TouchControllerMessageTypeAdd, index, clamp(x, 0.0, 1.0), clamp(y, 0.0, 1.0))];
}

BOOL TouchControllerSendRemovePointer(uint32_t index) {
    return [TouchControllerSharedBridge() enqueueLauncherMessage:
        TouchControllerCreatePointerMessage(TouchControllerMessageTypeRemove, index, 0.0, 0.0)];
}

BOOL TouchControllerSendClearPointer(void) {
    NSMutableData *data = [NSMutableData data];
    TouchControllerAppendUInt32(data, TouchControllerMessageTypeClear);
    return [TouchControllerSharedBridge() enqueueLauncherMessage:data];
}

JNIEXPORT void JNICALL Java_top_fifthlight_touchcontroller_common_platform_ios_Transport_init(JNIEnv *env, jclass clazz) {
}

JNIEXPORT jlong JNICALL Java_top_fifthlight_touchcontroller_common_platform_ios_Transport_new(JNIEnv *env, jclass clazz, jstring path) {
    if (path == NULL) {
        TouchControllerThrowNullPointer(env, "Path is null");
        return 0;
    }

    const char *pathChars = (*env)->GetStringUTFChars(env, path, NULL);
    if (pathChars == NULL) {
        TouchControllerThrowException(env, "Failed to read session token");
        return 0;
    }

    NSString *token = [NSString stringWithUTF8String:pathChars];
    (*env)->ReleaseStringUTFChars(env, path, pathChars);

    if (![TouchControllerSharedBridge() validateSessionToken:token]) {
        TouchControllerThrowException(env, "TouchController session is not available");
        return 0;
    }

    TouchControllerTransportHandle *handle = calloc(1, sizeof(TouchControllerTransportHandle));
    if (handle == NULL) {
        TouchControllerThrowException(env, "Failed to allocate TouchController handle");
        return 0;
    }

    handle->token = strdup(token.UTF8String);
    if (handle->token == NULL) {
        free(handle);
        TouchControllerThrowException(env, "Failed to copy TouchController session token");
        return 0;
    }

    return (jlong)handle;
}

JNIEXPORT jint JNICALL Java_top_fifthlight_touchcontroller_common_platform_ios_Transport_receive(JNIEnv *env, jclass clazz, jlong handleValue, jbyteArray buffer) {
    if (buffer == NULL) {
        TouchControllerThrowNullPointer(env, "Buffer is null");
        return 0;
    }

    TouchControllerTransportHandle *handle = (TouchControllerTransportHandle *)handleValue;
    if (![TouchControllerSharedBridge() isHandleValid:handle]) {
        TouchControllerThrowNullPointer(env, "TouchController handle is invalid");
        return 0;
    }

    NSData *message = [TouchControllerSharedBridge() dequeueMessageForHandle:handle];
    if (message.length == 0) {
        return 0;
    }

    jsize bufferLength = (*env)->GetArrayLength(env, buffer);
    if (bufferLength < (jsize)message.length) {
        TouchControllerThrowException(env, "TouchController buffer is too small");
        return -1;
    }

    (*env)->SetByteArrayRegion(env, buffer, 0, (jsize)message.length, (const jbyte *)message.bytes);
    if ((*env)->ExceptionCheck(env)) {
        return -1;
    }

    return (jint)message.length;
}

JNIEXPORT void JNICALL Java_top_fifthlight_touchcontroller_common_platform_ios_Transport_send(JNIEnv *env, jclass clazz, jlong handleValue, jbyteArray buffer, jint off, jint len) {
    if (buffer == NULL) {
        TouchControllerThrowNullPointer(env, "Buffer is null");
        return;
    }

    TouchControllerTransportHandle *handle = (TouchControllerTransportHandle *)handleValue;
    if (![TouchControllerSharedBridge() isHandleValid:handle]) {
        TouchControllerThrowNullPointer(env, "TouchController handle is invalid");
        return;
    }

    jsize bufferLength = (*env)->GetArrayLength(env, buffer);
    if (off < 0 || len <= 0 || off + len > bufferLength || len > UINT8_MAX) {
        TouchControllerThrowException(env, "Bad TouchController message bounds");
        return;
    }

    NSMutableData *message = [NSMutableData dataWithLength:(NSUInteger)len];
    (*env)->GetByteArrayRegion(env, buffer, off, len, message.mutableBytes);
    if ((*env)->ExceptionCheck(env)) {
        return;
    }

    [TouchControllerSharedBridge() handleIncomingModMessage:message];
}

JNIEXPORT void JNICALL Java_top_fifthlight_touchcontroller_common_platform_ios_Transport_destroy(JNIEnv *env, jclass clazz, jlong handleValue) {
    TouchControllerTransportHandle *handle = (TouchControllerTransportHandle *)handleValue;
    if (handle == NULL) {
        TouchControllerThrowNullPointer(env, "TouchController handle is null");
        return;
    }

    [TouchControllerSharedBridge() disconnectCurrentHandle];

    free(handle->token);
    free(handle);
}
