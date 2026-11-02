"""Build the AP04 Gowin project from the repository root."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gowin', help='Path to gw_sh.exe (or set GOWIN_GW_SH)')
    args = parser.parse_args()
    requested = args.gowin or os.environ.get('GOWIN_GW_SH') or 'gw_sh'
    tool = shutil.which(requested)
    if tool:
        tool = str(Path(tool).resolve())
    if not tool and Path(requested).is_file():
        tool = str(Path(requested).resolve())
    if not tool:
        parser.error('Gowin gw_sh not found. Supply --gowin or GOWIN_GW_SH.')
    project = ET.parse(ROOT / 'air_piano.gprj')
    sources = [node.attrib['path'] for node in project.findall('./FileList/File')
               if node.attrib.get('enable') == '1']
    missing = [p for p in sources if not (ROOT / p).is_file()]
    if missing:
        parser.error('Missing project files: ' + ', '.join(missing))
    out = ROOT / 'build'
    out.mkdir(exist_ok=True)
    files = sources + ['air_piano.gprj', 'run_gowin.tcl']
    hashes = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in files}
    (out / 'BUILD_INPUT_SHA256.json').write_text(json.dumps(hashes, indent=2) + '\n', encoding='utf-8')
    status = {'baseline': 'AP04', 'started_at': time.strftime('%Y-%m-%dT%H:%M:%S%z'),
              'state': 'running', 'log': 'build/gowin.log'}
    status_path = out / 'BUILD_STATUS.json'
    status_path.write_text(json.dumps(status, indent=2) + '\n', encoding='utf-8')
    print('Running Gowin; log: build/gowin.log', flush=True)
    try:
        with (out / 'gowin.log').open('wb') as log:
            proc = subprocess.run([tool, 'run_gowin.tcl'], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        status.update(state='process_exited', exit_code=proc.returncode,
                      sources_unchanged=all(hashlib.sha256((ROOT / p).read_bytes()).hexdigest() == h for p, h in hashes.items()))
    except (OSError, KeyboardInterrupt) as exc:
        status.update(state='interrupted_or_failed', error=type(exc).__name__, exit_code=1)
    status['finished_at'] = time.strftime('%Y-%m-%dT%H:%M:%S%z')
    status_path.write_text(json.dumps(status, indent=2) + '\n', encoding='utf-8')
    print('Process state recorded. Inspect log, final timing, warnings and bitstream before programming.', flush=True)
    return status['exit_code'] if status.get('sources_unchanged', True) else 1


if __name__ == '__main__':
    sys.exit(main())
