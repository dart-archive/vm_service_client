// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

VMReloadReport newVMReloadReport(Map json) {
  if (json == null) return null;
  assert(json["type"] == "ReloadReport");
  return new VMReloadReport._(json);
}

/// The reload report that is returned by `VMIsolateRef.reloadSources`.
class VMReloadReport {
  /// Did the reload succeed or fail?
  final bool status;

  VMReloadReport._(Map json) : status = json["success"];

  String toString() => "$status";
}
