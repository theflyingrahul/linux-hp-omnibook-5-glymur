#!/usr/bin/env python3
"""Classify the Windows PnP inventory (devices.tsv) against the Linux state.

Usage: map-windows-devices.py devices.tsv out.tsv
Each rule is (regex on "name|instance id", area, state, note); first match wins.
States: working, partial, failing, visible (bound, not exercised), absent, n/a.
"""
import csv, re, sys, collections

R = [
 (r"Oryon", "CPU", "working", "12 CPUs, scmi cpufreq, cluster idle used"),
 (r"Hexagon.*NP|NSP0 CDSP|Compute DSP Subsystem|Audio Rpc|FastRPC|QCOM0F82|QCOM0F5C", "DSP", "visible", "cdsp/adsp remoteprocs running, /dev/fastrpc-*; no compute workload tried"),
 (r"Audio DSP Subsystem|VEN_QCOM&DEV_0F1B", "DSP", "working", "adsp running with HP qcadsp8480.mbn"),
 (r"Adreno", "GPU", "working", "adreno bound, /dev/dri/renderD128 (needs Mesa 26.2 from /opt/mesa-glymur)"),
 (r"Integrated Monitor", "Display", "working", "eDP panel (Samsung ATNA), DP AUX backlight"),
 (r"Basic Display|Basic Render|Display Services", "Display", "n/a", "Windows software"),
 (r"EVA Device", "Video", "visible", "evacc clock controller bound"),
 (r"SAMSUNG|NVM Express", "Storage", "working", "nvme on pcie5"),
 (r"Wi-Fi 7|^Wi-Fi\||SWD\|RADIO.*Wi-Fi", "Wi-Fi", "working", "ath12k, wlo1 up"),
 (r"Aqstic\(TM\) BT ACX|QCOM0FEA", "Bluetooth", "absent", "BT audio offload (ACX) not used; A2DP works through the host"),
 (r"Bluetooth UART|QCOM0F6B|FastConnect C7700 NCM820A Bluetooth|UART_H4_CLG|Bluetooth\|", "Bluetooth", "working", "hci0 up on GENI UART; A2DP playback confirmed; RF calibration file qca/ornbcscal11.bin missing"),
 (r"MS_BTH|MS_RFCOMM|Bluetooth Device|BTHLE|Bluetooth LE|Personal Area|Radio Device Enum", "Bluetooth", "n/a", "Windows stack"),
 (r"HP IR Camera", "Camera", "working", "grey 400x400 frame captured"),
 (r"HP True Vision|USB Composite Device", "Camera", "working", "RGB frame captured; uvcvideo"),
 (r"Camera DFU", "Camera", "absent", "firmware-update interface, no driver and not needed"),
 (r"Windows Studio Effects|Rts-DMFT", "Camera", "n/a", "Windows software"),
 (r"QTEC0001|Keyboard Device|CONVERTEDDEVICE|BUTTONCONVER|Portable Device Control|ACPI0011|HID Button", "Input", "working", "keyboard on i2c 0-003a; consumer keys through it"),
 (r"ELAN0189|ELAN Input|ELAN PrecisionTouchpad|ELAN Consumer|ELAN HID Class|Input Configuration", "Input", "working", "touchpad on i2c 4-0015"),
 (r"ELAN&DEV_2513|touch screen", "Input", "working", "touchscreen on i2c 8-0010 (tested by hand)"),
 (r"I2C HID Device", "Input", "working", "bound by i2c_hid_of"),
 (r"VHF|HID_DEVICE_SYSTEM|Virtual HID", "Input", "n/a", "Windows virtual HID"),
 (r"SoundWire HID", "Audio", "absent", "headset-button function not enumerated on SoundWire"),
 (r"ACX Static Endpoints|Static Endpoints|MMDEVAPI.*(Speakers|Microphone)|QCASD", "Audio", "partial", "microphones work; speakers silent (amplifiers UNATTACHED)"),
 (r"Microphone Array", "Audio", "working", "DMIC capture records a real signal"),
 (r"Speakers \(", "Audio", "failing", "both WSA884x amplifiers UNATTACHED on this boot"),
 (r"HEADSET", "Audio", "partial", "headset jack input device registers; path not retested on -15"),
 (r"SoundWire Controller|ADCM.*0FF6", "Audio", "working", "qcom-soundwire master bound (swr0 for the amplifiers)"),
 (r"SoundWire Audio|SDCA_|SoundWire Audio Multifunction|0FB7|0FCD|0FF4|Aqstic\(TM\) ACX Audio|Aqstic\(TM\)\|", "Audio", "partial", "ASoC card up; amplifier function absent; no SDCA headset codec on the bus"),
 (r"Calibration Manager|DEV_0F22|Sound Model|ASD Audio|Fluence|Voice Clarity|VoiceAssistant|Audio Compositor|ACPI0018|QCSDCA", "Audio", "n/a", "Windows audio processing / no Linux counterpart"),
 (r"Mute LED|HPIC0005", "EC", "failing", "EC driver did not bind on -15 (thermal zone name too long); fixed for -16"),
 (r"HP Application Driver|HPIC0003|HP Application Enabling", "EC", "failing", "HP WMI/EC services: EC driver not bound; no HP WMI on arm64"),
 (r"ACPI Fan|PNP0C0B", "EC", "failing", "fan speed comes from the EC driver (not bound on -15)"),
 (r"ACPI Lid|PNP0C0D", "EC", "working", "gpio-keys lid switch registered"),
 (r"AC Adapter|ACPI0003|Control Method Battery|PNP0C0A|PMIC GLink|QCOM0F8E|QCOM0F77|FGBCL|ACPI Bridge|QCOM1045|Charge Arbitration", "Power", "working", "qcom_battmgr: battery, AC, USB power supplies"),
 (r"USBC000|UCM-UCSI|Type-C|QCOM0F9D", "USB-C", "partial", "UCSI ports registered; USB-C data works; DisplayPort over USB-C crashed the machine"),
 (r"eXtensible Host|Dual-Role|USB Root Hub|QCOM0F9A|QCOM0FEF|QCOM0F8B|QCOM0F8C", "USB", "working", "xhci and dwc3 bound; USB-A SuperSpeed stick in use"),
 (r"Pluton|PLUTONQC", "Security", "n/a", "Windows security processor"),
 (r"Trusted Platform Module|TREETPM", "Security", "absent", "no /dev/tpm (TPM2 start method 9 not supported)"),
 (r"Secure Processor|QCOM0F87|Secure Kernel|QCOM0FA5|Secure Services|QCOM1004|Secapp|QCOM0FCC|SCM Device|QCOM1001|QCOM0F8D|Connection Security|QCOM0FA1|BcryptCipher|Inline Crypto|QCOM103D|Control Processor|QCOM1036", "Security", "visible", "soccp remoteproc attached, qcom_scm and qcomtee bound; crypto engines have no Linux use yet"),
 (r"Human Presence|QCOM0FF8", "Sensors", "absent", "no IIO device"),
 (r"All-Ways Aware|QCOM0693|QCOM0694|Analog-to-Digital|QCOM0F11", "Sensors", "absent", "no IIO device"),
 (r"Temperature Sensor|Thermal Zone|THERMALZONE|Thermal Mitigation|QCOM1005|Wlan Thermal", "Thermal", "working", "tsens: 6 controllers, about 60 zones; EC thermistors missing on -15"),
 (r"PowerLimits|QCOM103F", "Power policy", "partial", "qcom_spel energy counters work; no limits readable"),
 (r"DCVS|Core parking|GPU limits|NSP limits|Modem|WLAN Limits|Policy Device|CUST8480", "Power policy", "partial", "cpufreq through SCMI; the other Windows policy devices have no Linux counterpart"),
 (r"Pep|Power Engine|QSTF|SBOD|PPTE|QCOM1042|Reset Power|QCOM1000|Power Management PMIC Device|PML0|QCOM0F2B|QCOM0FC6", "Power policy", "visible", "PMIC and RPMh power domains bound"),
 (r"SPMI Bus|SPI Bus|Bam Bus|Bus Device|I2C Bus|GPIO Device|PMIC GPIO|QCOM0F0B|QCOM0F0E|QCOM0F0A|QCOM0F88|QCOM0F16|QCOM0F10|QCOM0F0C|QCOM0F2D", "Buses", "working", "SPMI, GPI DMA, BAM, 4 of 5 I2C controllers, BT UART bound"),
 (r"IOMMU|QCOM0FF9|System Cache|VEN_QCOM&DEV_0F83|Shared Memory|QCOM0F84|Data IPC|QCOM0F0D|Inter Processor|QCOM1046|SOC Partition|QCOM0FFD|Subsystem Dependency|QCOM0F20|System Manager|QCOM0F85|QCOM103E|QCOM0F2F|Protection Domain|Peripheral Image|DCF Device|SenD|QCOM1047|QcSocService|QCOM103B|DEV_0FFA|DEV_0FFB|TFTP|QCOM0FFE", "SoC plumbing", "visible", "smmu, llcc, smem, ipcc, glink, pd-mapper, remoteproc loaders bound"),
 (r"PCI Express|PCIe Platform|PNP0A08|QCOM0F96", "PCIe", "working", "pcie4 (Wi-Fi) and pcie5 (NVMe) up"),
 (r"Generic Bus|PNP0A05|ACPI Devices driver|ACPI0013|Processor Aggregator|Processor Container|Wake Alarm|ACPI000E|Management Interface for ACPI|PNP0C14|ACPI-Compliant System|UEFI-Compliant|ACPI ARM64", "Platform", "n/a", "ACPI plumbing (this is a device-tree boot)"),
 (r"Device Firmware|System Firmware", "Firmware", "n/a", "UEFI capsule resources; fwupd is masked on purpose"),
]
NA = r"Hyper-V|Hypervisor|VMBus|VMS_|RRAS|WAN Miniport|Print|Volume|VOLMGR|Storage Spaces|Kernel Debug|NDIS|UMBus|RDP|Remote Desktop|Composite Bus|Plug and Play|Root Print|Windows Hello|Wavetable|Streaming Service|Device Association|SMBIOS|Virtual Drive|Generic software|COMPUTER|Generic volume|ROOT\|SYSTEM|HTREE|Microsoft Windows Trusted"

def main(src, dst):
    rows = list(csv.DictReader(open(src, encoding="utf-8-sig"), delimiter="\t"))
    out, count = [], collections.Counter()
    for r in rows:
        name = r["FriendlyName"] or r["Name"] or r["Description"]
        key = name + "|" + r["InstanceId"]
        for pat, area, state, note in R:
            if re.search(pat, key, re.I):
                break
        else:
            if re.search(NA, key, re.I):
                area, state, note = "Windows-only", "n/a", "virtual or Windows-specific"
            else:
                area, state, note = "unclassified", "unknown", ""
        out.append((area, state, name, r["InstanceId"].split("\\")[0] + "\\" + (r["InstanceId"].split("\\")[1][:40] if "\\" in r["InstanceId"] else ""), note))
        count[state] += 1
    out.sort()
    with open(dst, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, delimiter="\t", lineterminator="\n")
        w.writerow(["area", "linux_state", "windows_name", "windows_id", "note"])
        w.writerows(out)
    print(len(rows), dict(count))
    for o in out:
        if o[1] == "unknown":
            print("UNCLASSIFIED:", o[2], o[3])

main(sys.argv[1], sys.argv[2])
