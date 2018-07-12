// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

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

    var isolate = await (await client.getVM()).isolates.first.loadRunnable();
    var fieldRef = (await isolate.rootLibrary.load()).fields["value"];

    expect(fieldRef.name, equals("value"));
    expect(
        (fieldRef.owner as VMLibraryRef).uri, equals(isolate.rootLibrary.uri));
    expect((fieldRef.declaredType as VMTypeInstanceRef).name, equals("String"));
    expect(fieldRef.isConst, isTrue);
    expect(fieldRef.isFinal, isTrue);
    expect(fieldRef.isStatic, isTrue);
    expect(fieldRef.description, equals("const String value"));
    expect(fieldRef.toString(), equals("const String value = ..."));

    var field = await fieldRef.load();
    expect((field.value as VMStringInstanceRef).value, equals("foo"));
    expect(field.location.script.uri, equals(isolate.rootLibrary.uri));
    expect(field.toString(), equals('const String value = "foo"'));
  });

  test("includes an instance field's metadata", () async {
    client = await runAndConnect(topLevel: r"""
      class Foo {
        var value = 12;
      }
    """, flags: ["--pause-isolates-on-start"]);

    var isolate = await (await client.getVM()).isolates.first.loadRunnable();
    var klass = (await isolate.rootLibrary.load()).classes["Foo"];
    var instance = await (await klass.evaluate("new Foo()")).load();
    var fieldRef = instance.fields["value"].declaration;

    expect(fieldRef.name, equals("value"));
    expect((fieldRef.owner as VMClassRef).name, equals("Foo"));
    expect(
        (fieldRef.declaredType as VMTypeInstanceRef).name, equals("dynamic"));
    expect(fieldRef.isConst, isFalse);
    expect(fieldRef.isFinal, isFalse);
    expect(fieldRef.isStatic, isFalse);
    expect(fieldRef.description, equals("var value"));
    expect(fieldRef.toString(), equals("var value = ..."));

    var field = await fieldRef.load();
    expect(field.value, isNull);
    expect(field.location.script.uri, equals(isolate.rootLibrary.uri));
    expect(field.toString(), equals('var value = ...'));
  });
}
