"""Download the bitstreams built by a CI pipeline.

Fetches the artifacts of the pipeline's llrf_synthesis jobs (one per design)
from GitLab and extracts top/<design>/*.bit into this checkout, where
`make -C top/<design> system_config BITSTREAM=<file>` finds them.

    python -m uspas_llrf.tools.ci_bitfiles PIPELINE [--designs lemp uspas] [--dest DIR]

The GitLab token comes from $GITLAB_TOKEN, or from glab's config
(~/.config/glab-cli/config.yml) for the host. CI artifacts expire
(expire_in in .gitlab-ci.yml); "Keep" on the job keeps them.
"""
import argparse
import io
import json
import os
import re
import sys
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

HOST = 'gitlab.lbl.gov'
PROJECT = 'uspas-llrf/uspas_llrf'
JOB_RE = re.compile(r'^llrf_synthesis: \[(\w[\w-]*)\]$')


def glab_token(host):
    """Token for host from glab's config, or None."""
    cfg = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'glab-cli' / 'config.yml'
    if not cfg.exists():
        return None
    in_host = False
    for line in cfg.read_text().splitlines():
        if re.match(rf'^    {re.escape(host)}:\s*$', line):
            in_host = True
        elif re.match(r'^    \S', line):
            in_host = False
        elif in_host:
            m = re.match(r'^\s+token:\s*(\S+)\s*$', line)
            if m:
                return m.group(1)
    return None


class GitLab:
    def __init__(self, host, project, token):
        self.base = f'https://{host}/api/v4/projects/{urllib.parse.quote(project, safe="")}'
        self.token = token

    def get(self, path):
        req = urllib.request.Request(self.base + path, headers={'PRIVATE-TOKEN': self.token})
        with urllib.request.urlopen(req) as r:
            return r.read()

    def jobs(self, pipeline):
        return json.loads(self.get(f'/pipelines/{pipeline}/jobs?per_page=100'))


def synthesis_jobs(jobs, designs=None):
    """{design: job} for the pipeline's successful llrf_synthesis jobs."""
    found = {}
    for job in jobs:
        m = JOB_RE.match(job['name'])
        if m and job['status'] == 'success' and (not designs or m.group(1) in designs):
            found[m.group(1)] = job
    return found


def extract_bits(data, design, dest):
    """Write top/<design>/*.bit from an artifacts zip under dest; return the paths."""
    paths = []
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for name in z.namelist():
            if re.fullmatch(rf'top/{re.escape(design)}/[^/]+\.bit', name):
                out = Path(dest) / name
                out.parent.mkdir(parents=True, exist_ok=True)
                out.write_bytes(z.read(name))
                paths.append(out)
    return paths


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('pipeline', type=int, help='pipeline ID, e.g. 19610')
    parser.add_argument('--designs', nargs='*', help='designs to fetch (default: all built)')
    parser.add_argument('--dest', default=Path(__file__).resolve().parents[2],
                        help='repository root to extract into (default: this checkout)')
    parser.add_argument('--host', default=HOST)
    parser.add_argument('--project', default=PROJECT)
    args = parser.parse_args()

    token = os.environ.get('GITLAB_TOKEN') or glab_token(args.host)
    if not token:
        sys.exit(f'No GitLab token: set GITLAB_TOKEN or log in with glab for {args.host}')
    gl = GitLab(args.host, args.project, token)

    jobs = synthesis_jobs(gl.jobs(args.pipeline), args.designs)
    missing = set(args.designs or []) - set(jobs)
    if missing:
        print(f"no successful llrf_synthesis job in pipeline {args.pipeline} for: {' '.join(sorted(missing))}")
    if not jobs:
        sys.exit(1)
    for design, job in sorted(jobs.items()):
        try:
            data = gl.get(f"/jobs/{job['id']}/artifacts")
        except urllib.error.HTTPError as e:
            print(f'{design}: job {job["id"]} artifacts not available ({e.code}; expired?)')
            continue
        for path in extract_bits(data, design, args.dest):
            print(f'{design}: {path}  (make -C top/{design} system_config BITSTREAM={path.name})')


if __name__ == '__main__':
    main()
