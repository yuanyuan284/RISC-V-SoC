"""Run host conversion and UART protocol tests without opening a serial port."""
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'script'))
suite = unittest.defaultTestLoader.discover(str(ROOT / 'tb/python'), pattern='test_*.py')
result = unittest.TextTestRunner(verbosity=2).run(suite)
sys.exit(0 if result.wasSuccessful() else 1)
