import 'package:flutter/material.dart';

/// Keeps a set of controllers alive for exactly as long as the subtree that
/// uses them is on screen, and disposes them once it is gone.
///
/// Reach for this whenever a controller is created outside a route — before a
/// `showDialog` or `showModalBottomSheet` call — and used by a field inside
/// it.
///
/// The tempting alternative is to dispose the controller when the future
/// completes:
///
/// ```dart
/// try {
///   await showDialog(...);   // uses `controller`
/// } finally {
///   controller.dispose();    // wrong: too early
/// }
/// ```
///
/// That future resolves the moment the route is *popped*, while the route
/// itself keeps rebuilding all the way through its exit animation. The next
/// rebuild touches a disposed controller and throws in the middle of a build,
/// which leaves the element tree half-updated and takes the rest of the frame
/// with it. What the user sees is a red screen naming `_dependents.isEmpty`
/// or a duplicate `GlobalKey` — assertions from deep in the framework, several
/// frames removed from the line that actually caused them.
///
/// Putting the controllers in the tree makes their lifetime the tree's
/// problem: [State.dispose] runs when the route is genuinely finished, which
/// is the moment we wanted all along.
class ControllerScope extends StatefulWidget {
  const ControllerScope({
    super.key,
    required this.controllers,
    required this.child,
  });

  final List<ChangeNotifier> controllers;
  final Widget child;

  @override
  State<ControllerScope> createState() => _ControllerScopeState();
}

class _ControllerScopeState extends State<ControllerScope> {
  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }
}
