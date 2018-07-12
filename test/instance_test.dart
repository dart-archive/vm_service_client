// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:typed_data';

import 'package:vm_service_client/vm_service_client.dart';
import 'package:test/test.dart';

import 'utils.dart';

VMServiceClient client;

void main() {
  group("for a plain instance", () {
    var value;
    setUp(() async {
      client = await runAndConnect(topLevel: r"""
        class Foo {
          final int _value;

          Foo(this._value);
        }
      """, flags: ["--pause-isolates-on-start"]);
      value = await _evaluate("new Foo(12)");
    });

    tearDown(() => client.close());

    test("includes the instance's metadata", () async {
      expect(value.klass.name, equals("Foo"));
      expect(value.toString(), equals("Remote instance of 'Foo'"));
      expect((await value.load()).fields, contains("_value"));
    });

    test("evaluate() runs in the context of the instance", () async {
      var result = await value.evaluate("this._value + 1") as VMIntInstanceRef;
      expect(result.value, equals(13));
    });

    test("getValue() runs onUnknownValue", () async {
      var result =
          await value.getValue(onUnknownValue: expectAsync1((innerValue) {
        expect(innerValue, same(value));
        return 123;
      }));
      expect(result, equals(123));
    });
  });

  group("for a client with no code:", () {
    setUp(() async {
      client = await runAndConnect(flags: ["--pause-isolates-on-start"]);
    });

    tearDown(() => client.close());

    test("a null", () async {
      var value = await _evaluate("null") as VMNullInstanceRef;

      expect(value.value, isNull);
      expect((await value.load()).value, isNull);
      expect(await value.getValue(onUnknownValue: neverCalled), isNull);
    });

    test("a bool", () async {
      var value = await _evaluate("true") as VMBoolInstanceRef;

      expect(value.value, isTrue);
      expect((await value.load()).value, isTrue);
      expect(await value.getValue(onUnknownValue: neverCalled), isTrue);
    });

    test("a double", () async {
      var value = await _evaluate("12.3") as VMDoubleInstanceRef;

      expect(value.value, equals(12.3));
      expect((await value.load()).value, equals(12.3));
      expect(await value.getValue(onUnknownValue: neverCalled), equals(12.3));
    });

    test("an int", () async {
      var value = await _evaluate("12") as VMIntInstanceRef;

      expect(value.value, equals(12));
      expect((await value.load()).value, equals(12));
      expect(await value.getValue(onUnknownValue: neverCalled), equals(12));
    });

    test("a Float32x4", () async {
      var value = await _evaluate("new Float32x4(1.23, 2.34, 3.45, 4.56)")
          as VMFloat32x4InstanceRef;

      expect(value.value.x, closeTo(1.23, 0.00001));
      expect(value.value.y, closeTo(2.34, 0.00001));
      expect(value.value.z, closeTo(3.45, 0.00001));
      expect(value.value.w, closeTo(4.56, 0.00001));
      expect((await value.load()).toString(), equals(value.value.toString()));
      expect((await value.getValue(onUnknownValue: neverCalled)).toString(),
          equals(value.value.toString()));
    });

    test("a Float64x2", () async {
      var value = await _evaluate("new Float64x2(1.23, 2.34)")
          as VMFloat64x2InstanceRef;

      expect(value.value.x, closeTo(1.23, 0.00001));
      expect(value.value.y, closeTo(2.34, 0.00001));
      expect((await value.load()).toString(), equals(value.value.toString()));
      expect((await value.getValue(onUnknownValue: neverCalled)).toString(),
          equals(value.value.toString()));
    });

    test("an Int32x4", () async {
      var value = await _evaluate("new Int32x4(123, 234, 345, 456)")
          as VMInt32x4InstanceRef;

      expect(value.value.x, equals(123));
      expect(value.value.y, equals(234));
      expect(value.value.z, equals(345));
      expect(value.value.w, equals(456));
      expect((await value.load()).toString(), equals(value.value.toString()));
      expect((await value.getValue(onUnknownValue: neverCalled)).toString(),
          equals(value.value.toString()));
    });

    test("a StackTrace", () async {
      var value = await _evaluate(r"""
        (() {
          try {
            throw 'oh no!';
          } catch (error, stackTrace) {
            return stackTrace;
          }
        })()
      """) as VMStackTraceInstanceRef;

      expect(value.value.frames.first.uri.scheme, equals("evaluate"));
      expect(await value.getValue(onUnknownValue: neverCalled),
          equals(value.value));
      expect((await value.load()).value.toString(),
          equals(value.value.toString()));
    });

    test("a short String", () async {
      var value = await _evaluate(r"""'f\'\"oo'""") as VMStringInstanceRef;

      expect(value.value, equals("f'\"oo"));
      expect(value.isValueTruncated, isFalse);
      expect(value.toString(), equals('"f\'\\"oo"'));
      expect(
          await value.getValue(onUnknownValue: neverCalled), equals("f'\"oo"));
      expect((await value.load()).value, equals("f'\"oo"));
    });

    test("a long String", () async {
      var value = await _evaluate(r"""'foo' * 10000""") as VMStringInstanceRef;

      expect(value.value, startsWith("foo"));
      expect(value.isValueTruncated, isTrue);
      expect(value.toString(), endsWith('..."'));
      expect(await value.getValue(onUnknownValue: neverCalled),
          equals("foo" * 10000));

      value = await value.load();
      expect(value.value, equals("foo" * 10000));
      expect(value.isValueTruncated, isFalse);
      expect(value.toString(), equals('"${"foo" * 10000}"'));
    });

    test("a List", () async {
      var valueRef = await _evaluate("[1, 2, 3, 4]") as VMListInstanceRef;

      expect(valueRef.length, equals(4));
      expect(valueRef.toString(), equals("[...]"));
      expect(await valueRef.getValue(), equals([1, 2, 3, 4]));

      var value = await valueRef.load();
      expect(
          value.elements,
          allOf([
            hasLength(4),
            everyElement(new TypeMatcher<VMIntInstanceRef>())
          ]));
      expect(value.toString(), equals("[1, 2, 3, 4]"));
      expect(await value.getValue(), equals([1, 2, 3, 4]));
    });

    test("a List containing an unconvertable instance", () async {
      var value = await _evaluate("[() {}]");

      expect(value.getValue(), throwsUnsupportedError);
      expect(
          await value.getValue(onUnknownValue: expectAsync1((value) {
            expect(value, new TypeMatcher<VMClosureInstanceRef>());
            return null;
          })),
          equals([null]));
    });

    test("a Map", () async {
      var valueRef = await _evaluate("{1: 2, 3: 4}") as VMMapInstanceRef;

      expect(valueRef.length, equals(2));
      expect(valueRef.toString(), equals("{...}"));
      expect(await valueRef.getValue(), equals({1: 2, 3: 4}));

      var value = await valueRef.load();
      expect(value.associations, hasLength(2));
      expect(value.associations.first.key, new TypeMatcher<VMIntInstanceRef>());
      expect(
          value.associations.first.value, new TypeMatcher<VMIntInstanceRef>());
      expect(value.associations.last.key, new TypeMatcher<VMIntInstanceRef>());
      expect(
          value.associations.last.value, new TypeMatcher<VMIntInstanceRef>());
      expect(value.toString(), equals("{1: 2, 3: 4}"));
      expect(await value.getValue(), equals({1: 2, 3: 4}));
    });

    test("a Map containing an unconvertable instance", () async {
      var value = await _evaluate("{1: () {}}");

      expect(value.getValue(), throwsUnsupportedError);
      expect(
          await value.getValue(onUnknownValue: expectAsync1((value) {
            expect(value, new TypeMatcher<VMClosureInstanceRef>());
            return null;
          })),
          equals({1: null}));
    });

    test("a TypedData", () async {
      var valueRef = await _evaluate("new Uint8List.fromList([1, 2, 3, 4])")
          as VMTypedDataInstanceRef;

      expect(valueRef.length, equals(4));
      expect(valueRef.toString(), equals("[...]"));
      expect(
          await valueRef.getValue(),
          allOf([
            new TypeMatcher<Uint8List>(),
            equals([1, 2, 3, 4])
          ]));

      var value = await valueRef.load();
      expect(
          value.value,
          allOf([
            new TypeMatcher<Uint8List>(),
            equals([1, 2, 3, 4])
          ]));
      expect(value.toString(), equals("[1, 2, 3, 4]"));
      expect(
          await value.getValue(),
          allOf([
            new TypeMatcher<Uint8List>(),
            equals([1, 2, 3, 4])
          ]));
    });

    test("a RegExp", () async {
      var valueRef = await _evaluate("new RegExp('foo', caseSensitive: false)")
          as VMRegExpInstanceRef;

      expect(valueRef.pattern.isValueTruncated, isFalse);
      expect(valueRef.pattern.value, equals("foo"));
      expect(valueRef.toString(), equals('"foo"'));
      expect(await valueRef.getValue(),
          equals(new RegExp('foo', caseSensitive: false)));

      var value = await valueRef.load();
      expect(value.pattern.isValueTruncated, isFalse);
      expect(value.pattern.value, equals("foo"));
      expect(value.isCaseSensitive, isFalse);
      expect(value.isMultiLine, isFalse);
      expect(await value.getValue(),
          equals(new RegExp('foo', caseSensitive: false)));
    });

    test("a RegExp with a long pattern", () async {
      var valueRef =
          await _evaluate("new RegExp('foo' * 10000, multiLine: true)")
              as VMRegExpInstanceRef;

      expect(valueRef.pattern.isValueTruncated, isTrue);
      expect(valueRef.pattern.value, startsWith("foo"));
      expect(valueRef.toString(), endsWith('..."'));
      expect(await valueRef.getValue(),
          equals(new RegExp('foo' * 10000, multiLine: true)));

      var value = await valueRef.load();
      expect(value.pattern.isValueTruncated, isTrue);
      expect(value.pattern.value, startsWith("foo"));
      expect(value.isCaseSensitive, isTrue);
      expect(value.isMultiLine, isTrue);
      expect(await value.getValue(),
          equals(new RegExp('foo' * 10000, multiLine: true)));
    });

    test("a function", () async {
      var valueRef = await _evaluate("""
        (() {
          var i = 0;
          myFunction() => i;
          return myFunction;
        })()
      """) as VMClosureInstanceRef;

      var value = await valueRef.load();
      expect(value.function.name, equals("myFunction"));
      expect(value.context.length, equals(1));

      var context = await value.context.load();
      expect(context.variables, hasLength(1));
      expect(context.variables.first, new TypeMatcher<VMIntInstanceRef>());
      expect(context.parent, isNull);
    });

    test("a type", () async {
      var valueRef =
          await _evaluate("<int>[].runtimeType") as VMTypeInstanceRef;

      expect(valueRef.name, equals("List<int>"));
      expect(valueRef.typeClass.name, equals("_GrowableList"));

      var value = await valueRef.load();
      var argumentsRef = value.arguments;
      expect(argumentsRef.name, equals("<int>"));

      var arguments = await argumentsRef.load();
      expect(arguments.types, hasLength(1));
      var argument = arguments.types.first as VMTypeInstanceRef;
      expect(argument.name, equals("int"));
    });
  });
}

Future<VMInstanceRef> _evaluate(String expression) async {
  var isolate = await (await client.getVM()).isolates.first.loadRunnable();
  return await isolate.rootLibrary.evaluate(expression);
}
