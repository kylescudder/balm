"""The host engine is installed centrally; this app only has a CLI shim."""
from pathlib import Path
import unittest
class Installation(unittest.TestCase):
    def test_shared_service_entry_point(self):
        here=Path(__file__).parent
        self.assertIn('worker balm-site', (here/'host-deploy.sh').read_text())
        self.assertFalse((here/'deploy_core.py').exists())
