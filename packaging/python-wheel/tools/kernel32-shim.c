/*
 * Minimal native-import shim for KERNEL32.DLL, used only on Linux.
 *
 * Microsoft.Build.CPPTasks.Common.dll (part of the MSBuild VC++ target files)
 * P/Invokes a handful of Win32 kernel32 functions from VCToolTask's
 * constructor to build a cancellation event, even for tasks like
 * CLCommandLine that only *format* a compiler command line and never spawn
 * cl.exe. .NET's loader on Linux probes an assembly's own directory for
 * "<ModuleName>.so" (case-sensitive) when resolving a P/Invoke, so dropping
 * KERNEL32.DLL.so next to Microsoft.Build.CPPTasks.Common.dll satisfies that
 * resolution without needing Wine or a real Windows kernel.
 *
 * Only the three functions VCToolTask's constructor actually calls are
 * implemented. Anything else P/Invoked through this name will surface as an
 * EntryPointNotFoundException — which is the intended failure mode: this
 * shim exists to unblock design-time command-line extraction, not to
 * emulate Win32.
 */
#include <stdint.h>
#include <stdlib.h>

typedef void *HANDLE;
typedef int BOOL;
typedef uint32_t DWORD;

HANDLE CreateEventW(void *lpEventAttributes, BOOL bManualReset, BOOL bInitialState, const void *lpName) {
    (void)lpEventAttributes;
    (void)bManualReset;
    (void)bInitialState;
    (void)lpName;
    return malloc(1);
}

BOOL SetEvent(HANDLE hEvent) {
    (void)hEvent;
    return 1;
}

BOOL CloseHandle(HANDLE hObject) {
    free(hObject);
    return 1;
}
