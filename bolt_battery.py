#!/usr/bin/env python3
"""Talk HID++ 2.0 to a Logitech Bolt receiver via macOS IOKit. No deps."""

import ctypes
import struct
import sys
import time
from ctypes import (
    CFUNCTYPE, POINTER, byref, c_char_p, c_double, c_int, c_int32,
    c_long, c_uint8, c_uint32, c_void_p, sizeof,
)

IOKIT = ctypes.CDLL("/System/Library/Frameworks/IOKit.framework/IOKit")
CF = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")

CFTypeRef = c_void_p
CFAllocatorRef = c_void_p
CFStringRef = c_void_p
CFNumberRef = c_void_p
CFDictionaryRef = c_void_p
CFMutableDictionaryRef = c_void_p
CFSetRef = c_void_p
CFRunLoopRef = c_void_p
CFIndex = c_long

kCFStringEncodingUTF8 = 0x08000100
kCFNumberSInt32Type = 3

CF.CFNumberCreate.restype = CFNumberRef
CF.CFNumberCreate.argtypes = [CFAllocatorRef, c_int, c_void_p]
CF.CFStringCreateWithCString.restype = CFStringRef
CF.CFStringCreateWithCString.argtypes = [CFAllocatorRef, c_char_p, c_uint32]
CF.CFDictionaryCreateMutable.restype = CFMutableDictionaryRef
CF.CFDictionaryCreateMutable.argtypes = [CFAllocatorRef, CFIndex, c_void_p, c_void_p]
CF.CFDictionarySetValue.restype = None
CF.CFDictionarySetValue.argtypes = [CFMutableDictionaryRef, c_void_p, c_void_p]
CF.CFRelease.restype = None
CF.CFRelease.argtypes = [CFTypeRef]
CF.CFRunLoopGetCurrent.restype = CFRunLoopRef
CF.CFRunLoopGetCurrent.argtypes = []
CF.CFRunLoopRunInMode.restype = c_int32
CF.CFRunLoopRunInMode.argtypes = [CFStringRef, c_double, c_int32]
kCFRunLoopDefaultMode = c_void_p.in_dll(CF, "kCFRunLoopDefaultMode")
CF.CFSetGetCount.restype = CFIndex
CF.CFSetGetCount.argtypes = [CFSetRef]
CF.CFSetGetValues.restype = None
CF.CFSetGetValues.argtypes = [CFSetRef, POINTER(c_void_p)]

IOHIDManagerRef = c_void_p
IOHIDDeviceRef = c_void_p
IOReturn = c_int32

kIOHIDReportTypeOutput = 1

IOKIT.IOHIDManagerCreate.restype = IOHIDManagerRef
IOKIT.IOHIDManagerCreate.argtypes = [CFAllocatorRef, c_uint32]
IOKIT.IOHIDManagerSetDeviceMatching.restype = None
IOKIT.IOHIDManagerSetDeviceMatching.argtypes = [IOHIDManagerRef, CFDictionaryRef]
IOKIT.IOHIDManagerOpen.restype = IOReturn
IOKIT.IOHIDManagerOpen.argtypes = [IOHIDManagerRef, c_uint32]
IOKIT.IOHIDManagerCopyDevices.restype = CFSetRef
IOKIT.IOHIDManagerCopyDevices.argtypes = [IOHIDManagerRef]
IOKIT.IOHIDDeviceOpen.restype = IOReturn
IOKIT.IOHIDDeviceOpen.argtypes = [IOHIDDeviceRef, c_uint32]
IOKIT.IOHIDDeviceClose.restype = IOReturn
IOKIT.IOHIDDeviceClose.argtypes = [IOHIDDeviceRef, c_uint32]
IOKIT.IOHIDDeviceSetReport.restype = IOReturn
IOKIT.IOHIDDeviceSetReport.argtypes = [
    IOHIDDeviceRef, c_uint32, CFIndex, c_void_p, CFIndex
]

IOHIDReportCallback = CFUNCTYPE(
    None, c_void_p, IOReturn, c_void_p, c_uint32, c_uint32, c_void_p, CFIndex
)
IOKIT.IOHIDDeviceRegisterInputReportCallback.restype = None
IOKIT.IOHIDDeviceRegisterInputReportCallback.argtypes = [
    IOHIDDeviceRef, c_void_p, CFIndex, IOHIDReportCallback, c_void_p
]
IOKIT.IOHIDDeviceScheduleWithRunLoop.restype = None
IOKIT.IOHIDDeviceScheduleWithRunLoop.argtypes = [
    IOHIDDeviceRef, CFRunLoopRef, CFStringRef
]


def cf_str(s):
    return CF.CFStringCreateWithCString(None, s.encode("utf-8"), kCFStringEncodingUTF8)


def cf_int(v):
    n = c_int32(v)
    return CF.CFNumberCreate(None, kCFNumberSInt32Type, byref(n))


def make_match(vid, pid, usage_page):
    d = CF.CFDictionaryCreateMutable(None, 0, None, None)
    CF.CFDictionarySetValue(d, cf_str("VendorID"), cf_int(vid))
    CF.CFDictionarySetValue(d, cf_str("ProductID"), cf_int(pid))
    CF.CFDictionarySetValue(d, cf_str("PrimaryUsagePage"), cf_int(usage_page))
    return d


LOGITECH_VID = 0x046D
BOLT_PID = 0xC548
HIDPP_USAGE_PAGE = 0xFF00

REPORT_SHORT = 0x10
REPORT_LONG = 0x11
SWID = 0x0F

F_ROOT = 0x0000
F_FEATURE_SET = 0x0001
F_DEVICE_INFO = 0x0003
F_DEVICE_NAME = 0x0005
F_BATTERY_LEGACY = 0x1000
F_BATTERY_UNIFIED = 0x1004


class BoltClient:
    def __init__(self, debug=False):
        self.debug = debug
        self.manager = None
        self.device = None
        self._inbuf = (c_uint8 * 64)()
        self._cb = None
        self._last = None  # (report_id, bytes)

    def open(self):
        self.manager = IOKIT.IOHIDManagerCreate(None, 0)
        if not self.manager:
            raise RuntimeError("IOHIDManagerCreate failed")
        IOKIT.IOHIDManagerSetDeviceMatching(
            self.manager, make_match(LOGITECH_VID, BOLT_PID, HIDPP_USAGE_PAGE)
        )
        ret = IOKIT.IOHIDManagerOpen(self.manager, 0)
        if ret:
            raise RuntimeError(f"IOHIDManagerOpen failed: 0x{ret & 0xFFFFFFFF:08X}")
        devs = IOKIT.IOHIDManagerCopyDevices(self.manager)
        if not devs:
            raise RuntimeError("No matching HID device (Bolt receiver not present?)")
        n = CF.CFSetGetCount(devs)
        if n == 0:
            raise RuntimeError("Empty device set")
        arr = (c_void_p * n)()
        CF.CFSetGetValues(devs, arr)
        self.device = arr[0]
        ret = IOKIT.IOHIDDeviceOpen(self.device, 0)
        if ret:
            raise RuntimeError(f"IOHIDDeviceOpen failed: 0x{ret & 0xFFFFFFFF:08X}")

        client = self

        @IOHIDReportCallback
        def cb(ctx, result, sender, rtype, rid, report, length):
            data = bytes((c_uint8 * length).from_address(report))
            # macOS IOKit prefixes the report ID into the buffer for numbered
            # reports, so the HID++ payload starts at data[1].
            if data and data[0] == int(rid):
                data = data[1:]
            client._last = (int(rid), data)
            if client.debug:
                print(f"  <<< rid=0x{rid:02x} len={length} payload={data.hex()}")

        self._cb = cb
        IOKIT.IOHIDDeviceRegisterInputReportCallback(
            self.device, self._inbuf, sizeof(self._inbuf), cb, None
        )
        IOKIT.IOHIDDeviceScheduleWithRunLoop(
            self.device, CF.CFRunLoopGetCurrent(), kCFRunLoopDefaultMode
        )

    def close(self):
        if self.device:
            IOKIT.IOHIDDeviceClose(self.device, 0)
            self.device = None

    def call(self, device_idx, feature_idx, function, params=b"", timeout=2.5):
        buf = bytearray(20)
        buf[0] = REPORT_LONG
        buf[1] = device_idx
        buf[2] = feature_idx
        buf[3] = (function << 4) | (SWID & 0x0F)
        for i, p in enumerate(params[:16]):
            buf[4 + i] = p

        if self.debug:
            print(f"  >>> rid=0x11 dev={device_idx:#04x} feat={feature_idx:#04x} "
                  f"fn={function} swid={SWID} params={bytes(params).hex()}")

        self._last = None
        cbuf = (c_uint8 * 20).from_buffer(buf)
        ret = IOKIT.IOHIDDeviceSetReport(
            self.device, kIOHIDReportTypeOutput, REPORT_LONG, cbuf, 20
        )
        if ret:
            return None, f"SetReport=0x{ret & 0xFFFFFFFF:08X}"

        deadline = time.time() + timeout
        while time.time() < deadline:
            CF.CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, False)
            if self._last is None:
                continue
            rid, data = self._last
            self._last = None  # consume; ignore if it isn't ours
            if len(data) < 4:
                continue
            if data[0] != device_idx:
                continue  # response for a different device, drop it
            # HID++ 1.0 error: sub_id 0x8F, error code at byte 4
            if data[1] == 0x8F:
                if data[3] != ((function << 4) | (SWID & 0x0F)):
                    continue
                err_code = data[4]
                names = {
                    0x01: "InvalidSubID", 0x02: "InvalidAddress",
                    0x03: "InvalidValue", 0x04: "ConnectionNotEstablished",
                    0x05: "TooManyDevices", 0x06: "AlreadyExists",
                    0x07: "Busy", 0x08: "UnknownDevice",
                    0x09: "ResourceError", 0x0A: "RequestUnavailable",
                    0x0B: "InvalidParamValue", 0x0C: "WrongPINCode",
                }
                return None, f"HID++1 err {err_code:#04x} ({names.get(err_code, '?')})"
            # HID++ 2.0 error: feature_idx becomes 0xFF
            if data[1] == 0xFF:
                if (data[3], data[4] >> 4) != (feature_idx, function):
                    continue
                err = data[5] if len(data) >= 6 else 0
                names = {
                    0x01: "Unknown", 0x02: "InvalidArgument", 0x03: "OutOfRange",
                    0x04: "HWError", 0x05: "LogitechInternal", 0x06: "InvalidFeatureIndex",
                    0x07: "InvalidFunctionID", 0x08: "Busy", 0x09: "Unsupported",
                }
                return None, f"HID++2 err {err:#04x} ({names.get(err, '?')})"
            # Real response: must echo our feature & swid
            if data[1] != feature_idx:
                continue
            if (data[2] & 0x0F) != (SWID & 0x0F):
                continue
            return data, None
        return None, "timeout"

    def get_feature_index(self, device_idx, feature_id):
        params = bytes([(feature_id >> 8) & 0xFF, feature_id & 0xFF])
        data, err = self.call(device_idx, F_ROOT, 0x00, params)
        if err:
            return None, err
        feat_idx = data[3]
        if feat_idx == 0:
            return None, "not supported"
        return feat_idx, None

    def get_protocol_version(self, device_idx, timeout=2.5):
        # Root.GetProtocolVersion (function 1) — also acts as a ping; pingdata=0xAA
        data, err = self.call(device_idx, F_ROOT, 0x01,
                              bytes([0, 0, 0xAA]), timeout=timeout)
        if err:
            return None, err
        return (data[3], data[4], data[5]), None

    def get_device_name(self, device_idx):
        feat_idx, err = self.get_feature_index(device_idx, F_DEVICE_NAME)
        if err:
            return None, err
        data, err = self.call(device_idx, feat_idx, 0x00)  # GetDeviceNameLength
        if err:
            return None, err
        length = data[3]
        out = bytearray()
        offset = 0
        while offset < length:
            d, err = self.call(device_idx, feat_idx, 0x01, bytes([offset]))
            if err:
                return None, err
            chunk = d[3:3 + min(length - offset, 16)]
            if not chunk:
                break
            out.extend(chunk)
            offset += len(chunk)
        return bytes(out).rstrip(b"\x00").decode("utf-8", "replace"), None

    def get_device_type(self, device_idx):
        feat_idx, err = self.get_feature_index(device_idx, F_DEVICE_NAME)
        if err:
            return None, err
        data, err = self.call(device_idx, feat_idx, 0x02)  # GetDeviceType
        if err:
            return None, err
        types = {
            0: "Keyboard", 1: "RemoteControl", 2: "Numpad", 3: "Mouse",
            4: "Trackpad", 5: "Trackball", 6: "Presenter", 7: "Receiver",
            8: "Headset", 9: "Webcam", 10: "SteeringWheel", 11: "Joystick",
            12: "Gamepad", 13: "Dock", 14: "Speaker", 15: "Microphone",
            16: "IlluminationLight", 17: "ProgrammableController",
            18: "CarSimPedals", 19: "Adapter",
        }
        return types.get(data[3], f"Unknown({data[3]})"), None

    def get_battery(self, device_idx):
        feat_idx, _ = self.get_feature_index(device_idx, F_BATTERY_UNIFIED)
        if feat_idx is not None:
            data, err = self.call(device_idx, feat_idx, 0x01)  # GetStatus
            if not err:
                charge_state = {
                    0: "discharging", 1: "charging", 2: "charging-slow",
                    3: "charging-full", 4: "charging-error",
                }.get(data[5], f"unknown({data[5]})")
                return {
                    "feature": "UnifiedBattery (0x1004)",
                    "soc_percent": data[3],
                    "endpoint_remaining": data[4],
                    "charging": charge_state,
                    "external_power": bool(data[6]) if len(data) > 6 else None,
                    "raw": data[3:8].hex(),
                }, None
        feat_idx, _ = self.get_feature_index(device_idx, F_BATTERY_LEGACY)
        if feat_idx is not None:
            data, err = self.call(device_idx, feat_idx, 0x00)
            if not err:
                status_map = {
                    0: "discharging", 1: "recharging", 2: "almost-full",
                    3: "full", 4: "slow-recharge", 5: "invalid-battery",
                    6: "thermal-error",
                }
                return {
                    "feature": "BatteryUnifiedLevelStatus (0x1000)",
                    "soc_percent": data[3],
                    "next_soc_percent": data[4],
                    "status": status_map.get(data[5], f"unknown({data[5]})"),
                    "raw": data[3:8].hex(),
                }, None
        return None, "no battery feature exposed"

    def get_firmware(self, device_idx):
        feat_idx, err = self.get_feature_index(device_idx, F_DEVICE_INFO)
        if err:
            return None, err
        data, err = self.call(device_idx, feat_idx, 0x00)  # GetCount
        if err:
            return None, err
        count = data[3]
        firmwares = []
        for i in range(count):
            d, err = self.call(device_idx, feat_idx, 0x01, bytes([i]))
            if err:
                continue
            kind_map = {0: "MainApp", 1: "Bootloader", 2: "Hardware"}
            kind = kind_map.get(d[3] & 0x0F, f"k{d[3]:#x}")
            name = bytes(d[4:7]).decode("ascii", "replace").rstrip("\x00")
            ver = f"{d[7]:02x}.{d[8]:02x}.B{(d[9] << 8) | d[10]:04X}"
            firmwares.append(f"{kind} {name} v{ver}")
        return firmwares, None


def main():
    debug = "--debug" in sys.argv
    bolt = BoltClient(debug=debug)
    try:
        bolt.open()
    except RuntimeError as e:
        print(f"FAILED: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"✓ Bolt receiver opened (device handle 0x{bolt.device:x})\n")

    found = 0
    try:
        for idx in range(1, 7):
            ver, err = bolt.get_protocol_version(idx)
            if err:
                if debug:
                    print(f"--- Device #{idx}: {err}")
                continue
            found += 1
            print(f"━━━ Device #{idx} ━━━")
            print(f"  HID++ protocol: {ver[0]}.{ver[1]} (echo {ver[2]:#04x})")

            dtype, err = bolt.get_device_type(idx)
            print(f"  Type:           {dtype if not err else f'<{err}>'}")

            name, err = bolt.get_device_name(idx)
            print(f"  Name:           {name if not err else f'<{err}>'}")

            bat, err = bolt.get_battery(idx)
            if not err:
                soc = bat.get("soc_percent")
                feat = bat["feature"]
                extra = []
                if "charging" in bat:
                    extra.append(bat["charging"])
                if bat.get("external_power"):
                    extra.append("plugged in")
                if "status" in bat:
                    extra.append(bat["status"])
                tail = f" [{', '.join(extra)}]" if extra else ""
                print(f"  Battery:        {soc}%{tail}  ({feat})")
            else:
                print(f"  Battery:        <{err}>")

            fw, err = bolt.get_firmware(idx)
            if not err and fw:
                for line in fw:
                    print(f"  Firmware:       {line}")
            print()
        if found == 0:
            print("No paired devices answered. Wake them (touch a key/move the mouse) and re-run.")
    finally:
        bolt.close()


if __name__ == "__main__":
    main()
