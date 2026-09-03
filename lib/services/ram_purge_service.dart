import 'dart:ffi';
import 'dart:developer';
import 'dart:io';

typedef GetCurrentProcessC = IntPtr Function();
typedef GetCurrentProcessDart = int Function();

typedef SetProcessWorkingSetSizeC = Int32 Function(
  IntPtr hProcess,
  IntPtr dwMinimumWorkingSetSize,
  IntPtr dwMaximumWorkingSetSize,
);
typedef SetProcessWorkingSetSizeDart = int Function(
  int hProcess,
  int dwMinimumWorkingSetSize,
  int dwMaximumWorkingSetSize,
);

typedef MallocTrimC = Int32 Function(IntPtr pad);
typedef MallocTrimDart = int Function(int pad);

class RAMPurgeService {
  static void purgeNow() {
    try {
      _triggerDartGC();
      if (Platform.isWindows) {
        _purgeWindowsRAM();
      } else if (Platform.isLinux) {
        _purgeLinuxRAM();
      } else if (Platform.isAndroid) {
        _purgeAndroidRAM();
      }
    } catch (e, stackTrace) {
      log('Error al purgar la RAM: $e', stackTrace: stackTrace);
    }
  }

  static void _triggerDartGC() {
    for (int i = 0; i < 30; i++) {
      final dummy = List<int>.filled(10000, 0);
      if (dummy.isEmpty) break;
    }
  }

  static void _purgeWindowsRAM() {
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');

      final getCurrentProcess = kernel32.lookupFunction<
          GetCurrentProcessC,
          GetCurrentProcessDart>('GetCurrentProcess');

      final setProcessWorkingSetSize = kernel32.lookupFunction<
          SetProcessWorkingSetSizeC,
          SetProcessWorkingSetSizeDart>('SetProcessWorkingSetSize');

      final handle = getCurrentProcess();

      setProcessWorkingSetSize(handle, -1, -1);
    } catch (e) {
      log('Error purgando RAM en Windows: $e');
    }
  }

  static void _purgeLinuxRAM() {
    try {
      final libc = DynamicLibrary.open('libc.so.6');

      final mallocTrim = libc.lookupFunction<MallocTrimC, MallocTrimDart>('malloc_trim');
      mallocTrim(0);
    } catch (e) {
      log('Error purgando RAM en Linux: $e');
    }
  }

  static void _purgeAndroidRAM() {
    try {
      final libc = DynamicLibrary.open('libc.so');

      final mallocTrim = libc.lookupFunction<MallocTrimC, MallocTrimDart>('malloc_trim');

      mallocTrim(0);
    } catch (e) {
      log('Error purgando RAM en Android: $e');
    }
  }
}
