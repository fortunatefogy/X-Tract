import 'package:flutter/foundation.dart';

/// Lets the shell ask the Library tab to re-lock when it is opened or when the
/// app returns to the foreground while the Library is visible.
class LibraryLockController extends ChangeNotifier {
  LibraryLockController._();

  static final LibraryLockController instance = LibraryLockController._();

  int _epoch = 0;
  int get epoch => _epoch;

  bool authenticating = false;

  bool _active = false;

  /// True only while the Library tab is the one being shown. Prompts must not
  /// appear after the user has navigated to another tab.
  bool get active => _active;

  void setActive(bool value) {
    _active = value;
  }

  void requestLock() {
    _epoch++;
    notifyListeners();
  }
}
