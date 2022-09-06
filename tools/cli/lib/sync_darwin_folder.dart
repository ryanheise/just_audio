import 'dart:core';
import 'dart:io';

import "package:path/path.dart" show dirname;
import 'package:watcher/watcher.dart';

void main(List<String> arguments) {
  watch(
    sourceFolder: "just_audio/darwin",
    destinationFolders: [
      "just_audio/macos",
      "just_audio/ios",
    ],
  );
}

/// Watches files changes (add, modify and remove) inside the [sourceFolder], and aligns accordingly
/// the [destinationFolders] files. Both [sourceFolder] and [destinationFolders] are supposed to be relative paths to the directory you want to operate with.
///
/// Throws a [FileSystemException] if [sourceFolder] does not exist.
void watch({
  required String sourceFolder,
  required List<String> destinationFolders,
}) {
  final currentDir = dirname(Platform.script.path).dropLastSlash();
  final baseDir = "$currentDir/../../..";
  final destinationDirs = destinationFolders.map((it) {
    return "$baseDir/${it.dropLastSlash()}";
  });
  final watcher = DirectoryWatcher("$baseDir/$sourceFolder");

  watcher.events.listen((event) {
    final partialPath = event.path.replaceAll("$baseDir/$sourceFolder", "");

    print("Updating $partialPath");

    switch (event.type) {
      case ChangeType.ADD:
      case ChangeType.MODIFY:
        final file = File(event.path);
        for (final destination in destinationDirs) {
          file.copySync("$destination$partialPath");
        }
        break;
      case ChangeType.REMOVE:
        for (var element in destinationDirs) {
          final file = File("$element$partialPath");
          file.deleteSync(recursive: file is Directory);
        }
    }
  });

  print("🫣 Watching files 🫣");
}

extension StringPathClean on String {
  String dropLastSlash() {
    if (endsWith("/")) {
      return substring(0, length - 1);
    }

    return this;
  }
}
