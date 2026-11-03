"""Strict readers for native TD evidence; no synthesis or board-test claims."""
import re


def input_boundary_audit(block, begin, end):
    """Prove an ignored input hold ends at its first physical capture.

    TD can merge/rename LUT/register instance names. Identify the capture by
    its native terminal net and RTL origin, and require the complete direct
    PAD path, rather than trusting a hierarchical endpoint spelling.
    """
    match = re.search(r'^Delay Type[^\n]*\n[- ]+\n', block, re.M)
    assert match, 'Missing native input path table'
    table = re.split(r'\n\s*\n', block[match.end():], maxsplit=1)[0]
    types, nets, pins = [], [], []
    terminal = ''
    for line in table.splitlines():
        if not line.strip():
            continue
        kind = re.match(r'^(net \(fo=\d+\)|PAD \(reg\)|PAD|LUT\d+ \(reg\))\s+', line)
        if kind:
            types.append(re.sub(r'net \(fo=\d+\)', 'net', kind[1]))
            terminal = line
        else:
            assert line.lstrip().startswith('pin:'), 'Unknown element in input boundary path'
        item = re.search(r'\b(net|pin):\s*(.*)', line)
        assert item, 'Missing native input net/pin identity'
        identity = item[2].split(',')[0].strip()
        (nets if item[1] == 'net' else pins).append(identity)
    if begin == 'SD_MISO':
        capture = 'u_asset_loader/u_sd_card_ctrl/u_spi/rx_shift[0]'
        assert types == ['net', 'PAD', 'net', 'LUT2 (reg)'], 'SD input passes logic or another register'
        assert len(nets) == 3 and nets[0] == begin and nets[-1] == capture
        assert re.fullmatch(r'SD_MISO(?:_dup_\d+)?', nets[1]), 'SD input is not a direct PAD net'
        assert len(pins) == 3 and re.fullmatch(r'SD_MISO_syn_\d+\.ipad', pins[0])
        assert pins[1] == pins[0][:-4] + 'di' and pins[2] == end and end.endswith('.d[0]')
        assert re.search(r'rtl/sd_spi_master\.v\(\d+\)\s*$', terminal), 'Wrong SD capture RTL origin'
    else:
        key = re.fullmatch(r'(KEY|SW)\[([0-3])\]', begin)
        assert key or begin == 'UART_RX', 'Unreviewed input port'
        capture = ('u_board_inputs/' + ('keys_meta' if key[1] == 'KEY' else 'switches_meta') + '[' + key[2] + ']') if key else 'u_uart_rx/sync1'
        assert types == ['net', 'PAD (reg)'] and nets == [begin, capture], 'Input passes first PAD capture'
        assert pins == [end] and re.fullmatch(re.escape(begin) + r'_syn_\d+\.ipad', end)
        origin = 'medq_board_inputs' if key else 'uart_rx'
        assert re.search(r'rtl/' + origin + r'\.v\(\d+\)\s*$', terminal), 'Wrong PAD capture RTL origin'
    return {'capture_net': capture, 'native_elements': types,
            'direct_first_capture_verified': True}


def timing_report(text):
    def number(label):
        match = re.search(r'\b' + re.escape(label) + r':\s*(-?\d+(?:\.\d+)?)ns', text)
        return float(match[1]) if match else None
    values = {key: number(key) for key in ('SWNS', 'STNS', 'HWNS', 'HTNS')}
    period = re.search(r'Period Check WNS:\s*(-?[\d.]+)ns', text)
    coverage = re.search(r'STA coverage\s*:\s*([\d.]+)%', text)
    groups = []
    for block in text.split('Path Group')[1:]:
        header = block.split('Max Paths')[0]
        name = re.search(r'^\s*:\s*([^\r\n]*)', header)
        group = {'name': name[1].strip() if name else ''}
        for key, label in (('setup', 'Max'), ('hold', 'Min')):
            row = re.search(r'^' + label + r'\s*:\s*[SH]WNS\s+(-?[\d.]+)ns,\s*[SH]TNS\s+(-?[\d.]+)ns,\s*(\d+) Viol Endpoints,\s*(\d+) Total Endpoints,\s*(\d+) Paths Analyzed', header, re.M)
            if row:
                group[key] = dict(wns_ns=float(row[1]), tns_ns=float(row[2]), violated_endpoints=int(row[3]), total_endpoints=int(row[4]), analyzed_paths=int(row[5]))
        groups.append(group)
    negative = []
    for block in re.split(r'(?=^Slack\s*:)', text, flags=re.M)[1:]:
        match = re.match(r'Slack\s*:\s*(-?[\d.]+)ns', block)
        if not match or float(match[1]) >= 0:
            continue
        row = {'slack_ns': float(match[1])}
        for key, label in (('begin', 'Begin Point'), ('end', 'End Point'), ('check', 'Check Type')):
            field = re.search(r'^' + label + r'\s*:\s*(.*)', block, re.M)
            row[key] = field[1].strip() if field else None
        negative.append(row)
    known = all(value is not None for value in values.values()) and period is not None and bool(groups)
    known = known and all('setup' in group and 'hold' in group for group in groups)
    routed = bool(re.search(r'Confidence\s*:\s*Routed', text))
    both = bool(re.search(r'Check Corner\s*:\s*Both \(Slow and Fast\)', text))
    met = known and routed and both and all(value >= 0 for value in values.values()) and float(period[1]) >= 0
    met = met and all(item['wns_ns'] >= 0 and item['tns_ns'] == 0 and item['violated_endpoints'] == 0 for group in groups for key, item in group.items() if key in ('setup', 'hold'))
    return dict(values=values, period_check_wns_ns=float(period[1]) if period else None,
                coverage_percent=float(coverage[1]) if coverage else None,
                routed=routed, both_corners=both, format_known=known, met=met,
                groups=groups, negative_paths=negative)


def resources(text):
    return {row[1]: {'used': int(row[2]), 'available': int(row[3])}
            for row in re.finditer(r'^#(\w+)\s+(\d+)\s+out of\s+(\d+)', text, re.M)}


def route_qor_audit(qor, native_log, final_timing):
    """TD writes route.qor before fix_hold; never confuse it with final STA.

    Nonzero pre-fix hold counts require an ordered, completed native hold
    repair, final timing refresh/report and routed-DB export. Final routed
    slow+fast setup/hold must independently pass every group and endpoint.
    The original QoR is retained, never rewritten to synthetic zero counts.
    """
    assert final_timing['format_known'] and final_timing['routed'] and final_timing['both_corners']
    assert final_timing['met'] and not final_timing['negative_paths'], 'Final native timing is not clean'
    counts = {}
    for kind in ('S', 'H'):
        match = re.search(r'Num of violated ' + kind + r'-EP\s*\|\s*(\d+)', qor)
        assert match, 'Missing native route QoR endpoint counts'
        counts[kind] = int(match[1])
    assert counts['S'] == 0, 'Route QoR setup violations require a new implementation review'
    repaired = counts['H'] != 0
    if repaired:
        events = [
            r'^RUN-1002\s*:\s*start command "route"',
            r'^RUN-1003\s*:\s*finish command "fix_hold"',
            r'^RUN-1002\s*:\s*start command "update_timing -mode final"',
            r'^RUN-1002\s*:\s*start command "report_timing_summary .*_pr\.timing"',
            r'^RUN-1002\s*:\s*start command "export_db .*_pr\.db"',
        ]
        previous = -1
        for pattern in events:
            # route itself emits an earlier final-timing refresh. Search each
            # required command after the previous stage, not its first use.
            match = re.compile(pattern, re.M).search(native_log, previous + 1)
            assert match and match.start() > previous, 'Missing/out-of-order native post-route hold-repair evidence'
            previous = match.start()
    return {'stage': 'route_before_fix_hold', 'pre_fix_violated_endpoints': counts,
            'post_route_hold_repair_order_verified': repaired,
            'final_dual_corner_all_group_endpoints_zero': True,
            'final_native_timing_ns': final_timing['values']}
