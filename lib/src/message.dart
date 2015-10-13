// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library vm_service_client.message;

import 'dart:async';

import 'instance.dart';
import 'scope.dart';

VMMessage newVMMessage(Scope scope, Map json) {
  if (json == null) return null;
  assert(json["type"] == "Message");
  return new VMMessage._(scope, json);
}

/// A pending message to the current isolate.
class VMMessage {
  final Scope _scope;

  /// The ID of the message's payload.
  final String _objectId;

  /// The index in the isolate's message queue.
  ///
  /// The message with the index of 0 will be processed next.
  final int index;

  /// An advisory name describing the message.
  final String name;

  final int size;

  VMMessage._(Scope scope, Map json)
      : _scope = scope,
        _objectId = json["messageObjectId"],
        index = json["index"],
        name = json["name"],
        size = json["size"];

  /// Loads the message's payload.
  ///
  /// This will throw a [VMSentinelException] if the value has expired.
  Future<VMInstance> loadValue() async =>
      newVMInstance(_scope, await _scope.loadObject(_objectId));

  String toString() => name;
}
