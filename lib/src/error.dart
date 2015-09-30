// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library vm_service_client.error;

import 'dart:async';

import 'object.dart';
import 'scope.dart';

VMErrorRef newVMErrorRef(Scope scope, Map json) {
  if (json == null) return null;
  assert(json["type"] == "@Error" || json["type"] == "Error");
  return new VMErrorRef._(scope, json);
}

VMErrorRef newVMError(Scope scope, Map json) {
  if (json == null) return null;
  assert(json["type"] == "Error");
  return new VMError._(scope, json);
}

/// A reference to a Dart language error.
class VMErrorRef implements VMObjectRef {
  final Scope _scope;

  /// The ID for the error, which is unique relative to its isolate.
  final String _id;

  /// Whether [_id] is guaranteed to be the same for different VM service error
  /// objects that refer to the same error.
  final bool _fixedId;

  /// The kind of error this is.
  final VMErrorKind kind;

  /// The error message.
  final String message;

  VMErrorRef._(this._scope, Map json)
      : _id = json["id"],
        _fixedId = json["fixedId"] ?? false,
        kind = new VMErrorKind._parse(json["kind"]),
        message = json["message"];

  Future<VMError> load() async =>
      new VMError._(_scope, await _scope.loadObject(_id));

  bool operator ==(other) => other is VMErrorRef &&
      (_fixedId ? _id == other._id : super == other);

  int get hashCode => _fixedId ? _id.hashCode : super.hashCode;

  String toString() => "$kind: $message";
}

/// A Dart language error.
class VMError extends VMErrorRef implements VMObject {
  final int size;

  VMError._(Scope scope, Map json)
      : size = json["size"],
        super._(scope, json);
}

/// An enum of different kinds of Dart errors.
class VMErrorKind {
  /// A Dart exception with no handler.
  static const unhandledException = const VMErrorKind._("UnhandledException");

  /// An error caused by invalid Dart code.
  static const languageError = const VMErrorKind._("LanguageError");

  /// An internal error.
  ///
  /// These errors should not be exposed—if seen, they should be [reported as
  /// bugs](https://github.com/dart-lang/sdk/issues/new).
  static const internalError = const VMErrorKind._("InternalError");

  /// The isolate has been terminated from an external source.
  static const terminationError = const VMErrorKind._("TerminationError");

  /// The name of the error.
  final String name;

  /// Parses the error from its service protocol name.
  factory VMErrorKind._parse(String name) {
    switch (name) {
      case "UnhandledException": return VMErrorKind.unhandledException;
      case "LanguageError": return VMErrorKind.languageError;
      case "InternalError": return VMErrorKind.internalError;
      case "TerminationError": return VMErrorKind.terminationError;
      default: throw new StateError("Unknown VM error kind \"$name\".");
    }
  }

  const VMErrorKind._(this.name);

  String toString() => name;
}
