#include <windows.h>
#include <winternl.h>
#include <tlhelp32.h>
#include <aclapi.h>
#include <sddl.h>
#include <algorithm>
#include <string>
#include <vector>

typedef NTSTATUS(NTAPI* pfnNtQueryInformationProcess)(
    HANDLE ProcessHandle,
    ULONG ProcessInformationClass,
    PVOID ProcessInformation,
    ULONG ProcessInformationLength,
    PULONG ReturnLength
);

typedef NTSTATUS(NTAPI* pfnNtSetInformationThread)(
    HANDLE ThreadHandle,
    ULONG ThreadInformationClass,
    PVOID ThreadInformation,
    ULONG ThreadInformationLength
);

#define ThreadHideFromDebugger 0x11

extern "C" {
    __declspec(dllexport) void DenyMemoryReading() {
        HANDLE hProcess = GetCurrentProcess();

        PSECURITY_DESCRIPTOR pSD = NULL;
        if (ConvertStringSecurityDescriptorToSecurityDescriptorW(
            L"D:(D;;0x1418;;;WD)",
            SDDL_REVISION_1, &pSD, NULL)) {
            
            PACL pDacl = NULL;
            BOOL daclPresent = FALSE;
            BOOL daclDefaulted = FALSE;
            
            if (GetSecurityDescriptorDacl(pSD, &daclPresent, &pDacl, &daclDefaulted)) {
                SetSecurityInfo(hProcess, SE_KERNEL_OBJECT, DACL_SECURITY_INFORMATION, NULL, NULL, pDacl, NULL);
            }
            LocalFree(pSD);
        }

        HMODULE hNtdll = GetModuleHandleA("ntdll.dll");
        if (hNtdll) {
            auto NtSetInformationThread = (pfnNtSetInformationThread)GetProcAddress(hNtdll, "NtSetInformationThread");
            if (NtSetInformationThread) {
                NtSetInformationThread(GetCurrentThread(), ThreadHideFromDebugger, 0, 0);
            }
        }
    }

    __declspec(dllexport) bool IsMemoryScannerPresent() {
        HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if (hSnap == INVALID_HANDLE_VALUE) return false;

        PROCESSENTRY32W pe;
        pe.dwSize = sizeof(PROCESSENTRY32W);

        const std::vector<std::wstring> suspiciousProcesses = {
            L"python.exe", L"pythonw.exe", L"cheatengine", 
            L"x64dbg.exe", L"x32dbg.exe", L"processhacker.exe", 
            L"procmon.exe", L"cheat engine", L"wireshark.exe",
            L"ida.exe", L"ida64.exe", L"ghidra", L"scylla.exe"
        };

        if (Process32FirstW(hSnap, &pe)) {
            do {
                std::wstring exeName = pe.szExeFile;
                std::transform(exeName.begin(), exeName.end(), exeName.begin(), ::towlower);

                for (const auto& target : suspiciousProcesses) {
                    if (exeName.find(target) != std::wstring::npos) {
                        CloseHandle(hSnap);
                        return true;
                    }
                }
            } while (Process32NextW(hSnap, &pe));
        }
        CloseHandle(hSnap);
        return false;
    }

    __declspec(dllexport) bool IsDebuggerAttached() {
        if (IsDebuggerPresent()) return true;

        BOOL isRemotePresent = FALSE;
        CheckRemoteDebuggerPresent(GetCurrentProcess(), &isRemotePresent);
        if (isRemotePresent) return true;

        HMODULE hNtdll = GetModuleHandleA("ntdll.dll");
        if (hNtdll) {
            auto NtQueryInformationProcess = (pfnNtQueryInformationProcess)GetProcAddress(hNtdll, "NtQueryInformationProcess");
            if (NtQueryInformationProcess) {
                DWORD_PTR debugPort = 0;
                NTSTATUS status = NtQueryInformationProcess(GetCurrentProcess(), 7, &debugPort, sizeof(debugPort), NULL);
                if (status == 0 && debugPort != 0) return true;
            }
        }

        CONTEXT ctx = { 0 };
        ctx.ContextFlags = CONTEXT_DEBUG_REGISTERS;
        HANDLE hThread = GetCurrentThread();
        if (GetThreadContext(hThread, &ctx)) {
            if (ctx.Dr0 || ctx.Dr1 || ctx.Dr2 || ctx.Dr3) return true;
        }

        return false;
    }

    __declspec(dllexport) bool IsFridaPresent() {
        HANDLE hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, GetCurrentProcessId());
        if (hSnapshot != INVALID_HANDLE_VALUE) {
            MODULEENTRY32W me32;
            me32.dwSize = sizeof(MODULEENTRY32W);
            if (Module32FirstW(hSnapshot, &me32)) {
                do {
                    std::wstring modName = me32.szModule;
                    std::transform(modName.begin(), modName.end(), modName.begin(), ::towlower);
                    
                    if (modName.find(L"frida") != std::wstring::npos || 
                        modName.find(L"gadget") != std::wstring::npos ||
                        modName.find(L"hook") != std::wstring::npos) {
                        CloseHandle(hSnapshot);
                        return true;
                    }
                } while (Module32NextW(hSnapshot, &me32));
            }
            CloseHandle(hSnapshot);
        }

        WIN32_FIND_DATAW findFileData;
        HANDLE hFind = FindFirstFileW(L"\\\\.\\pipe\\frida-*", &findFileData);
        if (hFind != INVALID_HANDLE_VALUE) {
            FindClose(hFind);
            return true;
        }

        return false;
    }

    __declspec(dllexport) bool IsVirtualMachine() {
        HANDLE hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, GetCurrentProcessId());
        if (hSnapshot != INVALID_HANDLE_VALUE) {
            MODULEENTRY32W me32;
            me32.dwSize = sizeof(MODULEENTRY32W);
            if (Module32FirstW(hSnapshot, &me32)) {
                do {
                    std::wstring modName = me32.szModule;
                    std::transform(modName.begin(), modName.end(), modName.begin(), ::towlower);

                    if (modName.find(L"sbiedll.dll") != std::wstring::npos ||
                        modName.find(L"vboxdisp.dll") != std::wstring::npos ||
                        modName.find(L"vmmouse.sys") != std::wstring::npos) {
                        CloseHandle(hSnapshot);
                        return true;
                    }
                } while (Module32NextW(hSnapshot, &me32));
            }
            CloseHandle(hSnapshot);
        }
        return false;
    }
}
