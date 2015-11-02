// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library vm_service_client.type_arguments;

import 'dart:async';
import 'dart:collection';

import 'class.dart';
import 'scope.dart';
import 'instance.dart';
import 'object.dart';

VMTypeArgumentsRef newVMTypeArgumentsRef(Scope scope,
    Map json) {
  if (json == null) return null;
  assert(json["type"] == "@TypeArguments" || json["type"] == "TypeArguments");
  return new VMTypeArgumentsRef._(scope, json);
}

/// A reference to the type arguments for some instantiated generic type.
class VMTypeArgumentsRef implements VMObjectRef {
  final Scope _scope;

  /// The ID for these type arguments, which is unique relative to their
  /// isolate.
  final String _id;

  /// Whether [_id] is guaranteed to be the same for different VM service type
  /// arguments objects that refer to the same type arguments.
  final bool _fixedId;

  /// A name for this type argument list.
  final String name;

  VMTypeArgumentsRef._(this._scope, Map json)
      : _id = json["id"],
        _fixedId = json["fixedId"] ?? false,
        name = json["name"];

  Future<VMTypeArguments> load() async =>
      new VMTypeArguments._(_scope, await _scope.loadObject(_id));

  bool operator ==(other) => other is VMTypeArgumentsRef &&
      (_fixedId ? _id == other._id : super == other);

  int get hashCode => _fixedId ? _id.hashCode : super.hashCode;

  String toString() => name;
}

/// The type arguments for some instantiated generic type.
class VMTypeArguments extends VMTypeArgumentsRef implements VMObject {
  final VMClassRef klass;

  final int size;

  /// The type arguments.
  final List<VMTypeLikeInstanceRef> types;

  VMTypeArguments._(Scope scope, Map json)
      : klass = newVMClassRef(scope, json["class"]),
        size = json["size"],
        types = new UnmodifiableListView(json["types"]
            .map((type) => newVMTypeLikeInstanceRef(scope, type))
            .toList()),
        super._(scope, json);
}
