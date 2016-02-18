## 0.1.2

* Add `VMIsolateRef.onExtensionEvent`, which emits events posted by VM service
  extensions using `postEvent` in `dart:developer`.

* Add `VMIsolateRef.selectExtensionEvents()`, which selects events with specific
  kinds posted by VM service extensions using `postEvent` in `dart:developer`.

* Add `VMIsolateRef.onExtensionAdded`, which emits an event when a VM service
  extension registers a new RPC.

* Add `VMIsolateRef.waitForExtension()`, which returns when a given extension
  RPC is available.

* Add `VMIsolateRef.invokeExtension()`, which invokes VM service extension RPCs
  registered using `registerExtension` in `dart:developer`.

* Add `VMIsolate.extensionRpcs`, which returns the extension RPCs registered in
  a given isolate.

## 0.1.1+1

* Fix a bug where `VMPauseEvent.time` would always be reported as `null` or
  crash.

## 0.1.1

* Fix support for VM service protocol 1.0 events.

## 0.1.0

* Initial version.
