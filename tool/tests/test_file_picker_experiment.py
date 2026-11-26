import unittest

from tool.prepare_file_picker_experiment import candidate_manifest


class FilePickerExperimentTests(unittest.TestCase):
    def test_only_expected_constraints_changed(self):
        old = "file_picker: ^8.0.0\npackage_info_plus: 5.0.1\nflutter_secure_storage: ^9.0.0\n"
        self.assertEqual(
            candidate_manifest(old),
            "file_picker: 8.1.7\npackage_info_plus: 8.3.1\nflutter_secure_storage: ^9.0.0\n",
        )

    def test_promoted_candidate_is_idempotent(self):
        promoted = "file_picker: 8.1.7\npackage_info_plus: 8.3.1\n"
        self.assertEqual(candidate_manifest(promoted), promoted)

    def test_unreviewed_manifest_rejected(self):
        for old in ("file_picker: 9.0.0\npackage_info_plus: 5.0.1",
                    "file_picker: ^8.0.0\npackage_info_plus: 8.0.0"):
            with self.subTest(old=old), self.assertRaises(ValueError):
                candidate_manifest(old)
