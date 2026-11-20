#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(MiNaNative, NSObject)
RCT_EXTERN_METHOD(prepare:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(invoke:(NSString *)method params:(NSDictionary *)params resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
@end
