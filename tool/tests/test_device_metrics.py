import unittest

from tool.device_metrics import parse_battery, parse_cpu, parse_memory, summarize


class DeviceMetricsTest(unittest.TestCase):
    def test_memory_formats_and_missing_data(self):
        self.assertEqual(parse_memory(" TOTAL PSS: 1234 TOTAL RSS: 4567"), 1234)
        self.assertEqual(parse_memory(" TOTAL  456  123  78"), 456)
        self.assertIsNone(parse_memory("No process found"))

    def test_cpu_only_exact_app_and_child(self):
        raw = (
            "  4.5% 123/com.blackoutkit.vpn: 2% user\n"
            "  2% 456/com.blackoutkit.vpn:worker: 1% user\n"
            "  9% 789/com.blackoutkit.vpn.other: 9% user\n"
        )
        self.assertEqual(parse_cpu(raw), 6.5)
        self.assertIsNone(parse_cpu("  3% 1/system: 3% user"))

    def test_battery_and_summary(self):
        self.assertEqual(parse_battery("  level: 80\n  temperature: 310\n")["level"], 80)
        self.assertIsNone(parse_battery("")["temperature"])
        self.assertEqual(summarize([{"cpu": 2}, {"cpu": None}, {"cpu": 4}], "cpu")["median"], 3)
        self.assertIsNone(summarize([{"cpu": None}], "cpu"))
