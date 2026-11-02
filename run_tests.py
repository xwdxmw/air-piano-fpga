"""Run AP04's original regression selection without changing release evidence."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent
DEFAULT_TESTS = [
    'pressure_zero_check', 'ttp_check', 'transpose_check', 'boot_check', 'debounce_check',
    'queue_scoreboard', 'delay_clean', 'source_isolation', 'engine_idle_release',
    'pt8211_words', 'guide_disable', 'guide_sync', 'runtime_entry', 'led_startup',
    'strip30_top', 'guide_ws_chain', 'harp_bend', 'ws2812_protocol', 'scope_snapshot',
    'lcd_protocol', 'scope_trigger', 'voice_edges', 'top_event_check', 'adc_check',
    'harp_pending_check', 'pressure_path_check', 'no_lock_check', 'controls_check',
    'i2s_standard_check', 'spectrum_check', 'pitch_ratio_check', 'mixer_smooth_check',
    'lcd_spectrum_check', 'top_controls_check', 'latency_digital_check',
    'force_equiv_check', 'bell_edges_check', 'bell_alias_check', 'bell_render',
    'bell_poly32_check', 'zero_velocity_check', 'rom_truth_check', 'harp_equiv_check',
    'flute_bank_check', 'flute_edges_check', 'flute_source_check', 'flute_poly32_check',
    'flute_render', 'flute_rom_equiv_check', 'voice_status_check', 'lcd_poly32_check',
    'poly32_visual_chain_check', 'adc_timing_ab_check', 'live_led_follow_check',
    'normal_led_wire', 'poly32_slow_check', 'synth_shared_equiv', 'lcd_pixel_equiv',
    'queue_equiv', 'ws_equiv',
]
LONG_TESTS = {'normal_led_wire', 'guide_ws_chain', 'guide_sync',
              'poly32_visual_chain_check', 'synth_shared_equiv'}


def resolve_tool(value, env_name, default):
    candidate = value or os.environ.get(env_name) or default
    resolved = shutil.which(candidate)
    if resolved:
        return Path(resolved).resolve().as_posix()
    path = Path(candidate).expanduser()
    if path.is_file():
        return path.resolve().as_posix()
    raise ValueError(f'Tool not found: {candidate}. Set --{default} or {env_name}.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tests', nargs='*', help='Selected regression top names; default: all 60')
    parser.add_argument('--iverilog')
    parser.add_argument('--vvp')
    parser.add_argument('--jobs', type=int, default=2)
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--skip-reset', action='store_true')
    group.add_argument('--reset-only', action='store_true')
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error('--jobs must be positive')
    if args.reset_only and args.tests:
        parser.error('--reset-only cannot be combined with test names')
    names = [] if args.reset_only else (args.tests or DEFAULT_TESTS)
    for name in names:
        if name not in DEFAULT_TESTS:
            parser.error(f'Unknown regression: {name}')
    try:
        iv = resolve_tool(args.iverilog, 'IVERILOG', 'iverilog')
        vvp = resolve_tool(args.vvp, 'VVP', 'vvp')
    except ValueError as exc:
        parser.error(str(exc))
    results = ROOT / 'build/test_results'
    results.mkdir(parents=True, exist_ok=True)
    (ROOT / 'tests/results').mkdir(parents=True, exist_ok=True)
    rtl = sorted(p for p in (ROOT / 'src').glob('*.v')
                 if not p.name.startswith('tb_') and p.name != 'pll_12m288.v')
    refs = sorted((ROOT / 'tests/reference').glob('*.v'))
    all_inputs = sorted(set(rtl + list((ROOT / 'tests').rglob('*.v'))))
    hashes = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in all_inputs}

    def run(name, reset=False):
        start = time.monotonic()
        row = {'name': name}
        output = results / (name + '.vvp')
        files = [ROOT / 'tests' / (name + '.v'), ROOT / 'tests/pll_sim.v'] + rtl
        if not reset:
            files += refs
        cmd = [iv, '-g2012'] + ([] if reset else ['-DNEW_LED_FOLLOW'])
        cmd += ['-s', name, '-o', output.relative_to(ROOT).as_posix()]
        cmd += [p.relative_to(ROOT).as_posix() for p in files]
        (results / (name + '_command.json')).write_text(json.dumps(cmd, indent=2), encoding='utf-8')
        try:
            compiled = subprocess.run(cmd, cwd=ROOT, capture_output=True, timeout=90)
            (results / (name + '_compile.log')).write_bytes(compiled.stdout + compiled.stderr)
            row['compile_exit'] = compiled.returncode
            if compiled.returncode == 0:
                timeout = 60 if reset else (900 if name in LONG_TESTS else 300)
                simulated = subprocess.run([vvp, str(output)], cwd=ROOT,
                                           capture_output=True, timeout=timeout)
                (results / (name + '.log')).write_bytes(simulated.stdout + simulated.stderr)
                row['run_exit'] = simulated.returncode
        except subprocess.TimeoutExpired as exc:
            row['timeout'] = True
            (results / (name + '_timeout.log')).write_bytes((exc.stdout or b'') + (exc.stderr or b''))
        except OSError as exc:
            row['error'] = str(exc)
        row['passed'] = row.get('compile_exit') == 0 and row.get('run_exit') == 0 and not row.get('timeout')
        row['elapsed_seconds'] = round(time.monotonic() - start, 2)
        if reset:
            row['scenarios'] = 20
        print(('PASS' if row['passed'] else 'FAIL') + f' {name} ({row["elapsed_seconds"]}s)', flush=True)
        if not row['passed']:
            print(json.dumps(row), flush=True)
        return row

    started = time.strftime('%Y-%m-%dT%H:%M:%S%z')
    if args.jobs == 1:
        rows = [run(name) for name in names]
    else:
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            rows = list(pool.map(run, names))
    reset = None if args.skip_reset else run('reset_release_check', reset=True)
    unchanged = all(hashlib.sha256((ROOT / p).read_bytes()).hexdigest() == h for p, h in hashes.items())
    summary = {
        'baseline': 'AP04', 'started_at': started,
        'passed': unchanged and all(x['passed'] for x in rows) and (reset is None or reset['passed']),
        'sources_unchanged': unchanged, 'regression_count': len(rows),
        'tests': rows, 'reset': reset, 'source_sha256': hashes,
        'limitations': 'RTL simulation with behavioral PLL; not physical PLL, analog latency, cold boot, or peripheral validation.',
    }
    (ROOT / 'build/TEST_SUMMARY.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    print(f'{len(rows)} regressions; reset scenarios: {20 if reset else 0}; passed={summary["passed"]}', flush=True)
    return 0 if summary['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
