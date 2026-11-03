"""Negative controls for pre-fix route QoR versus final native STA."""
import unittest
from timing_evidence import timing_report, route_qor_audit
from test_timing_evidence import REPORT

QOR='Num of violated S-EP | 0\nNum of violated H-EP | 5\n'
LOG='''RUN-1002 : start command "route"
RUN-1003 : finish command "fix_hold" in 7s
RUN-1002 : start command "update_timing -mode final"
RUN-1002 : start command "report_timing_summary -ep_num 500 -file prj/td/reports/name_pr.timing"
RUN-1002 : start command "export_db prj/td/output/name_pr.db"
'''


class RouteQorStage(unittest.TestCase):
    def test_completed_repair_and_clean_final_sta(self):
        result=route_qor_audit(QOR,LOG,timing_report(REPORT))
        self.assertEqual(result['pre_fix_violated_endpoints']['H'],5)
        self.assertTrue(result['post_route_hold_repair_order_verified'])

    def test_missing_or_reversed_repair_fails(self):
        for bad in [LOG.replace('finish command "fix_hold"','unfinished hold repair'),
                    '\n'.join(reversed(LOG.splitlines()))]:
            with self.assertRaises(AssertionError):route_qor_audit(QOR,bad,timing_report(REPORT))

    def test_route_internal_refresh_does_not_replace_post_repair_refresh(self):
        earlier='RUN-1002 : start command "update_timing -mode final"\n'
        self.assertTrue(route_qor_audit(QOR,earlier+LOG,timing_report(REPORT))['post_route_hold_repair_order_verified'])

    def test_negative_final_hold_never_accepted(self):
        bad=REPORT.replace('Min : HWNS 0.030ns','Min : HWNS -0.001ns')
        with self.assertRaises(AssertionError):route_qor_audit(QOR,LOG,timing_report(bad))

    def test_positive_global_does_not_hide_final_endpoint(self):
        bad=REPORT.replace('0 Viol Endpoints','1 Viol Endpoints')
        with self.assertRaises(AssertionError):route_qor_audit(QOR,LOG,timing_report(bad))

    def test_unknown_qor_and_prefinal_setup_fail(self):
        for bad in ['',QOR.replace('S-EP | 0','S-EP | 1')]:
            with self.assertRaises(AssertionError):route_qor_audit(bad,LOG,timing_report(REPORT))

    def test_no_repair_needed_when_route_already_clean(self):
        result=route_qor_audit(QOR.replace('H-EP | 5','H-EP | 0'),'',timing_report(REPORT))
        self.assertFalse(result['post_route_hold_repair_order_verified'])


if __name__=='__main__':unittest.main()
