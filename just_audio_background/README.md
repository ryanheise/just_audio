# just_audio_background

This experimental package adds background playback and media notification support to just_audio by using [audio_service](https://pub.dev/packages/audio_service) under the hood. It can be used if your app uses a single `AudioPlayer` instance where notification media controls are to be bound to that instance. If your app requires more flexibility than what this plugin provides, you should use `audio_service` directly instead of `just_audio_background`.



## Setup

Add the `just_audio_background` dependency to your `pubspec.yaml` alongside `just_audio`:

```yaml
dependencies:
  just_audio: any # substitute version number
  just_audio_background: any # substitute version number

```

Then add the following initialization code to your app's `main` method:

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
    id: '1', // must be unique for each media item.
    album: "Album name",
    title: "Song name",
    artUri: Uri.parse('https://example.com/albumart.jpg'),
  ),
),
```

## Android setup

Make the following changes to your project's `AndroidManifest.xml` file:

```xml
<manifest ...>
  <!-- ADD THESE TWO PERMISSIONS -->
  <uses-permission android:name="android.permission.WAKE_LOCK"/>
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
  
  <application ...>
    
    ...
    
    <!-- EDIT THE android:name ATTRIBUTE IN YOUR EXISTING "ACTIVITY" ELEMENT -->
    <activity android:name="com.ryanheise.audioservice.AudioServiceActivity" ...>
      ...
    </activity>
    
    <!-- ADD THIS "SERVICE" element -->
    <service android:name="com.ryanheise.audioservice.AudioService">
      <intent-filter>
        <action android:name="android.media.browse.MediaBrowserService" />
      </intent-filter>
    </service>

    <!-- ADD THIS "RECEIVER" element -->
    <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver" >
      <intent-filter>
        <action android:name="android.intent.action.MEDIA_BUTTON" />
      </intent-filter>
    </receiver> 
  </application>
</manifest>
```

## iOS setup

Insert this in your `Info.plist` file:

```
	<key>UIBackgroundModes</key>
	<array>
		<string>audio</string>
	</array>
```
