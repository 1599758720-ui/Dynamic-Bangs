// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#include "private/MediaRemote.h"
#include <limits.h>

#import <Foundation/Foundation.h>

#import "MediaRemoteAdapter.h"
#import "adapter/env.h"
#import "adapter/globals.h"
#import "adapter/now_playing.h"
#import "utility/helpers.h"

void adapter_seek(long position) {

    if (position < 0) {
        failf(@"Negative values are not allowed: %d", position);
    }

    g_mediaRemote.setElapsedTime(position / 1000000.0);

    waitForCommandCompletion();
}

static inline long seek_0_position() {
    return getEnvFuncParamLongSafe(@"adapter_seek", 0, @"position");
}

extern void cotedosNeteaseSeek(double seconds);
void adapter_seek_env() {
    long position = seek_0_position();
    if (getEnvOption(@"netease") != nil) {
        if (position < 0) fail(@"Negative seek position");
        cotedosNeteaseSeek(position / 1000000.0);
    } else { adapter_seek(position); }
}
