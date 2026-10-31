#!/usr/bin/env python3
"""Checks a Tweak.xm module-split round without a compiler (v0.3.0 split; see OVERVIEW.md, "The Great Split").

    python3 tools/check_split.py [--old REV] [--logos PATH_TO_logos.pl] [--allow-wrapper NAME ...]

Run it from the repo root before committing a round. REV is the commit that holds the code before the round
(default HEAD; use HEAD~1 once the round is committed). It reads every OITI source file (.xm .mm .m .h, not the
prefs bundle or the helper tool) at REV and in the working tree and checks three things:

  1. LINES    The code lines (comments, blank lines and whitespace ignored) of the old and the new sources must be
              the same, except for the allowed edits: a dropped `static`, an added `extern`, #import lines and
              one-line prototypes. Anything else is listed as UNEXPECTED: a moved body that changed, or code that
              got lost or duplicated.
  2. SYMBOLS  Every file-level function or variable of the old sources that a new file uses must be defined in that
              file or declared in a header the file imports (directly or through other headers).
  3. LOGOS    With --logos, every .xm must pass through Logos without errors (github.com/theos/logos, bin/logos.pl),
              and the number of generated hook functions must equal the old one.

--allow-wrapper NAME  a new `void NAME(void) { %init(Group); }` function that a round added so a Logos group can be
              initialised from the %ctor in another file (round 3 on). Give it once per wrapper.

Exit status 0 = no problem found. It does not replace the build; it catches what a build would fail on.
"""
import argparse, collections, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_EXT = ('.xm', '.mm', '.m', '.h')
SKIP_DIRS = ('OITI/OITIPrefs/', 'OITI/OITIRestoreGestalt/', 'OITI/layout/')

def git(*args):
    return subprocess.run(['git', '-C', ROOT] + list(args), capture_output=True, text=True, check=True).stdout

def old_sources(rev):
    out = {}
    for path in git('ls-tree', '-r', '--name-only', rev, 'OITI').split('\n'):
        if path.endswith(SRC_EXT) and not path.startswith(SKIP_DIRS):
            out[path] = git('show', '%s:%s' % (rev, path))
    return out

def new_sources():
    out = {}
    for base, dirs, files in os.walk(os.path.join(ROOT, 'OITI')):
        rel = os.path.relpath(base, ROOT) + '/'
        if rel.startswith(SKIP_DIRS) or '.theos' in rel or '/packages' in rel: continue
        for f in files:
            if f.endswith(SRC_EXT):
                p = os.path.join(rel, f)
                out[p] = open(os.path.join(ROOT, p), encoding='utf-8').read()
    return out

def code_lines(text):
    """Lines with comments removed (string literals kept); returns list of (lineno, text) with empty ones dropped."""
    res = []; in_block = False
    for no, line in enumerate(text.split('\n'), 1):
        out = []; j = 0; n = len(line)
        while j < n:
            if in_block:
                k = line.find('*/', j)
                if k < 0: j = n; break
                in_block = False; j = k + 2; continue
            if line.startswith('//', j): break
            if line.startswith('/*', j): in_block = True; j += 2; continue
            c = line[j]
            if c == '"':
                k = j + 1
                while k < n and line[k] != '"':
                    if line[k] == '\\': k += 1
                    k += 1
                out.append(line[j:k + 1]); j = k + 1; continue
            out.append(c); j += 1
        t = re.sub(r'\s+', ' ', ''.join(out)).strip()
        if t: res.append((no, t))
    return res

def multiset(sources):
    c = collections.Counter()
    for text in sources.values():
        c.update(t for _, t in code_lines(text))
    return c

# ---------------------------------------------------------------------------------------------------------------
def check_lines(old, new, wrappers=()):
    only_old = multiset(old) - multiset(new)
    only_new = multiset(new) - multiset(old)
    def key(l):  # normal form for pairing: without a leading static/extern
        return re.sub(r'^(static|extern) ', '', l)
    paired = 0
    for l in list(only_old):
        for m in sorted(only_new, key=lambda x: x.startswith('extern ')):   # a definition pairs before a declaration
            if key(l) == key(m) and only_old[l] > 0 and only_new[m] > 0:
                n = min(only_old[l], only_new[m]); only_old[l] -= n; only_new[m] -= n; paired += n
    problems = []
    allowed_heads = {'void %s(void) {' % w for w in wrappers}
    allowed_closers = len(wrappers)      # each wrapper function ends with one lone '}'
    for l, n in only_old.items():
        if n > 0: problems.append('UNEXPECTED (only in old) x%d: %s' % (n, l[:150]))
    for l, n in only_new.items():
        if n <= 0: continue
        if l in allowed_heads: continue
        if l == '}' and n <= allowed_closers: continue
        if l.startswith('#import ') or re.match(r'^(extern )?[A-Za-z_].*\)\s*;$', l) or l.startswith('extern '):
            continue          # imports, prototypes, extern declarations
        problems.append('UNEXPECTED (only in new) x%d: %s' % (n, l[:150]))
    print('LINES: %d static/extern changes paired; %d problem(s)' % (paired, len(problems)))
    return problems

# ---------------------------------------------------------------------------------------------------------------
IDENT = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
KEYWORDS = {'return', 'if', 'else', 'for', 'while', 'switch', 'case', 'do', 'sizeof'}

def top_level_names(text):
    """(defined names, declared names) at file level, by line shape: column-0 lines at brace depth 0."""
    depth = 0; in_block = False; defined = set(); declared = set()
    for line in text.split('\n'):
        starts_ok = depth == 0 and not in_block and line and not line[0] in ' \t/#}@%*-+'
        if starts_ok:
            if line.startswith('extern ') or (line.rstrip().endswith(';') and '(' in line and '=' not in line):
                for m in IDENT.finditer(line): declared.add(m.group(0))
            else:
                m = re.match(r'^(?:static\s+)?[^=;(]*?\b([A-Za-z_]\w*)\s*\(', line)
                if m and '=' not in line.split('(')[0]: defined.add(m.group(1))
                else:
                    m = re.match(r'^(?:static\s+)?[^=;]*?\b([A-Za-z_]\w*)\s*(\[[^\]]*\])?\s*(=|;)', line)
                    if m: defined.add(m.group(1))
        j = 0; n = len(line)
        while j < n:
            if in_block:
                k = line.find('*/', j)
                if k < 0: break
                in_block = False; j = k + 2; continue
            if line.startswith('//', j): break
            if line.startswith('/*', j): in_block = True; j += 2; continue
            c = line[j]
            if c == '"':
                j += 1
                while j < n and line[j] != '"':
                    if line[j] == '\\': j += 1
                    j += 1
            elif c == "'":
                j += 1
                while j < n and line[j] != "'":
                    if line[j] == '\\': j += 1
                    j += 1
            elif c == '{': depth += 1
            elif c == '}': depth -= 1
            j += 1
    return defined - KEYWORDS, declared

def used_idents(text):
    used = set()
    for _, l in code_lines(text):
        l = re.sub(r'"(\\.|[^"\\])*"', '""', l)
        for m in IDENT.finditer(l):
            s, e = m.start(), m.end()
            if s > 0 and l[s - 1] == '.': continue
            if s > 1 and l[s - 2:s] == '->': continue
            if e < len(l) and l[e] == ':': continue
            used.add(m.group(0))
    return used

def imported_headers(path, sources, seen=None):
    seen = set() if seen is None else seen
    for m in re.finditer(r'^#import\s+"([^"]+)"', sources[path], re.M):
        for cand in (os.path.normpath(os.path.join(os.path.dirname(path), m.group(1))), os.path.normpath(os.path.join('OITI', m.group(1)))):
            if cand in sources and cand not in seen:
                seen.add(cand); imported_headers(cand, sources, seen); break
    return seen

def check_symbols(old, new):
    universe = set()
    for text in old.values():
        d, _ = top_level_names(text); universe |= d
    problems = []
    for path, text in sorted(new.items()):
        if not path.endswith(('.xm', '.mm', '.m')): continue
        mine, _ = top_level_names(text)
        visible = set(mine)
        for h in imported_headers(path, new):
            d, dec = top_level_names(new[h]); visible |= d | dec
        for n in sorted(used_idents(text) & universe - visible):
            problems.append('SYMBOL %s uses %s, which is neither defined in it nor declared in an imported header' % (path, n))
    print('SYMBOLS: %d problem(s)' % len(problems))
    return problems

# ---------------------------------------------------------------------------------------------------------------
def logos_hooks(logos, path_or_text, name, is_text):
    src = path_or_text
    if is_text:
        tmp = '/tmp/_check_split_%s' % os.path.basename(name)
        open(tmp, 'w', encoding='utf-8').write(path_or_text); src = tmp
    r = subprocess.run(['perl', logos, src], capture_output=True, text=True)
    if r.returncode != 0 or r.stderr.strip():
        return None, (r.stderr or 'exit %d' % r.returncode).strip()[:200]
    return r.stdout.count('_logos_orig'), None

def check_logos(logos, old, new):
    problems = []; total_old = 0; total_new = 0
    for path, text in old.items():
        if path.endswith('.xm'):
            n, err = logos_hooks(logos, text, path, True)
            if err: problems.append('LOGOS (old) %s: %s' % (path, err))
            else: total_old += n
    for path in new:
        if path.endswith('.xm'):
            n, err = logos_hooks(logos, os.path.join(ROOT, path), path, False)
            if err: problems.append('LOGOS %s: %s' % (path, err))
            else: total_new += n
    if total_old != total_new: problems.append('LOGOS hook count changed: %d -> %d' % (total_old, total_new))
    print('LOGOS: hooks %d -> %d; %d problem(s)' % (total_old, total_new, len(problems)))
    return problems

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--old', default='HEAD'); ap.add_argument('--logos'); ap.add_argument('--allow-wrapper', action='append', default=[], metavar='NAME')
    a = ap.parse_args()
    old, new = old_sources(a.old), new_sources()
    print('old: %d files at %s; new: %d files' % (len(old), a.old, len(new)))
    problems = check_lines(old, new, a.allow_wrapper) + check_symbols(old, new)
    if a.logos: problems += check_logos(a.logos, old, new)
    for p in problems: print('  ' + p)
    print('RESULT:', 'OK' if not problems else 'PROBLEMS FOUND')
    sys.exit(1 if problems else 0)

if __name__ == '__main__':
    main()
