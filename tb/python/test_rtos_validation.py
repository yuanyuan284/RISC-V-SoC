import unittest
from validate_rtos_hardware import CHECKS, validate_output

class RtosValidationTests(unittest.TestCase):
    def test_complete_real_application_counters(self):
        result = validate_output(CHECKS + b'FREERTOS PASS tick=61 switches=98 queue=13 msip=1 plic=1 uart=0\r\n')
        self.assertEqual(result['tick'], 61)
        self.assertEqual(result['plic'], 1)

    def test_pass_label_alone_or_failure_is_not_acceptance(self):
        for output in (
            b'FREERTOS PASS',
            b'FREERTOS PASS tick=61 switches=98 queue=13 msip=1 plic=1 uart=0\r\n',
            CHECKS + b'FREERTOS FAIL: bad context\r\n',
        ):
            with self.subTest(output=output), self.assertRaises(RuntimeError):
                validate_output(output)

    def test_missing_interrupt_or_stopped_scheduler_is_rejected(self):
        for counters in (b'0 98 13 1 1 0', b'61 0 13 1 1 0', b'61 98 0 1 1 0',
                         b'61 98 13 0 1 0', b'61 98 13 1 0 0'):
            values = counters.split()
            output = CHECKS + (b'FREERTOS PASS tick=%s switches=%s queue=%s msip=%s plic=%s uart=%s\r\n' % tuple(values))
            with self.subTest(counters=counters), self.assertRaises(RuntimeError):
                validate_output(output)

if __name__ == '__main__':
    unittest.main()
