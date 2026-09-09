# appshubcc/Bettbox#450 — ZIP directory entries during backup recovery

- Source: https://github.com/appshubcc/Bettbox/issues/450 (reported 2026-09-09).
- Baseline: Bettbox/Gbox `587d8d4fbcffa4c0327c54d35d3b32b9152be3f1`, application `1.19.1+2026090201`; archive dependency locked to `4.0.9`.
- Status: reproduced and fixed in source; no new application binary has been released by this change.
- Cause: recovery treated ZIP directory entries as writable files. A repacked archive containing `profiles/` throws `FileSystemException: Is a directory` when restoring into an existing profiles directory.
- Change: native and legacy backup recovery share `restoreBackupFiles`, which skips entries with `isFile == false`. File contents and replacement behavior are preserved.
- Regression: `test/common/backup_restore_test.dart` exercises a real ZIP encode/decode with profile/provider directories, file-only replacement, and a raw directory entry without a trailing slash.
- Red: original write loop produced two failing directory tests; file-only test passed.
- Green: all 19 Flutter tests pass; targeted Flutter analysis reports no issues. Tested on macOS with Flutter 3.44.9 / Dart 3.12.2. Android/Windows UI import has not been device-tested.
- Review: independent code review found no blocker; corrected the no-trailing-slash fixture so ZIP encoding cannot silently normalize it.

Before revisiting this issue, run the regression test and check this patch's ancestry. An upstream issue remaining open does not mean this fork is unfixed. Reopen the investigation only for a changed reproduction or a failing regression. Keep source-fix, application-release, and device-verification status separate.
