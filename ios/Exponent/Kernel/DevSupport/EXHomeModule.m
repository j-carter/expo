// Copyright 2015-present 650 Industries. All rights reserved.

#import "EXEnvironment.h"
#import "EXHomeModule.h"
#import "EXSession.h"
#import "EXUnversioned.h"
#import "EXClientReleaseType.h"

#import <React/RCTEventDispatcher.h>

@interface EXHomeModule ()

@property (nonatomic, assign) BOOL hasListeners;
@property (nonatomic, strong) NSMutableDictionary *eventSuccessBlocks;
@property (nonatomic, strong) NSMutableDictionary *eventFailureBlocks;
@property (nonatomic, strong) NSArray * _Nonnull sdkVersions;
@property (nonatomic, weak) id<EXHomeModuleDelegate> delegate;

@end

@implementation EXHomeModule

+ (NSString *)moduleName { return @"ExponentKernel"; }

- (instancetype)initWithExperienceId:(NSString *)experienceId kernelServiceDelegate:(id)kernelServiceInstance params:(NSDictionary *)params
{
  if (self = [super initWithExperienceId:experienceId kernelServiceDelegate:kernelServiceInstance params:params]) {
    _eventSuccessBlocks = [NSMutableDictionary dictionary];
    _eventFailureBlocks = [NSMutableDictionary dictionary];
    _sdkVersions = params[@"constants"][@"supportedExpoSdks"];
    _delegate = kernelServiceInstance;
  }
  return self;
}

+ (BOOL)requiresMainQueueSetup
{
  return NO;
}

- (NSDictionary *)constantsToExport
{
  return @{ @"sdkVersions": _sdkVersions,
            @"IOSClientReleaseType": [EXClientReleaseType clientReleaseType] };
}

#pragma mark - RCTEventEmitter methods

- (NSArray<NSString *> *)supportedEvents
{
  return @[];
}

/**
 *  Override this method to avoid the [self supportedEvents] validation
 */
- (void)sendEventWithName:(NSString *)eventName body:(id)body
{
  // Note that this could be a versioned bridge!
  [self.bridge enqueueJSCall:@"RCTDeviceEventEmitter.emit"
                        args:body ? @[eventName, body] : @[eventName]];
}

#pragma mark -

- (void)dispatchJSEvent:(NSString *)eventName body:(NSDictionary *)eventBody onSuccess:(void (^)(NSDictionary *))success onFailure:(void (^)(NSString *))failure
{
  NSString *qualifiedEventName = [NSString stringWithFormat:@"ExponentKernel.%@", eventName];
  NSMutableDictionary *qualifiedEventBody = (eventBody) ? [eventBody mutableCopy] : [NSMutableDictionary dictionary];
  
  if (success && failure) {
    NSString *eventId = [[NSUUID UUID] UUIDString];
    [_eventSuccessBlocks setObject:success forKey:eventId];
    [_eventFailureBlocks setObject:failure forKey:eventId];
    [qualifiedEventBody setObject:eventId forKey:@"eventId"];
  }
  
  [self sendEventWithName:qualifiedEventName body:qualifiedEventBody];
}

/**
 * Requests JavaScript side to start closing the dev menu (start the animation or so).
 * Fully closes the dev menu once it receives a response from that event.
 */
- (void)requestToCloseDevMenu
{
  __weak typeof(self) weakSelf = self;
  void (^close)(id) = ^(id arg){
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (strongSelf->_delegate) {
      [strongSelf->_delegate homeModuleDidSelectCloseMenu:strongSelf];
    }
  };
  [self dispatchJSEvent:@"requestToCloseDevMenu" body:nil onSuccess:close onFailure:close];
}

/**
 *  Duplicates Linking.openURL but does not validate that this is an exponent URL;
 *  in other words, we just take your word for it and never hand it off to iOS.
 *  Used by the home screen URL bar.
 */
RCT_EXPORT_METHOD(openURL:(NSURL *)URL
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(__unused RCTPromiseRejectBlock)reject)
{
  if (URL) {
    [_delegate homeModule:self didOpenUrl:URL.absoluteString];
    resolve(@YES);
  } else {
    NSError *err = [NSError errorWithDomain:EX_UNVERSIONED(@"EXKernelErrorDomain") code:-1 userInfo:@{ NSLocalizedDescriptionKey: @"Cannot open a nil url" }];
    reject(@"E_INVALID_URL", err.localizedDescription, err);
  }
}

/**
 * Returns boolean value determining whether the current app supports developer tools.
 */
RCT_REMAP_METHOD(doesCurrentTaskEnableDevtoolsAsync,
                 doesCurrentTaskEnableDevtoolsWithResolver:(RCTPromiseResolveBlock)resolve
                 reject:(RCTPromiseRejectBlock)reject)
{
  if (_delegate) {
    resolve(@([_delegate homeModuleShouldEnableDevtools:self]));
  } else {
    // don't reject, just disable devtools
    resolve(@NO);
  }
}

RCT_REMAP_METHOD(isLegacyMenuBehaviorEnabledAsync,
                 isLegacyMenuBehaviorEnabledWithResolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
  if (_delegate) {
    resolve(@([_delegate homeModuleShouldEnableLegacyMenuBehavior:self]));
  } else {
    resolve(@(NO));
  }
}

RCT_EXPORT_METHOD(setIsLegacyMenuBehaviorEnabledAsync:(BOOL)isEnabled)
{
  if (_delegate) {
    [_delegate homeModule:self didSelectEnableLegacyMenuBehavior:isEnabled];
  }
}

/**
 * Gets a dictionary of dev menu options available in the currently shown experience,
 * If the experience doesn't support developer tools just returns an empty response.
 */
RCT_REMAP_METHOD(getDevMenuItemsToShowAsync,
                 getDevMenuItemsToShowWithResolver:(RCTPromiseResolveBlock)resolve
                 reject:(RCTPromiseRejectBlock)reject)
{
  if (_delegate && [_delegate homeModuleShouldEnableDevtools:self]) {
    resolve([_delegate devMenuItemsForHomeModule:self]);
  } else {
    // don't reject, just show no devtools
    resolve(@{});
  }
}

/**
 * Function called every time the dev menu option is selected.
 */
RCT_EXPORT_METHOD(selectDevMenuItemWithKeyAsync:(NSString *)key)
{
  if (_delegate) {
    [_delegate homeModule:self didSelectDevMenuItemWithKey:key];
  }
}

/**
 * Reloads currently shown app with the manifest.
 */
RCT_EXPORT_METHOD(reloadAppAsync)
{
  if (_delegate) {
    [_delegate homeModuleDidSelectRefresh:self];
  }
}

/**
 * Immediately closes the dev menu if it's visible.
 * Note: It skips the animation that would have been applied by the JS side.
 */
RCT_EXPORT_METHOD(closeDevMenuAsync)
{
  if (_delegate) {
    [_delegate homeModuleDidSelectCloseMenu:self];
  }
}

/**
 * Goes back to the home app.
 */
RCT_EXPORT_METHOD(goToHomeAsync)
{
  if (_delegate) {
    [_delegate homeModuleDidSelectGoToHome:self];
  }
}

/**
 * Opens QR scanner to open another app by scanning its QR code.
 */
RCT_EXPORT_METHOD(selectQRReader)
{
  if (_delegate) {
    [_delegate homeModuleDidSelectQRReader:self];
  }
}

RCT_REMAP_METHOD(getSessionAsync,
                 getSessionAsync:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
  NSDictionary *session = [[EXSession sharedInstance] session];
  resolve(session);
}

RCT_REMAP_METHOD(setSessionAsync,
                 setSessionAsync:(NSDictionary *)session
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
  NSError *error;
  BOOL success = [[EXSession sharedInstance] saveSessionToKeychain:session error:&error];
  if (success) {
    resolve(nil);
  } else {
    reject(@"ERR_SESSION_NOT_SAVED", @"Could not save session", error);
  }
}

RCT_REMAP_METHOD(removeSessionAsync,
                 removeSessionAsync:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
  NSError *error;
  BOOL success = [[EXSession sharedInstance] deleteSessionFromKeychainWithError:&error];
  if (success) {
    resolve(nil);
  } else {
    reject(@"ERR_SESSION_NOT_REMOVED", @"Could not remove session", error);
  }
}

/**
 * Checks whether the dev menu onboarding is already finished.
 * Onboarding is a screen that shows the dev menu to the user that opens any experience for the first time.
*/
RCT_REMAP_METHOD(getIsOnboardingFinishedAsync,
                 getIsOnboardingFinishedWithResolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
  if (_delegate) {
    BOOL isFinished = [_delegate homeModuleShouldFinishNux:self];
    resolve(@(isFinished));
  } else {
    resolve(@(NO));
  }
}

/**
 * Sets appropriate setting in user defaults that user's onboarding has finished.
 */
RCT_REMAP_METHOD(setIsOnboardingFinishedAsync,
                 setIsOnboardingFinished:(BOOL)isOnboardingFinished)
{
  if (_delegate) {
    [_delegate homeModule:self didFinishNux:isOnboardingFinished];
  }
}

/**
 * Called when the native event has succeeded on the JS side.
 */
RCT_REMAP_METHOD(onEventSuccess,
                 eventId:(NSString *)eventId
                 body:(NSDictionary *)body)
{
  void (^success)(NSDictionary *) = [_eventSuccessBlocks objectForKey:eventId];
  if (success) {
    success(body);
    [_eventSuccessBlocks removeObjectForKey:eventId];
    [_eventFailureBlocks removeObjectForKey:eventId];
  }
}

/**
 * Called when the native event has failed on the JS side.
 */
RCT_REMAP_METHOD(onEventFailure,
                 eventId:(NSString *)eventId
                 message:(NSString *)message)
{
  void (^failure)(NSString *) = [_eventFailureBlocks objectForKey:eventId];
  if (failure) {
    failure(message);
    [_eventSuccessBlocks removeObjectForKey:eventId];
    [_eventFailureBlocks removeObjectForKey:eventId];
  }
}

@end
