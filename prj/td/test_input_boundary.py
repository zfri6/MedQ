"""Controls for TD register renaming: never extend an IO exclusion inward."""
import unittest
from timing_evidence import input_boundary_audit


END = 'u_osd_renderer/u_dual_scene/background_b14[0]_syn_1412.d[0]'
SD = '''Begin Point : SD_MISO(triggered by clock )
End Point : END(triggered by clock u_sys_pll/pll_inst.clkc[0])
Check Type : hold
Delay Type          Location             Incr           Path   Level  Netlist Info
--------------------------------------------------------------------  ---------------
net (fo=1)                                                            net: SD_MISO,  rtl/top.v(40)
                                                                      pin: SD_MISO_syn_2.ipad
PAD                 x022y000                                          pin: SD_MISO_syn_2.di
net (fo=1)                                                            net: SD_MISO_dup_1,  rtl/top.v(40)
                                                                      pin: END
LUT2 (reg)          x023y005z1                                        net: u_asset_loader/u_sd_card_ctrl/u_spi/rx_shift[0],  rtl/sd_spi_master.v(20)
'''.replace('END', END)


class InputBoundary(unittest.TestCase):
    def test_renamed_sd_first_capture_accepted(self):
        result = input_boundary_audit(SD, 'SD_MISO', END)
        self.assertEqual(result['capture_net'], 'u_asset_loader/u_sd_card_ctrl/u_spi/rx_shift[0]')
        self.assertTrue(result['direct_first_capture_verified'])

    def test_all_registered_input_pads(self):
        for port in [f'{p}[{i}]' for p in ('KEY', 'SW') for i in range(4)] + ['UART_RX']:
            with self.subTest(port=port):
                if port == 'UART_RX':
                    capture, origin = 'u_uart_rx/sync1', 'uart_rx'
                else:
                    capture = 'u_board_inputs/' + ('keys_meta' if port.startswith('KEY') else 'switches_meta') + port[port.index('['):]
                    origin = 'medq_board_inputs'
                end = port + '_syn_4.ipad'
                block = f'''Delay Type          Location             Incr           Path   Level  Netlist Info
--------------------------------------------------------------------  ---------------
net (fo=1)                                                            net: {port},  rtl/top.v(25)
                                                                      pin: {end}
PAD (reg)           x025y000                                          net: {capture},  rtl/{origin}.v(5)
'''
                self.assertTrue(input_boundary_audit(block, port, end)['direct_first_capture_verified'])
                with self.assertRaises(AssertionError):
                    input_boundary_audit(block.replace(capture, capture + '_later'), port, end)

    def test_later_register_rejected(self):
        with self.assertRaises(AssertionError):
            input_boundary_audit(SD.replace('/rx_shift[0]', '/rx_shift[1]'), 'SD_MISO', END)

    def test_combinational_detour_rejected(self):
        extra = 'LUT2                x022y001                                          pin: intermediate.f[0]\n'
        with self.assertRaises(AssertionError):
            input_boundary_audit(SD.replace('LUT2 (reg)', extra + 'LUT2 (reg)'), 'SD_MISO', END)

    def test_additional_register_rejected(self):
        extra = 'LUT2 (reg)          x022y001                                          net: intermediate, rtl/sd_spi_master.v(20)\n'
        with self.assertRaises(AssertionError):
            input_boundary_audit(SD.replace('LUT2 (reg)', extra + 'LUT2 (reg)'), 'SD_MISO', END)

    def test_wrong_endpoint_or_pad_rejected(self):
        for block, end in [(SD, END + '_later'), (SD.replace('SD_MISO_syn_2.di', 'OTHER_syn_2.di'), END)]:
            with self.assertRaises(AssertionError):
                input_boundary_audit(block, 'SD_MISO', end)

    def test_wrong_source_or_origin_rejected(self):
        for block in [SD.replace('net: SD_MISO,', 'net: UART_RX,'),
                      SD.replace('SD_MISO_dup_1', 'internal_stage'),
                      SD.replace('rtl/sd_spi_master.v', 'rtl/medq_dual_ui_scene.v')]:
            with self.assertRaises(AssertionError):
                input_boundary_audit(block, 'SD_MISO', END)

    def test_missing_table_or_unknown_element_rejected(self):
        for block in ['', SD.replace('PAD                 ', 'UNKNOWN             ')]:
            with self.assertRaises(AssertionError):
                input_boundary_audit(block, 'SD_MISO', END)


if __name__ == '__main__':
    unittest.main()
