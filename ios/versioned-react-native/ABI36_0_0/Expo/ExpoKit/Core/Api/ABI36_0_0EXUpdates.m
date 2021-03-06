// Copyright 2016-present 650 Industries. All rights reserved.

#import "ABI36_0_0EXUpdates.h"
#import <ABI36_0_0React/ABI36_0_0RCTUIManager.h>
#import <ABI36_0_0React/ABI36_0_0RCTBridge.h>

NSString * const ABI36_0_0EXUpdatesEventName = @"Exponent.nativeUpdatesEvent";
NSString * const ABI36_0_0EXUpdatesErrorEventType = @"error";
NSString * const ABI36_0_0EXUpdatesNotAvailableEventType = @"noUpdateAvailable";
NSString * const ABI36_0_0EXUpdatesDownloadStartEventType = @"downloadStart";
NSString * const ABI36_0_0EXUpdatesDownloadProgressEventType = @"downloadProgress";
NSString * const ABI36_0_0EXUpdatesDownloadFinishedEventType = @"downloadFinished";

ABI36_0_0EX_DEFINE_SCOPED_MODULE_GETTER(ABI36_0_0EXUpdates, updates)

@interface ABI36_0_0EXUpdates ()

@property (nonatomic, strong) NSDictionary *manifest;

@property (nonatomic, weak) id kernelUpdatesServiceDelegate;

@end

@implementation ABI36_0_0EXUpdates

@synthesize bridge = _bridge;

ABI36_0_0EX_EXPORT_SCOPED_MODULE(ExponentUpdates, UpdatesManager)

- (instancetype)initWithExperienceId:(NSString *)experienceId kernelServiceDelegate:(id)kernelServiceInstance params:(NSDictionary *)params
{
  if (self = [super initWithExperienceId:experienceId kernelServiceDelegate:kernelServiceInstance params:params]) {
    _kernelUpdatesServiceDelegate = kernelServiceInstance;
    _manifest = params[@"manifest"];
  }
  return self;
}

- (void)sendEventWithBody:(NSDictionary *)body
{
  [_bridge enqueueJSCall:@"ABI36_0_0RCTDeviceEventEmitter.emit" args:@[ABI36_0_0EXUpdatesEventName, body]];
}

ABI36_0_0RCT_EXPORT_METHOD(reload)
{
  [_kernelUpdatesServiceDelegate updatesModuleDidSelectReload:self];
}

ABI36_0_0RCT_EXPORT_METHOD(reloadFromCache)
{
  [_kernelUpdatesServiceDelegate updatesModuleDidSelectReloadFromCache:self];
}

ABI36_0_0RCT_EXPORT_METHOD(checkForUpdateAsync:(ABI36_0_0RCTPromiseResolveBlock)resolve
                             rejecter:(ABI36_0_0RCTPromiseRejectBlock)reject)
{
  if ([self _areDevToolsEnabledWithManifest:_manifest]) {
    reject(@"E_CHECK_UPDATE_FAILED", @"Cannot check for updates in dev mode", nil);
    return;
  }
  [_kernelUpdatesServiceDelegate updatesModule:self didRequestManifestWithCacheBehavior:ABI36_0_0EXManifestNoCache success:^(NSDictionary * _Nonnull manifest) {
    NSString *currentRevisionId = self->_manifest[@"revisionId"];
    NSString *newRevisionId = manifest[@"revisionId"];
    if (!currentRevisionId || !newRevisionId) {
      reject(@"E_CHECK_UPDATE_FAILED", @"Revision ID not found in manifest", nil);
      return;
    }
    if ([currentRevisionId isEqualToString:newRevisionId]) {
      resolve(nil);
      return;
    }
    resolve(manifest);
  } failure:^(NSError * _Nonnull error) {
    reject(@"E_CHECK_UPDATE_FAILED", error.localizedDescription, error);
  }];
}

ABI36_0_0RCT_EXPORT_METHOD(fetchUpdateAsync:(ABI36_0_0RCTPromiseResolveBlock)resolve
                          rejecter:(ABI36_0_0RCTPromiseRejectBlock)reject)
{
  if ([self _areDevToolsEnabledWithManifest:_manifest]) {
    [self sendEventWithBody:@{
                               @"type": ABI36_0_0EXUpdatesErrorEventType,
                               @"message": @"Cannot fetch updates in dev mode"
                               }];
    reject(@"E_FETCH_UPDATE_FAILED", @"Cannot fetch updates in dev mode", nil);
    return;
  }
  [_kernelUpdatesServiceDelegate updatesModule:self didRequestManifestWithCacheBehavior:ABI36_0_0EXManifestPrepareToCache success:^(NSDictionary * _Nonnull manifest) {
    NSString *currentRevisionId = self->_manifest[@"revisionId"];
    NSString *newRevisionId = manifest[@"revisionId"];
    if (currentRevisionId && newRevisionId && [currentRevisionId isEqualToString:newRevisionId]) {
      [self sendEventWithBody:@{ @"type": ABI36_0_0EXUpdatesNotAvailableEventType }];
      resolve(nil);
      return;
    }

    void (^progressBlock)(NSDictionary * _Nonnull) = ^void(NSDictionary * _Nonnull progressDict) {
      NSMutableDictionary *eventBody = [progressDict mutableCopy];
      eventBody[@"type"] = ABI36_0_0EXUpdatesDownloadProgressEventType;
      [self sendEventWithBody:eventBody];
    };
    void (^successBlock)(NSData * _Nonnull) = ^void(NSData * _Nonnull data) {
      [self sendEventWithBody:@{
                                 @"type": ABI36_0_0EXUpdatesDownloadFinishedEventType,
                                 @"manifest": manifest
                                 }];
      resolve(manifest);
    };
    void (^errorBlock)(NSError * _Nonnull) = ^void(NSError * _Nonnull error) {
      [self sendEventWithBody:@{
                                 @"type": ABI36_0_0EXUpdatesErrorEventType,
                                 @"message": @"Failed to fetch new update"
                                 }];
      reject(@"E_FETCH_BUNDLE_FAILED", @"Failed to fetch new update", error);
    };

    [self sendEventWithBody:@{ @"type": ABI36_0_0EXUpdatesDownloadStartEventType }];
    [self->_kernelUpdatesServiceDelegate updatesModule:self
                          didRequestBundleWithManifest:manifest
                                              progress:progressBlock
                                               success:successBlock
                                               failure:errorBlock];
  } failure:^(NSError * _Nonnull error) {
    [self sendEventWithBody:@{
                               @"type": ABI36_0_0EXUpdatesErrorEventType,
                               @"message": error.localizedDescription
                               }];
    reject(@"E_CHECK_UPDATE_FAILED", error.localizedDescription, error);
  }];
}

- (BOOL)_areDevToolsEnabledWithManifest:(NSDictionary *)manifest
{
  NSDictionary *manifestDeveloperConfig = manifest[@"developer"];
  BOOL isDeployedFromTool = (manifestDeveloperConfig && manifestDeveloperConfig[@"tool"] != nil);
  return (isDeployedFromTool);
}

@end
