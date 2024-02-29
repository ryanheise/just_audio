# just_audio_background

This package plugs into [just_audio](https://pub.dev/packages/just_audio) to add background playback support and remote controls (notification, lock screen, headset buttons, smart watches, Android Auto and CarPlay). It supports the simple use case where an app has a single `AudioPlayer` instance.

If your app has more complex requirements, it is recommended that you instead use the [audio_service](https://pub.dev/packages/audio_service) package directly (which just_audio_background is internally built on). This will give you greater control over which buttons to display in the notification and how you want them to behave, while also allowing you to use multiple audio player instances.

## Setup

Add the `just_audio_background` dependency to your `pubspec.yaml` alongside `just_audio`:

```yaml
dependencies:
  just_audio: any # substitute version number
  just_audio_background: any # substitute version number

```

Then add the following initialization code to your app's `main` method (refer to the API documentation for the complete set of options):

```dart
Future<void> main() async {
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.ryanheise.bg_demo.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
  );
  runApp(MyApp());
}
```

Create your player as normal:

```dart
player = AudioPlayer();
```

Set a `MediaItem` tag on each `IndexedAudioSource` loaded into the player. For example:

```dart
AudioSource.uri(
  Uri.parse('https://example.com/song1.mp3'),
  tag: MediaItem(
    // Specify a unique ID for each media item:
    id: '1',
    // Metadata to display in the notification:
    album: "Album name",
    title: "Song name",
    artUri: Uri.parse('https://example.com/albumart.jpg'),
  ),
),
```

## Android setup

Make the following changes to your project's `AndroidManifest.xml` file:

```xml
<manifest xmlns:tools="http://schemas.android.com/tools" ...>
  <!-- ADD THESE TWO PERMISSIONS -->
  <uses-permission android:name="android.permission.WAKE_LOCK"/>
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
  <!-- ALSO ADD THIS PERMISSION IF TARGETING SDK 34 -->
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
  
  <application ...>
    
    ...
    
    <!-- EDIT THE android:name ATTRIBUTE IN YOUR EXISTING "ACTIVITY" ELEMENT -->
    <activity android:name="com.ryanheise.audioservice.AudioServiceActivity" ...>
      ...
    </activity>
    
    <!-- ADD THIS "SERVICE" element -->
    <service android:name="com.ryanheise.audioservice.AudioService"
        android:foregroundServiceType="mediaPlayback"
        android:exported="true" tools:ignore="Instantiatable">
      <intent-filter>
        <action android:name="android.media.browse.MediaBrowserService" />
      </intent-filter>
    </service>

    <!-- ADD THIS "RECEIVER" element -->
    <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
        android:exported="true" tools:ignore="Instantiatable">
      <intent-filter>
        <action android:name="android.intent.action.MEDIA_BUTTON" />
      </intent-filter>
    </receiver> 
  </application>
</manifest>
```

Note: when targeting Android 12 or above, you must set `android:exported` on each component that has an intent filter (the main activity, the service and the receiver). If the manifest merging process causes `"Instantiable"` lint warnings, use `tools:ignore="Instantiable"` (as above) to suppress them.

If your app has a requirement to use a FragmentActivity, you can replace `AudioServiceActivity` above with `AudioServiceFragmentActivity`. If your app needs to use a custom activity, you can also make your own activity class a subclass of either `AudioServiceActivity` or `AudioServiceFragmentActivity`. For more details on this and other options, refer to the [audio_service setup instructions](https://pub.dev/packages/audio_service).

## iOS setup

Insert this in your `Info.plist` file:

```
	<key>UIBackgroundModes</key>
	<array>
		<string>audio</string>
	</array>
```
