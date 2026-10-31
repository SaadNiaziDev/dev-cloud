#!/usr/bin/env python3
"""Reject backend identifiers and credentials in tracked client files or one ref's history."""
import argparse
import itertools
import pathlib
import re
import subprocess
import sys

SELF = 'scripts/check-cloud-leaks.py'
RULES = [
    ('provider endpoint', re.compile(rb'(?:r2\.cloudflarestorage\.com|[a-z0-9.-]*\.(?:workers\.dev|supabase\.co|neon\.tech|vercel\.app))', re.I)),
    ('database connection', re.compile(rb'postgres(?:ql)?://', re.I)),
    ('private key', re.compile(rb'-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----')),
    ('credential', re.compile(rb'\b(?:sb_(?:secret|publishable)_|sk_(?:live|test)_|sk-ant-)[A-Za-z0-9_-]{16,}')),
    ('provider identifier', re.compile(rb'(?<![A-Za-z0-9])[a-f0-9]{32}(?![A-Za-z0-9])', re.I)),
]


def findings(data):
    return [(data.count(b'\n', 0, match.start()) + 1, label) for label, pattern in RULES for match in pattern.finditer(data)]


def git(*args):
    return subprocess.check_output(['git', *args])


def files(history):
    if history:
        # Inspect each historical path: a safe blob name today cannot exempt a different historical file.
        seen = set()
        for commit in git('rev-list', history).decode().splitlines():
            for row in git('ls-tree', '-rz', '--full-tree', commit).split(b'\0'):
                if not row:
                    continue
                meta, name = row.split(b'\t', 1)
                mode, kind, oid = meta.split()
                if kind != b'blob' or name.decode() == SELF or (oid, name) in seen:
                    continue
                seen.add((oid, name))
                yield f'{commit[:8]}:{name.decode()}', git('cat-file', 'blob', oid.decode())
    else:
        for name in git('ls-files', '-z').split(b'\0'):
            if not name or name.decode() == SELF:
                continue
            path = pathlib.Path(name.decode())
            if path.is_file() and not path.is_symlink():
                yield str(path), path.read_bytes()


def self_test():
    bad = [b'postgres://host/db', b'https://private.workers.dev', b'https://private.supabase.co',
           b'https://private.neon.tech', b'https://private.vercel.app', b'r2.cloudflarestorage.com',
           b'-----BEGIN PRIVATE KEY-----', b'sk_live_' + b'x' * 24, b'"' + b'a' * 32 + b'"']
    safe = [b'https://api.example.invalid', b'http://127.0.0.1:8787', b'vercel-cli', b'a' * 64]
    assert all(findings(value) for value in bad)
    assert not any(findings(value) for value in safe)
    print('Leak guard checks passed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--history', metavar='REF', help='audit only this ref and its ancestors')
    parser.add_argument('--artifact', action='append', default=[], help='also inspect a built binary')
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    failed = False
    sources = itertools.chain(files(args.history), ((name, pathlib.Path(name).read_bytes()) for name in args.artifact))
    for name, data in sources:
        for line, reason in findings(data):
            print(f'{name}:{line}: {reason}', file=sys.stderr)
            failed = True
    if failed:
        raise SystemExit(1)
    print('Cloud leak guard passed')


if __name__ == '__main__':
    main()
