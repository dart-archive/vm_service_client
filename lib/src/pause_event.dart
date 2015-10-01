// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library vm_service_client.pause_event;

import 'scope.dart';

VMPauseEvent newVMPauseEvent(Scope scope, Map json) {
  if (json == null) return null;

  assert(json["type"] == "Event");
  switch (json["kind"]) {
    case "PauseStart": return new VMPauseStartEvent._(scope, json);
    case "PauseExit": return new VMPauseExitEvent._(scope, json);
    case "PauseBreakpoint": return new VMPauseBreakpointEvent._(scope, json);
    case "PauseInterrupted": return new VMPauseInterruptedEvent._(scope, json);
    case "PauseException": return new VMPauseExceptionEvent._(scope, json);
    case "Resume": return new VMResumeEvent._(scope, json);
    default: return null;
  }
}

/// An event indicating that an isolate has been paused or resumed.
abstract class VMPauseEvent {
  /// The time at which the event fired.
  ///
  /// This is only available in version 3.0 or greater of the VM service
  /// protocol.
  final DateTime time;

  VMPauseEvent._(Scope scope, Map json)
      : time = json["timestamp"] == null
            ? new DateTime.fromMillisecondsSinceEpoch(json["timestamp"])
            : null;
}

/// An event indicating that an isolate was paused as it started, before it
/// executed any code.
class VMPauseStartEvent extends VMPauseEvent {
  VMPauseStartEvent._(Scope scope, Map json)
      : super._(scope, json);

  String toString() => "pause before start";
}

/// An event indicating that an isolate was paused as it exited, before it
/// terminated.
class VMPauseExitEvent extends VMPauseEvent {
  VMPauseExitEvent._(Scope scope, Map json)
      : super._(scope, json);

  String toString() => "pause before exit";
}

/// An event indicating that an isolate was paused at a breakpoint or due to
/// stepping through code.
class VMPauseBreakpointEvent extends VMPauseEvent {
  VMPauseBreakpointEvent._(Scope scope, Map json)
      : super._(scope, json);

  String toString() => "pause at breakpoint";
}

/// An event indicating that an isolate was paused due to an interruption.
///
/// This usually means its process received `SIGQUIT`.
class VMPauseInterruptedEvent extends VMPauseEvent {
  VMPauseInterruptedEvent._(Scope scope, Map json)
      : super._(scope, json);

  String toString() => "pause on interrupt";
}

/// An event indicating that an isolate was paused due to an exception.
/// An event indicating that an isolate was paused due to an exception.
class VMPauseExceptionEvent extends VMPauseEvent {
  VMPauseExceptionEvent._(Scope scope, Map json)
      : super._(scope, json);

  String toString() => "pause on exception";
}

/// An event indicating that an isolate was unpaused.
class VMResumeEvent extends VMPauseEvent {
  VMResumeEvent._(Scope scope, Map json)
      : super._(scope, json);

  String toString() => "resume";
}
