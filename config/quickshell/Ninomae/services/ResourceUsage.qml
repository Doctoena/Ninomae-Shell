pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
/**
 * Simple polled resource usage service with RAM, Swap, CPU, GPU usage, and temperatures.
 */
Singleton {
    id: root
    // Pre-compiled regex patterns for better performance
    readonly property var memTotalRegex: /MemTotal:\s*(\d+)/
    readonly property var memAvailableRegex: /MemAvailable:\s*(\d+)/
    readonly property var swapTotalRegex: /SwapTotal:\s*(\d+)/
    readonly property var swapFreeRegex: /SwapFree:\s*(\d+)/
    readonly property var cpuStatRegex: /^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/

    property double memoryTotal: 0
    property double memoryFree: 0
    readonly property double memoryUsed: memoryTotal - memoryFree
    readonly property double memoryUsedPercentage: memoryTotal > 0 ? (memoryUsed / memoryTotal) : 0
    property double swapTotal: 0
    property double swapFree: 0
    readonly property double swapUsed: swapTotal - swapFree
    property double cpuUsage: 0
    property string cpuName: ""
    property var previousCpuStats
    // GPU properties
    property double gpuUsage: 0
    property double vramTotal: 0
    property double vramUsed: 0
    property string gpuType: "unknown" // "amd", "nvidia", or "unknown"
    property string gpuName: ""
    property bool gpuDetected: false
    // Temperature properties (in Celsius)
    property double cpuTemp: 0
    property double gpuTemp: 0
    property double ramTemp: 0
    // Auto-detected hwmon paths (resolved at startup)
    property string cpuTempPath: ""
    property string ramTempPath: ""
    property bool hwmonResolved: false
    // Detect CPU model name from /proc/cpuinfo at startup
    Process {
        id: cpuNameProcess
        running: true
        command: ["sh", "-c", "grep -m1 'model name' /proc/cpuinfo | sed -e 's/.*: //' -e 's/(R)//g' -e 's/(TM)//g' -e 's/^.*Gen //' -e 's/ CPU//' -e 's/ [0-9]*-Core Processor//' -e 's/ @.*$//' -e 's/  */ /g'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const name = text.trim()
                if (name.length > 0) cpuName = name
            }
        }
    }
    // Auto-detect hwmon paths by reading the 'name' file in each hwmon directory
    // This avoids breakage when kernel enumeration order changes (e.g., after kernel updates)
    Process {
        id: hwmonDetectProcess
        running: true
        command: ["bash", "-c", `
            cpu_path=""; ram_path=""
            for hwmon in /sys/class/hwmon/hwmon*; do
                name=$(cat "$hwmon/name" 2>/dev/null)
                case "$name" in
                    k10temp|coretemp|zenpower|cpu_thermal)
                        [ -f "$hwmon/temp1_input" ] && cpu_path="$hwmon/temp1_input"
                        ;;
                    spd5118|jc42)
                        [ -f "$hwmon/temp1_input" ] && ram_path="$hwmon/temp1_input"
                        ;;
                esac
            done
            echo "$cpu_path"
            echo "$ram_path"
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                if (lines[0] && lines[0].length > 0) {
                    cpuTempPath = lines[0]
                    fileCpuTemp.path = cpuTempPath
                } else {
                    console.warn("[ResourceUsage] Could not auto-detect CPU temperature hwmon path")
                }
                if (lines[1] && lines[1].length > 0) {
                    ramTempPath = lines[1]
                    fileRamTemp.path = ramTempPath
                } else {
                    console.warn("[ResourceUsage] Could not auto-detect RAM temperature hwmon path")
                }
                hwmonResolved = true
            }
        }
    }
    // Only poll while something shows the numbers (widgets register through `watchers`)
    property int watchers: 0
    Timer {
        interval: Config.options?.resources?.updateInterval ?? 3000
        running: root.watchers > 0
        repeat: true
        triggeredOnStart: true
        onRunningChanged: if (running) root.previousCpuStats = null // Don't average CPU over the idle gap
        onTriggered: {
            // CPU usage is a delta between two reads, so the first tick after starting has nothing to
            // compare against; the next one comes after half a second instead of a full interval
            const warmingUp = !previousCpuStats
            // Reload files
            fileMeminfo.reload()
            fileStat.reload()
            // Parse memory and swap usage using pre-compiled regex
            const textMeminfo = fileMeminfo.text()
            memoryTotal = Number(memTotalRegex.exec(textMeminfo)?.[1] ?? 1)
            memoryFree = Number(memAvailableRegex.exec(textMeminfo)?.[1] ?? 0)
            swapTotal = Number(swapTotalRegex.exec(textMeminfo)?.[1] ?? 1)
            swapFree = Number(swapFreeRegex.exec(textMeminfo)?.[1] ?? 0)
            // Parse CPU usage using pre-compiled regex
            const textStat = fileStat.text()
            const cpuLine = cpuStatRegex.exec(textStat)
            if (cpuLine) {
                const stats = cpuLine.slice(1).map(Number)
                const total = stats.reduce((a, b) => a + b, 0)
                const idle = stats[3]
                if (previousCpuStats) {
                    const totalDiff = total - previousCpuStats.total
                    const idleDiff = idle - previousCpuStats.idle
                    cpuUsage = totalDiff > 0 ? (1 - idleDiff / totalDiff) : 0
                }
                previousCpuStats = { total, idle }
            }
            // Trigger GPU data collection (non-hybrid NVIDIA uses persistent streaming)
            if (gpuType === "amd") {
                pollAmd()
            } else if (gpuType === "nvidia" && nvidiaHybrid) {
                pollHybridNvidia()
            }
            // Read CPU temperature (only if path was resolved)
            if (cpuTempPath.length > 0) {
                fileCpuTemp.reload()
                const cpuTempText = fileCpuTemp.text().trim()
                if (cpuTempText.length > 0) cpuTemp = Number(cpuTempText) / 1000
            }
            // Read RAM temperature (only if path was resolved)
            if (ramTempPath.length > 0) {
                fileRamTemp.reload()
                const ramTempText = fileRamTemp.text().trim()
                if (ramTempText.length > 0) ramTemp = Number(ramTempText) / 1000
            }
            interval = warmingUp ? 500 : (Config.options?.resources?.updateInterval ?? 3000)
        }
    }
    FileView { id: fileMeminfo; path: "/proc/meminfo" }
    FileView { id: fileStat; path: "/proc/stat" }
    FileView {
        id: fileCpuTemp
        path: "" // Set dynamically by hwmon auto-detection
        onLoadFailed: () => {}
    }
    FileView {
        id: fileRamTemp
        path: "" // Set dynamically by hwmon auto-detection
        onLoadFailed: () => {}
    }
    // GPU detection process - runs once at startup
    Process {
        id: gpuDetectionProcess
        // Output: type, name, then for NVIDIA: sysfs device path, hybrid (1 = another GPU exists and the
        // dGPU can runtime-suspend); for AMD: sysfs device path, temperature file
        command: ["bash", "-c", `
            nv=""; other=0; amd=""; amdv=0
            for d in /sys/bus/pci/devices/*; do
                case "$(cat "$d/class")" in 0x03*) ;; *) continue ;; esac
                if [ "$(cat "$d/vendor")" = 0x10de ]; then nv="$d"; else other=1; fi
                # amdgpu: keep the card with the most VRAM (the dGPU over an iGPU)
                if [ "$(cat "$d/vendor")" = 0x1002 ] && [ -r "$d/gpu_busy_percent" ]; then
                    v=$(cat "$d/mem_info_vram_total" 2>/dev/null || echo 0)
                    if [ "$v" -gt "$amdv" ]; then amd="$d"; amdv="$v"; fi
                fi
            done
            if [ -n "$amd" ]; then
                echo amd
                # Marketing name from AMD's own table (libdrm, device + revision tell e.g. a 7800 XT from a
                # 7700 XT); otherwise the PCI ID database's chip line
                dev=$(cut -c3- "$amd/device" | tr a-f A-F); rev=$(cut -c3- "$amd/revision" | tr a-f A-F)
                name=$(awk -F',[ \t]*' -v d="$dev" -v r="$rev" '$1 == d && $2 == r { print $3; exit }' /usr/share/libdrm/amdgpu.ids 2>/dev/null)
                [ -z "$name" ] && name=$(awk -v d="$(echo "$dev" | tr A-F a-f)" '/^1002/ { v = 1; next } v && /^[0-9a-f]/ { exit } v && $1 == d { $1 = ""; print; exit }' /usr/share/hwdata/pci.ids 2>/dev/null)
                echo "\${name:-AMD GPU}"
                echo "$amd"
                ls "$amd"/hwmon/hwmon*/temp1_input 2>/dev/null | head -1
            elif [ -n "$nv" ] && command -v nvidia-smi >/dev/null 2>&1; then
                echo nvidia
                # The driver's own info file has the model without waking a runtime-suspended dGPU, which
                # asking nvidia-smi did on every shell start; nvidia-smi only if the file isn't there
                name=$(sed -n 's/^Model:[[:space:]]*//p' "/proc/driver/nvidia/gpus/$(basename "$nv")/information" 2>/dev/null)
                [ -z "$name" ] && name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
                echo "\${name}"
                echo "$nv"
                [ "$other" = 1 ] && [ "$(cat "$nv/power/control")" = auto ] && echo 1 || echo 0
            else
                echo unknown
            fi
        `]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                const detectedType = lines[0] ? lines[0].trim() : "unknown"
                gpuType = detectedType
                gpuDetected = (detectedType === "amd" || detectedType === "nvidia")
                let rawName = lines[1] ? lines[1].trim() : ""
                // Clean up to produce short names like "NVIDIA RTX 3060" or "AMD RX 7800 XT"
                rawName = rawName
                    .replace(/^[^\[]*\[(.*)\]\s*$/, "$1")          // "Navi 32 [Radeon RX 7700 XT]" → the bracketed name
                    .replace(/NVIDIA\s+(Corporation\s+)?/i, "")  // strip "NVIDIA Corporation"
                    .replace(/Advanced Micro Devices,? Inc\.?\s*(\[AMD(\/ATI)?\])?/i, "") // strip AMD corp
                    .replace(/^AMD\s+/i, "")                     // the brand is added back below
                    .replace(/GeForce\s+/i, "")                  // strip "GeForce"
                    .replace(/Radeon\s+/i, "")                   // strip "Radeon"
                    .replace(/\s*\[.*?\]/g, "")                  // strip bracketed substrings
                    .replace(/\s*\(rev.*\)/g, "")                // strip rev info
                    .replace(/\s*Mobile.*$/i, "")                // strip Mobile / Max-Q etc
                    .replace(/\s*Laptop.*$/i, "")                // strip Laptop GPU suffix
                    .replace(/^\s+|\s+$/g, "")                   // trim
                // Prefix with brand
                if (detectedType === "nvidia" && rawName) {
                    gpuName = "NVIDIA " + rawName
                } else if (detectedType === "amd" && rawName) {
                    gpuName = "AMD " + rawName
                } else {
                    gpuName = detectedType === "amd" ? "AMD GPU" : detectedType === "nvidia" ? "NVIDIA GPU" : ""
                }
                if (detectedType === "amd") {
                    amdDevicePath = lines[2] ? lines[2].trim() : ""
                    amdTempPath = lines[3] ? lines[3].trim() : ""
                }
                if (detectedType === "nvidia") {
                    nvidiaDevicePath = lines[2] ? lines[2].trim() : ""
                    nvidiaHybrid = lines[3]?.trim() === "1" && nvidiaDevicePath.length > 0
                    // Hybrid dGPUs are polled from the main timer so they can runtime-suspend
                    if (!nvidiaHybrid) {
                        nvidiaUptimeTimer.start()
                        nvidiaStreamProcess.running = true
                    }
                }
            }
        }
    }
    function parseNvidiaLine(data) {
        const values = data.trim().split(',').map(v => v.trim())
        if (values.length >= 4) {
            gpuUsage = Number(values[0]) / 100
            vramUsed = Number(values[1]) / 1024  // Convert MB to GB
            vramTotal = Number(values[2]) / 1024  // Convert MB to GB
            gpuTemp = Number(values[3])
        }
    }
    // Hybrid laptops: nvidia-smi wakes the dGPU, and polling it keeps it from ever
    // runtime-suspending. Only query when it's already awake, and back off while idle.
    property string nvidiaDevicePath: ""
    property bool nvidiaHybrid: false
    property int _nvidiaSkipTicks: 0
    // The dGPU is runtime-suspended (powered down while idle): its numbers aren't readings, it's off
    property bool gpuAsleep: false
    function pollHybridNvidia() {
        nvidiaPowerStatus.reload()
        gpuAsleep = nvidiaPowerStatus.text().trim() !== "active"
        if (gpuAsleep) {
            gpuUsage = 0
            vramUsed = 0
            gpuTemp = 0
            _nvidiaSkipTicks = 0
            return
        }
        if (_nvidiaSkipTicks > 0) {
            _nvidiaSkipTicks--
            return
        }
        if (!nvidiaQueryProcess.running) nvidiaQueryProcess.running = true
    }
    FileView {
        id: nvidiaPowerStatus
        blockAllReads: true
        path: root.nvidiaDevicePath.length > 0 ? `${root.nvidiaDevicePath}/power/runtime_status` : ""
        onLoadFailed: () => {}
    }
    Process {
        id: nvidiaQueryProcess
        command: ["nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu", "--format=csv,noheader,nounits"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.parseNvidiaLine(text)
                root._nvidiaSkipTicks = root.gpuUsage > 0 ? 0 : 9
            }
        }
    }
    // Persistent NVIDIA GPU monitoring via nvidia-smi streaming mode (non-hybrid only)
    // Uses --loop-ms to output a new CSV line at the configured interval,
    // avoiding the overhead of spawning a new process every poll cycle
    property int _nvidiaRetries: 0
    readonly property int _nvidiaMaxRetries: 5
    property bool _nvidiaStable: false
    property string _nvidiaLastError: ""
    Process {
        id: nvidiaStreamProcess
        command: ["nvidia-smi",
            "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu",
            "--format=csv,noheader,nounits",
            `--loop-ms=${Config.options?.resources?.updateInterval ?? 3000}`]
        running: false
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    _nvidiaLastError = text.trim()
                }
            }
        }
        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return
                // Only reset retries if stream has been up long enough (not just initial partial output)
                if (_nvidiaStable) {
                    _nvidiaRetries = 0
                }
                _nvidiaLastError = ""
                root.parseNvidiaLine(data)
            }
        }
        onExited: (exitCode, exitStatus) => {
            const reason = _nvidiaLastError.length > 0
                ? _nvidiaLastError.split('\n')[0]
                : `exit code ${exitCode}`
            if (gpuType === "nvidia" && _nvidiaRetries < _nvidiaMaxRetries) {
                _nvidiaRetries++
                _nvidiaStable = false
                console.warn(`[ResourceUsage] nvidia-smi failed (${reason}), retry ${_nvidiaRetries}/${_nvidiaMaxRetries}...`)
                nvidiaRetryTimer.start()
            } else if (_nvidiaRetries >= _nvidiaMaxRetries) {
                console.warn(`[ResourceUsage] nvidia-smi failed after max retries (${reason}), giving up. GPU monitoring disabled.`)
            }
        }
    }
    Timer {
        id: nvidiaRetryTimer
        interval: 2000
        repeat: false
        onTriggered: {
            nvidiaUptimeTimer.restart()
            nvidiaStreamProcess.running = true
        }
    }
    // Tracks whether nvidia-smi has been running long enough to consider it stable
    Timer {
        id: nvidiaUptimeTimer
        interval: 10000
        repeat: false
        onTriggered: _nvidiaStable = true
    }
    // AMD: read amdgpu's sysfs files directly. Spawning rocm-smi (a Python tool) every poll cost
    // ~80 ms of CPU each time and logged an error whenever the GPU was in a low-power state.
    // A runtime-suspended GPU refuses these reads instead of waking up, which just reads as idle
    property string amdDevicePath: ""
    property string amdTempPath: ""
    FileView { id: amdBusyFile; path: root.amdDevicePath ? root.amdDevicePath + "/gpu_busy_percent" : ""; onLoadFailed: () => {} }
    FileView { id: amdVramUsedFile; path: root.amdDevicePath ? root.amdDevicePath + "/mem_info_vram_used" : ""; onLoadFailed: () => {} }
    FileView { id: amdVramTotalFile; path: root.amdDevicePath ? root.amdDevicePath + "/mem_info_vram_total" : ""; onLoadFailed: () => {} }
    FileView { id: amdTempFile; path: root.amdTempPath; onLoadFailed: () => {} }
    function pollAmd() {
        if (!amdDevicePath) return
        const num = (f, fallback) => { f.reload(); const n = parseInt(f.text()); return isNaN(n) ? fallback : n }
        gpuUsage = num(amdBusyFile, 0) / 100
        const gib = 1024 * 1024 * 1024
        vramUsed = num(amdVramUsedFile, 0) / gib
        if (vramTotal === 0) vramTotal = num(amdVramTotalFile, 0) / gib
        if (amdTempPath) { const t = num(amdTempFile, 0); if (t > 0) gpuTemp = t / 1000 }
    }
}
