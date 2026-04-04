#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef void (^TouchControllerVibrationHandler)(NSInteger kind);

BOOL TouchControllerShouldEnableForCurrentProfile(void);
BOOL TouchControllerShouldEnableForGameDirectory(NSString *gameDir);
NSString *TouchControllerPrepareSessionForGameDirectory(NSString *gameDir);
void TouchControllerResetSession(void);
BOOL TouchControllerIsSessionEnabled(void);
void TouchControllerSetVibrationHandler(TouchControllerVibrationHandler handler);
BOOL TouchControllerSendAddPointer(uint32_t index, CGFloat x, CGFloat y);
BOOL TouchControllerSendRemovePointer(uint32_t index);
BOOL TouchControllerSendClearPointer(void);
