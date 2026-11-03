"""Negative controls for the signoff reader, not STA execution evidence."""
import unittest
from timing_evidence import timing_report


REPORT='''Confidence : Routed
Check Corner : Both (Slow and Fast)
STA coverage : 99.81%
SWNS: 1.000ns, STNS: 0.000ns
HWNS: 0.030ns, HTNS: 0.000ns
Period Check WNS: 0.000ns
Path Group : clk -> clk
Max : SWNS 1.000ns, STNS 0.000ns, 0 Viol Endpoints, 10 Total Endpoints, 20 Paths Analyzed
Min : HWNS 0.030ns, HTNS 0.000ns, 0 Viol Endpoints, 10 Total Endpoints, 20 Paths Analyzed
Max Paths
Slack : 1.000ns
Begin Point : reg_a.clk
End Point : reg_b.d
Check Type : setup
'''


class NativeTimingReader(unittest.TestCase):
    def test_full_native_shape(self):
        self.assertTrue(timing_report(REPORT)['met'])

    def test_unknown_and_nonrouted_fail(self):
        self.assertFalse(timing_report('')['met'])
        self.assertFalse(timing_report(REPORT.replace('Routed','Placed'))['met'])

    def test_both_corners_required(self):
        self.assertFalse(timing_report(REPORT.replace('Both (Slow and Fast)','Slow'))['met'])

    def test_positive_global_does_not_hide_negative_group(self):
        bad=REPORT.replace('Min : HWNS 0.030ns','Min : HWNS -0.001ns')
        self.assertFalse(timing_report(bad)['met'])

    def test_missing_hold_statistics_fails(self):
        bad='\n'.join(line for line in REPORT.splitlines() if not line.startswith('Min :'))
        self.assertFalse(timing_report(bad)['met'])

    def test_period_violation_fails(self):
        self.assertFalse(timing_report(REPORT.replace('Period Check WNS: 0.000','Period Check WNS: -0.001'))['met'])

    def test_endpoint_count_must_be_zero(self):
        self.assertFalse(timing_report(REPORT.replace('0 Viol Endpoints','1 Viol Endpoints'))['met'])


if __name__=='__main__':unittest.main()
