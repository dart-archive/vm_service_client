// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:math' as math;

import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:source_span/source_span.dart';

import 'breakpoint.dart';
import 'class.dart';
import 'library.dart';
import 'object.dart';
import 'scope.dart';
import 'source_location.dart';

VMScriptRef newVMScriptRef(Scope scope, Map json) {
  if (json == null) return null;
  assert(json["type"] == "@Script" || json["type"] == "Script");
  return new VMScriptRef._(scope, json);
}

VMScriptToken newVMScriptToken(String isolateId, String scriptId,
        int position) {
  if (position == null) return null;
  return new VMScriptToken._(isolateId, scriptId, position);
}

/// A reference to a script in the Dart VM.
///
/// A script contains information about the actual text of a library. Usually
/// there's only one script per library, but the `part` directive can produce
/// libraries made up of multiple scripts.
class VMScriptRef implements VMObjectRef {
  final Scope _scope;

  /// The ID for script library, which is unique relative to its isolate.
  final String _id;

  /// Whether [_id] is guaranteed to be the same for different VM service
  /// script objects that refer to the same script.
  final bool _fixedId;

  /// The URI from which this script was loaded.
  final Uri uri;

  VMScriptRef._(this._scope, Map json)
      : _id = json["id"],
        _fixedId = json["fixedId"] ?? false,
        uri = Uri.parse(json["uri"]);

  Future<VMScript> load() async =>
      new VMScript._(_scope, await _scope.loadObject(_id));

  /// Adds a breakpoint at [line] (and optionally [column]) in this script.
  Future<VMBreakpoint> addBreakpoint(int line, {int column}) async {
    var params = {"scriptId": _id, "line": line};
    if (column != null) params["column"] = column;

    try {
      var response = await _scope.sendRequest("addBreakpoint", params);
      return newVMBreakpoint(_scope, response);
    } on rpc.RpcException catch (error) {
      // Error 102 indicates that the breakpoint couldn't be created.
      if (error.code == 102) return null;
      rethrow;
    }
  }

  bool operator ==(other) => other is VMScriptRef &&
      (_fixedId ? _id == other._id : super == other);

  int get hashCode => _fixedId ? _id.hashCode : super.hashCode;

  String toString() => uri.toString();
}

/// A script in the Dart VM.
class VMScript extends VMScriptRef implements VMObject {
  final VMClassRef klass;

  final int size;

  /// The library that owns this script.
  final VMLibraryRef library;

  /// The source code for this script.
  ///
  /// For certain built-in libraries, this may be reconstructed without source
  /// comments.
  final String source;

  /// A table encoding a mapping from token position to line and column.
  ///
  /// Each subarray consists of an int designating the line, followed by any
  /// number of position-column pairs that represent the positions of tokens
  /// known to the VM.
  ///
  /// Because this encodes all the known token positions, it's more efficient to
  /// access than the representation used by a [SourceFile] as long as you're
  /// looking up a known token boundary.
  final List<List<int>> _tokenPositions;

  /// A source file that provides access to location and span information about
  /// this script.
  ///
  /// This is generally less efficient than calling [sourceSpan] and
  /// [sourceLocation] directly, and should only be used when you don't
  /// [VMSourceLocation] or [VMScriptToken] objects.
  SourceFile get sourceFile {
    if (_sourceFile == null) _sourceFile = new SourceFile(source, url: uri);
    return _sourceFile;
  }
  SourceFile _sourceFile;

  VMScript._(Scope scope, Map json)
      : klass = newVMClassRef(scope, json["class"]),
        size = json["size"],
        library = newVMLibraryRef(scope, json["library"]),
        source = json["source"],
        _tokenPositions = json["tokenPosTable"],
        super._(scope, json);

  /// Returns a [FileSpan] representing the source covered by [location].
  ///
  /// If [location] doesn't have a [VMSourceLocation.end] token, this will be a
  /// point span.
  ///
  /// Throws an [ArgumentError] if [location] isn't for this script.
  FileSpan sourceSpan(VMSourceLocation location) {
    if (location.script._scope.isolateId != _scope.isolateId ||
        (_fixedId && location.script._id != _id)) {
      throw new ArgumentError("SourceLocation isn't for this script.");
    }

    var end = location.end ?? location.token;
    return new _ScriptSpan(this, location.token.offset, end.offset);
  }

  /// Returns a [FileLocation] representing the location indicated by [token].
  ///
  /// Throws an [ArgumentError] if [location] isn't for this script.
  FileLocation sourceLocation(VMScriptToken token) {
    if (token._isolateId != _scope.isolateId ||
        (_fixedId && token._scriptId != _id)) {
      throw new ArgumentError("Token isn't for this script.");
    }

    return new _ScriptLocation(this, token.offset);
  }

  /// Binary searches [_tokenPositions] for the line and column information for
  /// the token at [offset].
  ///
  /// This returns a `line, column` pair if the token is found, and throws a
  /// [StateError] otherwise.
  List<int> _lineAndColumn(int offset) {
    var min = 0;
    var max = _tokenPositions.length;
    while (min < max) {
      var mid = min + ((max - min) >> 1);

      var row = _tokenPositions[mid];

      if (row[1] > offset) {
        max = mid;
      } else {
        for (var i = 1; i < row.length; i += 2) {
          if (row[i] == offset) return [row.first, row[i + 1]];
        }

        min = mid + 1;
      }
    }

    // We only call this for positions that come from the VM, so we shouldn't
    // ever actually reach this point.
    throw new StateError("Couldn't find line and column for offset $offset in "
        "$uri.");
  }
}

/// The location of a token in a Dart script.
///
/// A token can be passed to [VMScriptRef.sourceLocation] to get the line and
/// column information for the token.
class VMScriptToken {
  /// The ID of this token's script's isolate.
  final String _isolateId;

  /// The ID of this token's script.
  final String _scriptId;

  /// The location of this token in the script, in code units from the
  /// beginning.
  final int offset;

  VMScriptToken._(this._isolateId, this._scriptId, this.offset);

  String toString() => offset.toString();
}

/// An implementation of [FileLocation] based on a known token offset.
class _ScriptLocation extends SourceLocationMixin implements FileLocation {
  /// The script that produced this location.
  final VMScript _script;

  final int offset;

  SourceFile get file => _script.sourceFile;

  Uri get sourceUrl => _script.uri;

  int get line {
    _ensureLineAndColumn();
    return _line;
  }
  int _line;

  int get column {
    _ensureLineAndColumn();
    return _column;
  }
  int _column;

  _ScriptLocation(this._script, this.offset);

  /// Ensures that [_line] and [_column] are set based on [_script]'s
  /// information.
  void _ensureLineAndColumn() {
    if (_line != null) return null;
    var result = _script._lineAndColumn(offset);
    _line = result.first;
    _column = result.last;
  }

  FileSpan pointSpan() => new _ScriptSpan(_script, offset, offset);
}

/// An implementation of [FileSpan] based on known token offsets.
class _ScriptSpan extends SourceSpanMixin implements FileSpan {
  /// The script that produced this location.
  final VMScript _script;

  SourceFile get file => _script.sourceFile;

  /// The offset of the start token.
  final int _start;

  /// The offset of the end token.
  final int _end;

  Uri get sourceUrl => _script.uri;
  int get length => _end - _start;
  FileLocation get start => new _ScriptLocation(_script, _start);
  FileLocation get end => new _ScriptLocation(_script, _end);
  String get text => _script.source.substring(_start, _end);

  // We have to make [_script.sourceFile] concrete for this because the VMScript
  // alone doesn't have the line context in an easily accessible form.
  String get context => file.getText(file.getOffset(start.line),
      end.line == file.lines - 1 ? null : file.getOffset(end.line + 1));  

  _ScriptSpan(this._script, this._start, this._end);

  int compareTo(SourceSpan other) {
    if (other is! _ScriptSpan) return super.compareTo(other);

    _ScriptSpan otherFile = other;
    var result = _start.compareTo(otherFile._start);
    return result == 0 ? _end.compareTo(otherFile._end) : result;
  }

  SourceSpan union(SourceSpan other) {
    if (other is! _ScriptSpan) return super.union(other);

    var span = expand(other);
    var beginSpan = span._start == _start ? this : other;
    var endSpan = span._end == _end ? this : other;

    if (beginSpan._end < endSpan._start) {
      throw new ArgumentError("Spans $this and $other are disjoint.");
    }

    return span;
  }

  bool operator ==(other) {
    if (other is! FileSpan) return super == other;

    if (other is! _ScriptSpan) {
      return super == other && sourceUrl == other.sourceUrl;
    }

    return _start == other._start && _end == other._end &&
        sourceUrl == other.sourceUrl;
  }

  FileSpan expand(FileSpan other) {
    if (sourceUrl != other.sourceUrl) {
      throw new ArgumentError("Source URLs \"${sourceUrl}\" and "
          " \"${other.sourceUrl}\" don't match.");
    }

    if (other is _ScriptSpan) {
      var start = math.min(this._start, other._start);
      var end = math.max(this._end, other._end);
      return new _ScriptSpan(_script, start, end);
    } else {
      var start = math.min(this._start, other.start.offset);
      var end = math.max(this._end, other.end.offset);
      return file.span(start, end);
    }
  }
}
