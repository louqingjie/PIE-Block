import 'dart:ffi';

final class PbSdccStringList extends Struct {
  external Pointer<Pointer<Char>> items;

  @Uint32()
  external int count;
}

final class PbSdccRequest extends Struct {
  external Pointer<Char> workingDirectory;
  external Pointer<Char> resourceDirectory;
  external Pointer<Char> projectKind;
  external Pointer<Char> mainSourcePath;
  external Pointer<Char> interruptHeaderPath;
  external PbSdccStringList sourcePaths;
  external PbSdccStringList compileArguments;
  external PbSdccStringList linkArguments;
  external Pointer<Char> hexOutputPath;
  external Pointer<Char> mapOutputPath;
  external Pointer<Char> logOutputPath;
}

final class PbSdccEvent extends Struct {
  @Int32()
  external int stage;
  @Int32()
  external int level;
  @Int32()
  external int current;
  @Int32()
  external int total;
  external Pointer<Char> fileName;
  external Pointer<Char> message;
}

final class PbSdccResult extends Struct {
  @Int32()
  external int status;
  @Int32()
  external int exitCode;
  @Int32()
  external int errorCount;
  @Int32()
  external int warningCount;
  external Pointer<Char> hexPath;
  external Pointer<Char> mapPath;
  external Pointer<Char> logPath;
  external Pointer<Char> errorCode;
  external Pointer<Char> message;
}

typedef _ApiVersionNative = Uint32 Function();
typedef ApiVersionDart = int Function();
typedef _FingerprintNative = Pointer<Char> Function();
typedef FingerprintDart = Pointer<Char> Function();
typedef _IsAvailableNative = Int32 Function();
typedef IsAvailableDart = int Function();
typedef _StartNative = Int32 Function(
  Pointer<PbSdccRequest>,
  Pointer<Pointer<Void>>,
);
typedef StartDart = int Function(
  Pointer<PbSdccRequest>,
  Pointer<Pointer<Void>>,
);
typedef _PollNative = Int32 Function(Pointer<Void>, Pointer<PbSdccEvent>);
typedef PollDart = int Function(Pointer<Void>, Pointer<PbSdccEvent>);
typedef _CancelNative = Int32 Function(Pointer<Void>);
typedef CancelDart = int Function(Pointer<Void>);
typedef _ResultNative = Int32 Function(Pointer<Void>, Pointer<PbSdccResult>);
typedef ResultDart = int Function(Pointer<Void>, Pointer<PbSdccResult>);
typedef _DestroyNative = Void Function(Pointer<Void>);
typedef DestroyDart = void Function(Pointer<Void>);

class PbSdccBindings {
  PbSdccBindings(DynamicLibrary library)
    : apiVersion = library.lookupFunction<_ApiVersionNative, ApiVersionDart>(
        'pb_sdcc_api_version',
      ),
      fingerprint = library.lookupFunction<_FingerprintNative, FingerprintDart>(
        'pb_sdcc_build_fingerprint',
      ),
      isAvailable = library.lookupFunction<_IsAvailableNative, IsAvailableDart>(
        'pb_sdcc_is_available',
      ),
      start = library.lookupFunction<_StartNative, StartDart>('pb_sdcc_start'),
      poll = library.lookupFunction<_PollNative, PollDart>(
        'pb_sdcc_poll_event',
      ),
      cancel = library.lookupFunction<_CancelNative, CancelDart>(
        'pb_sdcc_cancel',
      ),
      result = library.lookupFunction<_ResultNative, ResultDart>(
        'pb_sdcc_get_result',
      ),
      destroy = library.lookupFunction<_DestroyNative, DestroyDart>(
        'pb_sdcc_destroy',
      );

  final ApiVersionDart apiVersion;
  final FingerprintDart fingerprint;
  final IsAvailableDart isAvailable;
  final StartDart start;
  final PollDart poll;
  final CancelDart cancel;
  final ResultDart result;
  final DestroyDart destroy;
}
