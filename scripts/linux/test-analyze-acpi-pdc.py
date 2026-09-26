#!/usr/bin/env python3
"""Synthetic, firmware-independent tests for analyze-acpi-pdc.py."""

import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name('analyze-acpi-pdc.py')
spec = importlib.util.spec_from_file_location('analyze_acpi_pdc', SCRIPT)
analyzer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analyzer)


DSDT = '''
Device (GIO0)
{
    Name (GPIC, 0x64)
    Method (_CRS, 0, NotSerialized)
    {
        Name (RBUF, Buffer (0x1D)
        {
            /* 0000 */ 0x89, 0x06, 0x00, 0x09, 0x01, 0xF0, 0x00, 0x00, 0x00,
            /* 0009 */ 0x89, 0x06, 0x00, 0x09, 0x01, 0xF0, 0x00, 0x00, 0x00,
            /* 0012 */ 0x89, 0x06, 0x00, 0x09, 0x01, 0xEF, 0x02, 0x00, 0x00,
            /* 001B */ 0x79, 0x00
        })
        Return (RBUF)
    }
    Name (CIPR, Package (0x02)
    {
        Package (0x03) { One, 0x43, 0x02EF },
        Package (0x03) { 0x02, Zero, 0x00F0 }
    })
}
'''


class AnalyzeAcpiPdcTests(unittest.TestCase):
    def test_duplicate_crs_irqs_keep_their_indexes(self):
        count, mapping = analyzer.pdc_map(DSDT)
        self.assertEqual(count, 100)
        self.assertEqual(mapping, [(240, 0), (240, 0), (751, 67)])
        self.assertEqual(analyzer.resolve_pin(128, count, mapping), (67, 2, 751))
        self.assertEqual(analyzer.resolve_pin(51, count, mapping), (51, None, None))

    def test_unmapped_pseudo_pin_fails_closed(self):
        count, mapping = analyzer.pdc_map(DSDT)
        with self.assertRaisesRegex(ValueError, 'no PDC IRQ index'):
            analyzer.resolve_pin(192, count, mapping)
        with self.assertRaisesRegex(ValueError, 'no CIPR mapping'):
            analyzer.resolve_pin(100, count, [(240, None), (240, None)])

    def test_invalid_mapping_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'invalid physical GPIO'):
            analyzer.pdc_map(DSDT.replace('0x43, 0x02EF', '0x64, 0x02EF'))
        with self.assertRaisesRegex(ValueError, 'duplicate CIPR IRQ'):
            analyzer.pdc_map(DSDT.replace('0x00F0', '0x02EF'))

    def test_truncated_resource_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'truncated large ACPI resource'):
            analyzer.extended_irqs(bytes([0x89, 0x06, 0x00, 0x09]))
        with self.assertRaisesRegex(ValueError, 'no EndTag'):
            analyzer.extended_irqs(bytes([0x89, 0x06, 0x00, 0x09, 1, 240, 0, 0, 0]))

    def test_multi_irq_resource_is_rejected(self):
        data = bytes([0x89, 0x0A, 0x00, 0x09, 2, 240, 0, 0, 0,
                      241, 0, 0, 0, 0x79, 0])
        with self.assertRaisesRegex(ValueError, 'one IRQ per'):
            analyzer.extended_irqs(data)

    def test_incomplete_disassembly_is_rejected(self):
        broken = DSDT.replace('/* 0009 */', '/* 000A */')
        with self.assertRaisesRegex(ValueError, 'non-contiguous'):
            analyzer.pdc_map(broken)
        broken = DSDT.replace('Buffer (0x1D)', 'Buffer (0x1E)')
        with self.assertRaisesRegex(ValueError, 'byte count'):
            analyzer.pdc_map(broken)


if __name__ == '__main__':
    unittest.main()
