// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library vm_service_client.scope;

import 'dart:async';

import 'package:json_rpc_2/json_rpc_2.dart' as rpc;

/// A class representing the state inherent in the scope of a single isolate and
/// the values available therein.
class Scope {
  /// The JSON-RPC 2.0 peer for communicating with the service protocol.
  final rpc.Peer peer;

  /// The ID of this scope's isolate.
  ///
  /// This is necessary for all isolate-scoped RPCs.
  final String isolateId;

  Scope(this.peer, this.isolateId);

  /// Calls an isolate-scoped RPC named [method] with [params].
  ///
  /// This always adds the `isolateId` parameter to the RPC.
  Future<Map> sendRequest(String method, [Map<String, Object> params]) async {
    var allParams = {"isolateId": isolateId}..addAll(params ?? {});
    return (await peer.sendRequest(method, allParams)) as Map;
  }
}
