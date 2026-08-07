#!/usr/bin/env python3
"""Phase 0 probe: enumerate USB HID devices, show STC ones (VID 0x34BF)."""
from hid_loader import ensure_hidapi_available

ensure_hidapi_available()
import hid

STC_VID = 0x34BF

found = []
for d in hid.enumerate():
    if d["vendor_id"] == STC_VID:
        found.append(d)

if not found:
    print("NO STC (0x34BF) HID DEVICE FOUND")
    print("All HID devices:")
    for d in hid.enumerate():
        print("  vid=%04x pid=%04x product=%r usage_page=%04x usage=%04x"
              % (d["vendor_id"], d["product_id"], d.get("product_string"),
                 d.get("usage_page"), d.get("usage")))
else:
    print("Found %d STC HID device(s):" % len(found))
    for d in found:
        print("  vid=%04x pid=%04x product=%r usage_page=%04x usage=%04x"
              % (d["vendor_id"], d["product_id"], d.get("product_string"),
                 d.get("usage_page"), d.get("usage")))
