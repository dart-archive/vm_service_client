// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library vm_service_client.exceptions;

import 'error.dart';
import 'sentinel.dart';

/// An exception thrown when the client attempts to load a remote object that's
/// no longer available.
class VMSentinelException implements Exception {
  /// The sentinel indicating what happened to the remote object.
  final VMSentinel sentinel;

  VMSentinelException(this.sentinel);

  String toString() => "Unexpected $sentinel sentinel.";
}

/// An exception that represents a Dart exception in the remote VM.
class VMErrorException implements Exception {
  /// The error in the remote VM.
  final VMErrorRef error;

  VMErrorException(this.error);

  String toString() => "Remote VM ${error.kind}: ${error.message}";
}
