// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library vm_service_client.breakpoint;

import 'dart:async';

import 'package:async/async.dart';
import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:json_rpc_2/error_code.dart' as rpc_error;

import 'exceptions.dart';
import 'object.dart';
import 'scope.dart';
import 'sentinel.dart';
import 'utils.dart';

VMBreakpoint newVMBreakpoint(Scope scope, Map json) {
  if (json == null) return null;
  assert(json["type"] == "Breakpoint");
  return new VMBreakpoint._(scope, json);
}

/// A debugger breakpoint.
///
/// A breakpoint corresponds to a location in the source file. Before the
/// isolate would execute that location, it pauses.
///
/// Unlike most [VMObject]s, this has no corresponding [VMObjectRef] type. The
/// full metadata is always available.
class VMBreakpoint extends VMObject {
  final Scope _scope;

  /// The ID for this breakpoint, which is unique relative to its isolate.
  final String _id;

  /// Whether [_id] is guaranteed to be the same for different VM service
  /// instance objects that refer to the same breakpoint.
  final bool _fixedId;

  final int size;

  /// The number of this breakpoint.
  ///
  /// This number is user-visible.
  final int number;

  /// A stream that emits a copy of [this] each time it causes the isolate to
  /// become paused.
  Stream<VMBreakpoint> get onPause => _onPause;
  Stream<VMBreakpoint> _onPause;

  /// A future that fires when this breakpoint is removed.
  ///
  /// If the breakpoint is already removed, this will complete immediately.
  Future get onRemove => _onRemoveMemo.runOnce(() async {
    await _scope.getInState(_scope.streams.debug, () async {
      try {
        await load();
        return false;
      } on VMSentinelException catch (_) {
        return true;
      }
    }, (json) {
      return json["kind"] == "BreakpointRemoved" &&
          json["breakpoint"]["id"] == _id;
    });
  });
  final _onRemoveMemo = new AsyncMemoizer();

  VMBreakpoint._(Scope scope, Map json)
      : _scope = scope,
        _id = json["id"],
        _fixedId = json["fixedId"] ?? false,
        size = json["size"],
        number = json["breakpointNumber"] {
    _onPause = transform(_scope.streams.debug, (json, sink) {
      if (json["isolate"]["id"] != _scope.isolateId) return;
      if (json["kind"] != "PauseBreakpoint") return;

      for (var breakpoint in json["pauseBreakpoints"]) {
        if (breakpoint["id"] != _id) continue;
        sink.add(newVMBreakpoint(_scope, breakpoint));
        break;
      }
    });
  }

  Future<VMBreakpoint> load() async {
    try {
      return newVMBreakpoint(_scope, await _scope.loadObject(_id));
    } on rpc.RpcException catch (error) {
      if (error.code != rpc_error.INVALID_PARAMS) rethrow;

      // Work around sdk#24247.
      throw new VMSentinelException(VMSentinel.expired);
    }
  }

  /// Removes this breakpoint.
  Future remove() =>
      _scope.sendRequest("removeBreakpoint", {"breakpointId": _id});

  bool operator ==(other) => other is VMBreakpoint &&
      (_fixedId ? _id == other._id : super == other);

  int get hashCode => _fixedId ? _id.hashCode : super.hashCode;

  String toString() => "breakpoint #$number";
}
