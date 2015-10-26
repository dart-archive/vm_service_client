// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:async/async.dart';
import 'package:test/test.dart';
import 'package:vm_service_client/vm_service_client.dart';

import 'utils.dart';

VMServiceClient client;

void main() {
  tearDown(() {
    if (client != null) client.close();
  });

  test("includes a top-level field's metadata", () async {
    client = await runAndConnect(topLevel: r"""
      const String value = 'foo';
    """, flags: ["--pause-isolates-on-start"]);

    var isolate = await (await client.getVM()).isolates.first.load();
    var field = (await isolate.rootLibrary.load()).fields["value"];

    expect(field.name, equals("value"));
    expect(field.owner, new isInstanceOf<VMLibraryRef>());
    expect(field.owner.uri, equals(isolate.rootLibrary.uri));
    expect(field.declaredType, new isInstanceOf<VMTypeInstanceRef>());
    expect(field.declaredType.name, equals("String"));
    expect(field.isConst, isTrue);
    expect(field.isFinal, isTrue);
    expect(field.isStatic, isTrue);
    expect(field.description, equals("const String value"));
    expect(field.toString(), equals("const String value = ..."));

    field = await field.load();
    expect(field.value, new isInstanceOf<VMStringInstanceRef>());
    expect(field.value.value, equals("foo"));
    expect(field.location.script.uri, equals(isolate.rootLibrary.uri));
    expect(field.toString(), equals('const String value = "foo"'));
  });

  test("includes an instance field's metadata", () async {
    client = await runAndConnect(topLevel: r"""
      class Foo {
        var value = 12;
      }
    """, flags: ["--pause-isolates-on-start"]);

    var isolate = await (await client.getVM()).isolates.first.load();
    var klass = (await isolate.rootLibrary.load()).classes["Foo"];
    var instance = await (await klass.evaluate("new Foo()")).load();
    var field = instance.fields["value"].declaration;

    expect(field.name, equals("value"));
    expect(field.owner, new isInstanceOf<VMClassRef>());
    expect(field.owner.name, equals("Foo"));
    expect(field.declaredType, new isInstanceOf<VMTypeInstanceRef>());
    expect(field.declaredType.name, equals("dynamic"));
    expect(field.isConst, isFalse);
    expect(field.isFinal, isFalse);
    expect(field.isStatic, isFalse);
    expect(field.description, equals("var value"));
    expect(field.toString(), equals("var value = ..."));

    field = await field.load();
    expect(field.value, isNull);
    expect(field.location.script.uri, equals(isolate.rootLibrary.uri));
    expect(field.toString(), equals('var value = ...'));
  });
}
