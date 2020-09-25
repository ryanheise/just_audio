//
// Generated file. Do not edit.
//

// ignore: unused_import
import 'dart:ui';

import 'package:audio_session/audio_session_web.dart';
import 'package:just_audio/just_audio_web.dart';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

// ignore: public_member_api_docs
void registerPlugins(PluginRegistry registry) {
  AudioSessionWeb.registerWith(registry.registrarFor(AudioSessionWeb));
  JustAudioPlugin.registerWith(registry.registrarFor(JustAudioPlugin));
  registry.registerMessageHandler();
}
