// Local extension: request only NetEase's system media record, including when
// a browser is the global Now Playing app. No UI automation or account data.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "adapter/now_playing.h"
#import "adapter/env.h"
#import "utility/helpers.h"

@interface NSObject (CoteDOsMediaRequest)
+ (id)localOrigin;
+ (id)defaultPlayer;
- (id)initWithOrigin:(id)origin bundleIdentifier:(NSString *)bundle player:(id)player;
- (id)initWithPlayerPath:(id)path;
- (void)requestNowPlayingInfoWithCompletion:(void (^)(NSDictionary *, NSError *))completion;
- (void)requestIsPlayingOnQueue:(dispatch_queue_t)queue completion:(void (^)(BOOL, NSError *))completion;
- (void)requestNowPlayingItemArtworkWithCompletion:(void (^)(id, NSError *))completion;
- (NSData *)imageData;
- (id)initWithDestination:(id)destination;
+ (void)sendCommand:(unsigned int)command toDestination:(id)destination options:(NSDictionary *)options appOptions:(unsigned int)appOptions withCompletion:(id)completion;
@end

NSDictionary *cotedosNeteaseData(void);

// Use the class operation with an explicit destination. An instance controller
// has an asynchronous initial load and can otherwise default to the global route.
void cotedosNeteaseSendOptions(unsigned int command, NSDictionary *options) {
    Class origin = NSClassFromString(@"MROrigin"), player = NSClassFromString(@"MRPlayer");
    Class pathClass = NSClassFromString(@"MRPlayerPath"), destClass = NSClassFromString(@"MRDestination");
    Class controllerClass = NSClassFromString(@"MRNowPlayingController");
    SEL selector = @selector(sendCommand:toDestination:options:appOptions:withCompletion:);
    if (!origin || !player || !pathClass || !destClass || ![controllerClass respondsToSelector:selector])
        fail(@"NetEase targeted media control is unavailable");
    id path = [[pathClass alloc] initWithOrigin:[origin localOrigin]
        bundleIdentifier:@"com.netease.163music" player:[player defaultPlayer]];
    id destination = [[destClass alloc] initWithPlayerPath:path];
    [controllerClass sendCommand:command toDestination:destination options:options appOptions:0 withCompletion:nil];
    // Keep the helper alive for delivery. Confirmation is read in a NEW helper
    // by NeteaseSource.refreshTargeted: MediaRemote can cache a request's state
    // for the lifetime of this process, even after a command has taken effect.
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.6];
    while (deadline.timeIntervalSinceNow > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];

}

void cotedosNeteaseSend(unsigned int command) { cotedosNeteaseSendOptions(command, @{}); }
void cotedosNeteaseSeek(double seconds) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    CFStringRef *key = handle ? (CFStringRef *)dlsym(handle, "kMRMediaRemoteOptionPlaybackPosition") : NULL;
    if (!key || !*key) fail(@"NetEase seeking is unavailable");
    cotedosNeteaseSendOptions(24, @{(__bridge NSString *)*key: @(seconds)});
}

// Dedicated entry points cannot silently fall through to global media controls.
void cotedos_netease_send_env(void) {
    int command = getEnvFuncParamIntSafe(@"cotedos_netease_send", 0, @"value");
    if (command < 0 || command > 6 || command == 3) fail(@"Unsupported NetEase command");
    cotedosNeteaseSend((unsigned int)command);
}
void cotedos_netease_seek_env(void) {
    long micros = getEnvFuncParamLongSafe(@"cotedos_netease_seek", 0, @"value");
    if (micros < 0) fail(@"Negative seek position");
    cotedosNeteaseSeek(micros / 1000000.0);
}

NSDictionary *cotedosNeteaseData(void) {
    Class origin = NSClassFromString(@"MROrigin");
    Class player = NSClassFromString(@"MRPlayer");
    Class pathClass = NSClassFromString(@"MRPlayerPath");
    Class requestClass = NSClassFromString(@"MRNowPlayingRequest");
    if (!origin || !player || !pathClass || !requestClass) return nil;
    id path = [[pathClass alloc] initWithOrigin:[origin localOrigin]
        bundleIdentifier:@"com.netease.163music" player:[player defaultPlayer]];
    id request = [[requestClass alloc] initWithPlayerPath:path];
    if (![request respondsToSelector:@selector(requestNowPlayingInfoWithCompletion:)]) return nil;
    __block NSDictionary *info;
    __block NSData *art;
    __block BOOL playing = NO, infoDone = NO, playingDone = NO, artDone = NO;
    [request requestNowPlayingInfoWithCompletion:^(NSDictionary *value, NSError *error) {
        info = error ? nil : value; infoDone = YES;
    }];
    if ([request respondsToSelector:@selector(requestIsPlayingOnQueue:completion:)]) {
        [request requestIsPlayingOnQueue:dispatch_get_main_queue() completion:^(BOOL value, NSError *error) {
            playing = error ? NO : value; playingDone = YES;
        }];
    } else { playingDone = YES; }
    if ([request respondsToSelector:@selector(requestNowPlayingItemArtworkWithCompletion:)]) {
        [request requestNowPlayingItemArtworkWithCompletion:^(id value, NSError *error) {
            if (!error) {
                if ([value respondsToSelector:@selector(imageData)]) art = [value imageData];
                else if ([value isKindOfClass:[NSData class]]) art = value;
            }
            artDone = YES;
        }];
    } else { artDone = YES; }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1.4];
    while (!(infoDone && playingDone && artDone) && deadline.timeIntervalSinceNow > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    if (!infoDone || !info[@"kMRMediaRemoteNowPlayingInfoTitle"]) return nil;
    NSMutableDictionary *result = convertNowPlayingInformation(info, false, false, false);
    result[@"bundleIdentifier"] = @"com.netease.163music";
    result[@"playing"] = @(playing);
    if (art) result[@"artworkData"] = [art base64EncodedStringWithOptions:0];
    return result;
}
