"""Unit tests for failure classification; these are NOT TD synthesis evidence."""
import tempfile
import unittest
import subprocess
import sys
import xml.etree.ElementTree as ET
import json
import io
from contextlib import redirect_stdout
from unittest.mock import patch
from pathlib import Path
import medq_td


class FlowEvidence(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='medq_td_judge_')
        self.stage = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)

    def judge(self, mode='synth', text='MEDQ_FLOW_DONE_SYNTH', rc=0):
        return medq_td.judge(mode, 'MedQ', self.stage, text, rc)

    def artifacts(self):
        for name in ('reports/MedQ_rtl.area', 'reports/MedQ_gate.area', 'output/MedQ_gate.db'):
            p=self.stage/'prj/td'/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text('#lut 100 out of 19600\n#reg 50 out of 19600\n')

    def test_zero_exit_does_not_hide_expired_license(self):
        self.artifacts()
        r=self.judge(text='RUN-8008 ERROR: License expired!\nMEDQ_FLOW_DONE_SYNTH')
        self.assertEqual(r['status'],'FAIL');self.assertTrue(r['license_expired'])

    def test_completion_marker_required(self):
        self.artifacts();self.assertEqual(self.judge(text='')['status'],'FAIL')

    def test_embedded_marker_is_not_completion(self):
        self.artifacts();self.assertEqual(self.judge(text='start command puts MEDQ_FLOW_DONE_SYNTH')['status'],'FAIL')

    def test_missing_reports_fail(self):
        self.assertEqual(self.judge()['status'],'FAIL')

    def test_empty_report_fails(self):
        self.artifacts();(self.stage/'prj/td/reports/MedQ_gate.area').write_text('')
        self.assertEqual(self.judge()['status'],'FAIL')

    def test_complete_gate_synthesis(self):
        self.artifacts();self.assertEqual(self.judge()['status'],'PASS')

    def test_resource_overflow_is_not_accepted(self):
        self.artifacts();(self.stage/'prj/td/reports/MedQ_gate.area').write_text('#lut 37341 out of 19600\n')
        self.assertEqual(self.judge()['status'],'RESOURCE_OVERFLOW')

    def test_unknown_area_format_requires_review(self):
        self.artifacts();(self.stage/'prj/td/reports/MedQ_gate.area').write_text('unknown format')
        self.assertEqual(self.judge()['status'],'REVIEW_REQUIRED')

    def test_crash_and_nonzero_fail(self):
        self.artifacts()
        self.assertEqual(self.judge(text='Oops! coredump')['status'],'FAIL')
        self.assertEqual(self.judge(rc=1)['status'],'FAIL')

    def test_synth_stops_before_implementation(self):
        text=medq_td.build_tcl('MedQ','top','synth',False,['rtl/top.v'])
        self.assertNotIn('\nplace\n',text);self.assertNotIn('\nroute\n',text);self.assertNotIn('\nbitgen ',text)
        self.assertIn('analyze -file {rtl/top.v}',text);self.assertNotIn('SIMULATION',text)

    def test_unknown_timing_never_passes(self):
        self.artifacts()
        for file in ('reports/MedQ_phy.area','reports/MedQ_phy.ts','reports/MedQ_pr.timing',
                     'reports/MedQ_exception.timing','reports/MedQ_clock_utilization.txt','output/MedQ_pr.db','output/MedQ.bit'):
            p=self.stage/'prj/td'/file;p.write_text('unknown report format')
        result=self.judge('bitgen','MEDQ_FLOW_DONE_BITGEN')
        self.assertEqual(result['status'],'REVIEW_REQUIRED')
        self.assertIsNone(result['timing_met']);self.assertFalse(result['bitstream_verified'])

    def test_project_xml_carries_constraints(self):
        xml=medq_td.build_project('MedQ','top',['rtl/top.v'],self.stage/'prj/td',True)
        root=ET.fromstring(xml)
        self.assertEqual(root.findtext('HardWare/Device'),'EG4S20BG256')
        self.assertIsNotNone(root.find('Source_Files/ADC_FILE/File'))
        self.assertIsNotNone(root.find('Source_Files/SDC_FILE/File'))

    def test_current_readiness_blocks_bitgen(self):
        # The actual project's readiness changes after successful signoff.
        # Keep this negative control isolated from real release state.
        ready=self.stage/'prj/td/hardware_readiness.json'
        ready.parent.mkdir(parents=True,exist_ok=True)
        ready.write_text(json.dumps({'required':{'clock_and_cdc_constraints_reviewed':False}}))
        output=io.StringIO()
        with patch.object(medq_td,'ROOT',self.stage),patch.object(sys,'argv',['medq_td','--mode','bitgen']),redirect_stdout(output):
            code=medq_td.main()
        self.assertEqual(code,2);self.assertIn('BLOCKED',output.getvalue())


if __name__=='__main__':unittest.main()
