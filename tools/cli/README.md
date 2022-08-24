# Development tools

### Swift development

**Problem**

Native `macos` and `ios` projects share most of the code. Sadly, CocoaPods does not allow to
reference files outside of the root project directory, or to symlink `.swift` files.

This would force us to duplicate the code between `macos` and `ios` implementations with cut &
paste.

**Solution**

A simple script that watches a source folder (say `darwin`) and copies the files to the correct
folder. Of course this means that most of future ios/macos developments will need to happen inside
the source folder.

**How to**
Launch the script inside `tools/cli/lib`. Say you are in the root of the repository it would be

```bash
dart run ./tools/cli/lib/sync_darwin_folder.dart
```