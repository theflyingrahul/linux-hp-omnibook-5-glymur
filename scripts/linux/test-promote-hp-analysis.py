#!/usr/bin/env python3
"""Regression checks for additive HP candidate promotion."""

import importlib.util
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("promote-hp-analysis.py")
spec = importlib.util.spec_from_file_location("promote_hp_analysis", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PromotionTests(unittest.TestCase):
    def test_malformed_reference_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            hardware = root / "hardware-id-candidates.tsv"
            hardware.write_text(
                "hardware_id\tprovider\tinf_source\tevidence\n"
                "ACPI\\OLD0001\tOriginal\n", encoding="utf-8"
            )
            with self.assertRaisesRegex(ValueError, "Malformed TSV row"):
                module.read_rows(hardware, module.HARDWARE_COLUMNS)

    def test_empty_analysis_cannot_change_references(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest = root / "analysis.txt"
            manifest.write_text("Subsystem String Matches:\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "No INF hardware IDs"):
                module.promote(manifest, root, True)

    def test_dry_run_and_additive_idempotent_merge(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            hardware = root / "hardware-id-candidates.tsv"
            firmware = root / "firmware-candidates.tsv"
            hardware.write_text(
                "hardware_id\tprovider\tinf_source\tevidence\n"
                "ACPI\\OLD0001\tOriginal\told.inf\tMANUAL\n", encoding="utf-8"
            )
            firmware.write_text(
                "firmware_name\tinf_source\tevidence\n"
                "old.bin\told.inf\tMANUAL\n", encoding="utf-8"
            )
            manifest = root / "analysis.txt"
            manifest.write_text(
                "Inventorying INFs...\n----------------------------------------\n"
                "INF: C:\\Drivers\\new.inf\nprovider: Qualcomm\n"
                "hw_ids: ACPI\\QCOM0F10\nfirmware_refs: new.bin\n"
                "----------------------------------------\nSubsystem String Matches:\n",
                encoding="utf-8",
            )

            before = (hardware.read_bytes(), firmware.read_bytes())
            module.promote(manifest, root, False)
            self.assertEqual(before, (hardware.read_bytes(), firmware.read_bytes()))

            module.promote(manifest, root, True)
            self.assertEqual(
                module.read_rows(hardware, module.HARDWARE_COLUMNS),
                [
                    ("ACPI\\OLD0001", "Original", "old.inf", "MANUAL"),
                    ("ACPI\\QCOM0F10", "Qualcomm", "new.inf", "HP-SOFTWARE"),
                ],
            )
            self.assertEqual(
                module.read_rows(firmware, module.FIRMWARE_COLUMNS),
                [("old.bin", "old.inf", "MANUAL"), ("new.bin", "new.inf", "HP-SOFTWARE")],
            )
            after = (hardware.read_bytes(), firmware.read_bytes())
            module.promote(manifest, root, True)
            self.assertEqual(after, (hardware.read_bytes(), firmware.read_bytes()))


if __name__ == "__main__":
    unittest.main()
