// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library vm_service_client.isolate;

import 'dart:async';

import 'package:json_rpc_2/json_rpc_2.dart' as rpc;

import 'exceptions.dart';
import 'scope.dart';
import 'sentinel.dart';

VMIsolateRef newVMIsolateRef(rpc.Peer peer, Map json) {
  if (json == null) return null;
  assert(json["type"] == "@Isolate" || json["type"] == "Isolate");
  var scope = new Scope(peer, json["id"]);
  return new VMIsolateRef._(scope, json);
}

/// A reference to an isolate on the remote VM.
///
/// The full isolate with additional metadata can be loaded using [load].
class VMIsolateRef {
  final Scope _scope;

  /// A unique numeric ID for this isolate.
  ///
  /// Note that this may be larger than can be represented in Dart
  /// implementations that compile to JS; it's generally safer to use
  /// [numberAsString] instead.
  final int number;

  /// The string representation of [number].
  final String numberAsString;

  /// A name identifying this isolate for debugging.
  ///
  /// This isn't guaranteed to be unique. It can be set using [setName].
  final String name;

  VMIsolateRef._(this._scope, Map json)
      : number = int.parse(json["number"]),
        numberAsString = json["number"],
        name = json["name"];

  /// Loads the full representation of this isolate.
  ///
  /// Throws a [VMSentinelException] if this isolate is no longer available.
  Future<VMIsolate> load() async {
    var response = await _scope.sendRequest("getIsolate");

    // Work around sdk#24142.
    if (response["type"] == "Error") {
      throw new VMSentinelException(VMSentinel.collected);
    } else if (response["type"] == "Sentinel") {
      throw new VMSentinelException(newVMSentinel(response));
    } else {
      return new VMIsolate._(_scope, response);
    }
  }

  /// Pauses this isolate.
  ///
  /// The returned future may complete before the isolate is paused.
  Future pause() async {
    await _scope.sendRequest("pause");
  }

  /// Resumes execution of this isolate, if it's paused.
  ///
  /// [step] controls how execution proceeds; it defaults to [VMStep.resume].
  ///
  /// Throws an [rpc.RpcException] if the isolate isn't paused.
  Future resume({VMStep step}) {
    if (step == null) step = VMStep.resume;
    return _scope.sendRequest("resume",
        step == VMStep.resume ? {} : {"step": step._value});
  }

  /// Sets the [name] of the isolate.
  ///
  /// Note that since this object is immutable, it needs to be reloaded to see
  /// the new name.
  Future setName(String name) => _scope.sendRequest("setName", {"name": name});

  bool operator ==(other) => other is VMIsolateRef &&
      other._scope.isolateId == _scope.isolateId;

  int get hashCode => _scope.isolateId.hashCode;

  String toString() => name;
}

/// A full isolate on the remote VM.
class VMIsolate extends VMIsolateRef {
  /// The time that the isolate started running.
  final DateTime startTime;

  /// The number of live ports on this isolate.
  final int livePorts;

  /// Whether this isolate will pause before it exits.
  final bool pauseOnExit;

  VMIsolate._(Scope scope, Map json)
      : startTime = new DateTime.fromMillisecondsSinceEpoch(
            // TODO(nweiz): Don't round when sdk#24245 is fixed
            json["startTime"].round()),
        livePorts = json["livePorts"],
        pauseOnExit = json["pauseOnExit"],
        super._(scope, json);
}

/// An enum of ways to resume an isolate's execution using
/// [VMIsolateRef.resume].
class VMStep {
  /// The isolate resumes regular execution.
  static const resume = const VMStep._("Resume");

  /// The isolate takes a single step into a function call.
  static const into = const VMStep._("Into");

  /// The isolate takes a single step, skipping over function calls.
  static const over = const VMStep._("Over");

  /// The isolate continues until it exits the current function.
  static const out = const VMStep._("Out");

  /// The string name of the step type.
  final String _value;

  const VMStep._(this._value);

  String toString() => _value;
}