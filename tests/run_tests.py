"""Run PogRaid's headless tests under Lua 5.1 (WoW's Lua). Needs: pip install lupa"""
import os, sys
from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.environ.get("POGRAID_DIR") or os.path.join(os.path.dirname(HERE), "PogRaid").replace("\\", "/")

lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.execute(open(os.path.join(HERE, "wowstub.lua"), encoding="utf-8").read())
run = lua.eval("function(src, dir) return assert(loadstring(src, '@test_pograid.lua'))(dir) end")
res = run(open(os.path.join(HERE, "test_pograid.lua"), encoding="utf-8").read(), ADDON)
print(f"{res['pass']} passed, {res['fail']} failed")
for i in range(1, res['fail'] + 1):
    print("  FAIL:", res['failures'][i])
# multi-client sync tests
import subprocess
sync = subprocess.run([sys.executable, os.path.join(HERE, "test_sync.py")], capture_output=True, text=True, env=os.environ)
print("sync:", sync.stdout.strip() or sync.stderr.strip()[-800:])
# launch-night sync load, small version (the full one: python tests/stress_sync.py)
stress = subprocess.run([sys.executable, os.path.join(HERE, "stress_sync.py"), "--quick"], capture_output=True, text=True, env=os.environ)
last = (stress.stdout.strip().splitlines() or ["STRESS FAIL (no output) " + stress.stderr.strip()[-600:]])[-1]
print("stress:", last)
# and with one message in ten lost on the way (loading screens)
lossy = subprocess.run([sys.executable, os.path.join(HERE, "stress_sync.py"), "--quick", "--loss", "0.1"], capture_output=True, text=True, env=os.environ)
lastLossy = (lossy.stdout.strip().splitlines() or ["STRESS FAIL (no output) " + lossy.stderr.strip()[-600:]])[-1]
print("stress, 10% of messages lost:", lastLossy)
sys.exit(1 if res['fail'] or sync.returncode or " 0 failed" not in sync.stdout or stress.returncode or lossy.returncode else 0)
