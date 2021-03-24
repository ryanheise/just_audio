#import "JustAudioPlugin.h"
#import "AudioPlayer.h"
#import <AVFoundation/AVFoundation.h>
#include <TargetConditionals.h>

@implementation JustAudioPlugin {
    NSObject<FlutterPluginRegistrar>* _registrar;
    NSMutableDictionary<NSString *, AudioPlayer *> *_players;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel* channel = [FlutterMethodChannel
        methodChannelWithName:@"com.ryanheise.just_audio.methods"
              binaryMessenger:[registrar messenger]];
    JustAudioPlugin* instance = [[JustAudioPlugin alloc] initWithRegistrar:registrar];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    self = [super init];
    NSAssert(self, @"super init cannot be nil");
    _registrar = registrar;
    _players = [[NSMutableDictionary alloc] init];
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([@"init" isEqualToString:call.method]) {
        NSDictionary *request = (NSDictionary *)call.arguments;
        NSString *playerId = request[@"id"];
        if ([_players objectForKey:playerId] != nil) {
            FlutterError *flutterError = [FlutterError errorWithCode:@"error" message:@"Platform player already exists" details:nil];
            result(flutterError);
        } else {
            AudioPlayer* player = [[AudioPlayer alloc] initWithRegistrar:_registrar playerId:playerId];
            [_players setValue:player forKey:playerId];
            result(nil);
        }
    } else if ([@"disposePlayer" isEqualToString:call.method]) {
        NSDictionary *request = (NSDictionary *)call.arguments;
        NSString *playerId = request[@"id"];
        [_players[playerId] dispose];
        [_players setValue:nil forKey:playerId];
        result(@{});
    } else if ([@"disposeAllPlayers" isEqualToString:call.method]) {
        NSArray *disposedPlayers = [self dispose];
        result(@{
            @"disposedPlayers" : disposedPlayers});
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (NSArray*)dispose {
    NSArray *keys = _players.allKeys;
    for (NSString *playerId in _players) {
        [_players[playerId] dispose];
    }
    [_players removeAllObjects];
    return keys;
}

- (void)dealloc {
    [self dispose];
}

@end
