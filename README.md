# just_audio_icy
## Audio Player icy metadata behaviour investigation
### 20-Nov-2022 (Mike Relac)
Added print statements to both AudioPlayer.java and example_radio.dart. Modified example_radio.dart to add WETF to a list of clickable radio urls. WETF is the
station causing the incorrect metadata duplication.
Discovered the following when running example_radio.dart to switch from the first station (radioparadise) to WETF:
- looking at the debug console, onMetadata() is invoked for radioparadise but NOT for WETF.
- example_radio.dart lines 102 to 105 (in the StreamBuilder) are invoked with metadata that is not null, for station WETF, and contains the
  metadata for radioparadise.
- Added System.out.println() to AudioPlayer.onTracksChanged(), lines 233 and 242. This is the only other method I could find using 'metadata'.
When I switched radio stations, these print statements were never invoked, so I'm guessing onTracksChanged() wasn't called.
