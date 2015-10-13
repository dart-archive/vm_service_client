// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library vm_service_client.stack;

import 'dart:collection';

import 'frame.dart';
import 'message.dart';
import 'scope.dart';

VMStack newVMStack(Scope scope, Map json) {
  if (json == null) return null;
  assert(json["type"] == "Stack");
  return new VMStack._(scope, json);
}

/// The current execution stack and message queue for an isolate.
class VMStack {
  /// The current execution stack.
  ///
  /// The earlier a frame appears in this list, the closer to the current point
  /// of execution. This will be empty if the isolate is not currently executing
  /// any Dart code.
  final List<VMFrame> frames;

  /// The current message queue.
  ///
  /// The earlier a message appears in this list, the earlier it will be
  /// processed.
  final List<VMMessage> messages;

  VMStack._(Scope scope, Map json)
      : frames = new UnmodifiableListView(json["frames"]
            .map((frame) => newVMFrame(scope, frame))
            .toList()),
        messages = new UnmodifiableListView(json["messages"]
            .map((message) => newVMMessage(scope, message))
            .toList());
}
