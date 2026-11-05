# Python mirror of OITIGuardBeginLaunch / OITIEvaluateLoopGuard in OITI/Safety/OITISafety.xm (logic only, NOT the Objective-C).
# Keep it in step with that file; it tests the intended behavior of the loop guard (v0.3.0 batch 2). Run: python3 tools/guard_model.py
MAXL, WINDOW, STABLE, INTENT_AGE = 5, 120, 45, 30
class Phone:
    def __init__(s): s.files = {}; s.enabled = True
def begin(ph, now, st):
    st['launches'] = None; st['counted'] = False
    if not ph.enabled: return
    if ph.files.get('safe', {}).get('tripped'): return
    st['time'] = now
    intent = ph.files.pop('intent', None)
    if intent is not None:
        age = now - intent
        if 0 <= age < INTENT_AGE:
            ph.files['boot'] = []; st['requested'] = True; return
    launches = [t for t in ph.files.get('boot', []) if 0 <= now - t < WINDOW]
    launches.append(now); launches = launches[-16:]
    ph.files['boot'] = launches; st['launches'] = launches; st['counted'] = True
def evaluate(ph, st):
    if not ph.enabled: return False
    if ph.files.get('safe', {}).get('tripped'): return True
    if not st['counted']: return False
    if len(st['launches']) >= MAXL:
        ph.files['safe'] = {'tripped': True, 'time': st['time']}; return True
    return False   # a stable-timer would clear the history after STABLE s
def launch(ph, now, crash_in_prefs):
    st = {}; begin(ph, now, st); safe = evaluate(ph, st)
    prefs_ran = not safe
    crashed = prefs_ran and crash_in_prefs
    return safe, prefs_ran, crashed

# 1. the batch-1 failure: every launch crashes inside preferencesChanged
ph = Phone(); t = 1000.0; trips = None
for n in range(1, 9):
    safe, ran, crashed = launch(ph, t, crash_in_prefs=True)
    if safe and trips is None: trips = n
    if safe: break
    t += 8
assert trips == 5, trips
assert ph.files['safe']['tripped']
# next launch with a tripped flag: stays safe, no prefs, history untouched
before = list(ph.files['boot']); safe, ran, crashed = launch(ph, t + 8, True)
assert safe and not ran and not crashed and ph.files['boot'] == before
# 2. the OLD design (record in evaluate after prefs): crash before evaluate -> nothing recorded -> never trips
ph = Phone(); t = 1000.0
for n in range(20):
    # old: prefs first; crashes -> never reaches evaluate/record
    t += 8
assert 'boot' not in ph.files and 'safe' not in ph.files   # no trace at all, the loop continues forever
# 3. requested respring: not counted, history cleared
ph = Phone(); t = 1000.0
for n in range(3): launch(ph, t, False); t += 8
ph.files['intent'] = t - 5
safe, ran, crashed = launch(ph, t, False)
assert not safe and ran and ph.files['boot'] == [] 
# 4. stale marker is ignored (counted normally), and is consumed
ph = Phone(); ph.files['intent'] = 100.0
safe, ran, _ = launch(ph, 1000.0, False)
assert not safe and 'intent' not in ph.files and len(ph.files['boot']) == 1
# 5. old launches fall out of the window: 4 launches, a 2-minute gap, then more: no trip
ph = Phone(); t = 1000.0
for n in range(4): launch(ph, t, False); t += 8
t += 200
for n in range(3):
    safe, _, _ = launch(ph, t, False); assert not safe; t += 8
# 6. guard disabled: records nothing, never trips
ph = Phone(); ph.enabled = False
for n in range(10): assert launch(ph, 1000.0 + n, True)[0] is False
assert 'boot' not in ph.files and 'safe' not in ph.files
# 7. exactly like before for a normal healthy run: counts launches, trips only at the threshold
ph = Phone(); t = 1000.0
res = [launch(ph, t + 10*n, False)[0] for n in range(6)]
assert res == [False]*4 + [True, True], res
print("guard model: all scenarios pass (mirror of the logic, not the Objective-C)")
