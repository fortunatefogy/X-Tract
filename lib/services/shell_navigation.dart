import 'package:flutter/foundation.dart';

class ShellNavigation {
  static final ShellNavigation instance = ShellNavigation._();

  ShellNavigation._();

  final ValueNotifier<int?> requestedTab = ValueNotifier<int?>(null);

  void openTab(int index) => requestedTab.value = index;

  void consume() => requestedTab.value = null;
}
