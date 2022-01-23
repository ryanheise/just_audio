/*
 * Copyright (C) 2010 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

//
//  AndroidFFT.h
//
//  Created by Eittipat K on 7/12/2564 BE.
//
//  Original source code from
//  - https://android.googlesource.com/platform/system/media/+/master/audio_utils/fixedfft.cpp
//  - https://android.googlesource.com/platform/frameworks/av/+/android-5.1.1_r18/media/libmedia/Visualizer.cpp


#ifndef AndroidFFT_h
#define AndroidFFT_h

#include <stdio.h>
#include <stdint.h>

#import <Foundation/Foundation.h>

@interface AndroidFFT : NSObject

+(void) doFft:(UInt8*) fft :(UInt8*) waveform :(UInt32) size;

@end

#endif /* AndroidFFT_h */
