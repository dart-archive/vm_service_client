// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library vm_service_client.vm;

import 'dart:async';
import 'dart:collection';

import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:pub_semver/pub_semver.dart';

import 'isolate.dart';

VM newVM(rpc.Peer peer, Map json) {
  if (json == null) return null;
  assert(json["type"] == "VM");
  return new VM._(peer, json);
}

/// Data about the Dart VM as a whole.
class VM {
  /// The underlying JSON-RPC peer used to communicate with the VM service.
  final rpc.Peer _peer;

  /// The word length of the target architecture, in bits.
  final int architectureBits;

  /// The name of the CPU for which the VM is generating code.
  final String targetCpu;

  /// The name of the CPU on which VM is actually running code.
  final String hostCpu;

  /// The semantic version of the Dart VM.
  ///
  /// Note that this is distinct from the VM service protocol version, which is
  /// accessible via [VMServiceClient.getVersion].
  final Version version;

  /// The full version string of the Dart VM.
  ///
  /// This includes more information than [version] alone.
  final String versionString;

  /// The process ID of the VM process.
  final int pid;

  /// The time at which the VM started running.
  final DateTime startTime;

  /// The currently-running isolates.
  final List<VMIsolateRef> isolates;

  VM._(rpc.Peer peer, Map json)
      : _peer = peer,
        architectureBits = json["architectureBits"],
        targetCpu = json["targetCPU"],
        hostCpu = json["hostCPU"],
        version = new Version.parse(json["version"].split(" ").first),
        versionString = json["version"],
        pid = int.parse(json["pid"]),
        startTime = new DateTime.fromMillisecondsSinceEpoch(
            // TODO(nweiz): Don't round when sdk#24245 is fixed
            json["startTime"].round()),
        isolates = new UnmodifiableListView(json["isolates"]
            .map((isolate) => newVMIsolateRef(peer, isolate))
            .toList());

  /// Reloads the current state of the VM.
  Future<VM> load() async =>
      new VM._(_peer, await _peer.sendRequest("getVM", {}));
}
