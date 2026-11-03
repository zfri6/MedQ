"""Negative native slack must never be accepted as timing closure."""
import unittest,tempfile
from pathlib import Path
import medq_td
class TimingStatus(unittest.TestCase):
 def test_native_negative_and_unknown(self):
  with tempfile.TemporaryDirectory() as d:
   stage=Path(d);reports=stage/'prj/td/reports';output=stage/'prj/td/output'
   reports.mkdir(parents=True);output.mkdir()
   for name in ['rtl.area','gate.area','phy.area','phy.ts','pr.timing','exception.timing']:
    (reports/('MedQ_'+name)).write_text('#lut 100 out of 19600\n')
   for name in ['gate.db','pr.db']:(output/('MedQ_'+name)).write_text('db')
   path=reports/'MedQ_phy.ts';path.write_text('SWNS: -5.565ns, STNS: -248.083ns.\nHWNS: -1.528ns, HTNS: -22.742ns.')
   result=medq_td.judge('implement','MedQ',stage,'MEDQ_FLOW_DONE_IMPLEMENT',0)
   self.assertEqual(result['status'],'TIMING_FAIL');self.assertFalse(result['timing_met'])
   path.write_text('unknown')
   result=medq_td.judge('implement','MedQ',stage,'MEDQ_FLOW_DONE_IMPLEMENT',0)
   self.assertEqual(result['status'],'REVIEW_REQUIRED');self.assertIsNone(result['timing_met'])
   self.assertFalse(result['bitstream_verified'])
if __name__=='__main__':unittest.main()
