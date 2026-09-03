#include <iostream>
#include <fstream>
#include <string>
#include <dirent.h>
#include <unistd.h>
#include <sys/ptrace.h>
#include <sys/prctl.h>
#include <algorithm>
#include <vector>

extern "C" {
    __attribute__((visibility("default"))) void DenyMemoryReading() {
        prctl(PR_SET_DUMPABLE, 0);
    }

    __attribute__((visibility("default"))) bool IsDebuggerAttached() {
        std::ifstream statusFile("/proc/self/status");
        std::string line;
        while (std::getline(statusFile, line)) {
            if (line.rfind("TracerPid:", 0) == 0) {
                int tracerPid = std::stoi(line.substr(10));
                return tracerPid != 0;
            }
        }
        return false;
    }

    __attribute__((visibility("default"))) bool IsMemoryScannerPresent() {
        DIR* dir = opendir("/proc");
        if (!dir) return false;

        const std::vector<std::string> targets = {"python", "gdb", "radare2", "edb", "fuzz"};
        struct dirent* entry;

        while ((entry = readdir(dir)) != NULL) {
            if (entry->d_type == DT_DIR) {
                std::string pid = entry->d_name;
                if (std::all_of(pid.begin(), pid.end(), ::isdigit)) {
                    std::ifstream cmdFile("/proc/" + pid + "/cmdline");
                    std::string cmdline;
                    if (std::getline(cmdFile, cmdline)) {
                        std::transform(cmdline.begin(), cmdline.end(), cmdline.begin(), ::towlower);
                        for (const auto& t : targets) {
                            if (cmdline.find(t) != std::string::npos) {
                                closedir(dir);
                                return true;
                            }
                        }
                    }
                }
            }
        }
        closedir(dir);
        return false;
    }

    __attribute__((visibility("default"))) bool IsFridaPresent() {
        std::ifstream mapsFile("/proc/self/maps");
        std::string line;
        while (std::getline(mapsFile, line)) {
            std::transform(line.begin(), line.end(), line.begin(), ::towlower);
            if (line.find("frida") != std::string::npos || line.find("gadget") != std::string::npos) {
                return true;
            }
        }
        return false;
    }

    __attribute__((visibility("default"))) bool IsVirtualMachine() {
        return false;
    }
}
