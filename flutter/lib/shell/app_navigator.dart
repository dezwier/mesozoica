import 'package:flutter/material.dart';

/// Root navigator for routes shown from widgets above [MaterialApp]'s child
/// (e.g. the global XP badge overlay in [MaterialApp.builder]).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
