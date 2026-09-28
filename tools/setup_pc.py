"""Set up this computer for Pog Raid development (double-click 'Set up this PC.bat').

1. Finds World of Warcraft and the Forever client folder (asks if there's more than one).
2. Links the project's PogRaid folder into that client's Interface\\AddOns (a junction), so edits are live
   after /reload. A real PogRaid folder already there (say, from CurseForge) is renamed, not deleted.
3. Installs lupa (what the tests use) and runs the tests.
"""
import datetime
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "PogRaid")


def say(msg=""):
    print(msg, flush=True)


def wow_roots():
    roots = []
    try:
        import winreg
        for hive, key in ((winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft"),
                          (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Blizzard Entertainment\World of Warcraft")):
            try:
                with winreg.OpenKey(hive, key) as k:
                    path = winreg.QueryValueEx(k, "InstallPath")[0]
                    # InstallPath points inside a client folder (e.g. ...\_retail_\)
                    roots.append(os.path.dirname(os.path.normpath(path)))
            except OSError:
                pass
    except ImportError:
        pass
    for drive in "CDEFGH":
        for sub in (r"Program Files (x86)\World of Warcraft", r"Program Files\World of Warcraft", r"World of Warcraft",
                    r"Games\World of Warcraft", r"Blizzard\World of Warcraft"):
            roots.append(f"{drive}:\\{sub}")
    seen, out = set(), []
    for r in roots:
        r = os.path.normpath(r)
        if r.lower() not in seen and os.path.isdir(r):
            seen.add(r.lower())
            out.append(r)
    return out


def clients():
    """Client folders (like _classic_beta_) under every WoW install found."""
    found = []
    for root in wow_roots():
        for name in sorted(os.listdir(root)):
            path = os.path.join(root, name)
            if name.startswith("_") and name.endswith("_") and os.path.isdir(path):
                found.append(path)
    return found


def pick_client():
    found = clients()
    forever = [c for c in found if "classic_beta" in c.lower() or "forever" in c.lower()]
    if len(forever) == 1:
        return forever[0]
    choices = forever or found
    if choices:
        say("Which World of Warcraft client is Forever?")
        for i, c in enumerate(choices, 1):
            say(f"  {i}. {c}")
        say("  (or paste the full path of the client folder)")
    else:
        say("I couldn't find World of Warcraft. Paste the full path of the Forever client folder")
        say("(the one with Interface and WTF inside, e.g. C:\\Program Files (x86)\\World of Warcraft\\_classic_beta_):")
    while True:
        answer = input("> ").strip().strip('"')
        if answer.isdigit() and choices and 1 <= int(answer) <= len(choices):
            return choices[int(answer) - 1]
        if answer and os.path.isdir(answer):
            return answer
        say("That isn't one of the choices or a folder that exists. Try again.")


def is_link(path):
    """A junction or a directory symlink (either works for WoW)."""
    if os.path.islink(path):
        return True
    isjunction = getattr(os.path, "isjunction", None)  # Python 3.12+
    if isjunction:
        return isjunction(path)
    return os.path.normcase(os.path.realpath(path)) != os.path.normcase(os.path.abspath(path))


def link(client):
    addons = os.path.join(client, "Interface", "AddOns")
    os.makedirs(addons, exist_ok=True)
    target = os.path.join(addons, "PogRaid")
    if os.path.lexists(target):
        if is_link(target):
            if os.path.normcase(os.path.realpath(target)) == os.path.normcase(os.path.realpath(ADDON)):
                say(f"Already linked: {target}")
                return True
            os.rmdir(target)  # removes only the link, never what it points to
        else:
            # set aside outside AddOns, so WoW never lists it
            backups = os.path.join(client, "Interface", "PogRaid-backups")
            os.makedirs(backups, exist_ok=True)
            backup = os.path.join(backups, "PogRaid-" + datetime.datetime.now().strftime("%Y-%m-%d-%H%M"))
            os.rename(target, backup)
            say("There was a regular PogRaid folder there, probably installed by the CurseForge app.")
            say(f"Moved it out of the way to:\n  {backup}")
            say("On a computer you develop on, don't let the CurseForge app install or update Pog Raid:")
            say("it replaces the link with its own copy and your edits stop showing up in game.")
    r = subprocess.run(["cmd", "/c", "mklink", "/J", target, ADDON], capture_output=True, text=True)
    if r.returncode != 0:
        say("Couldn't create the link: " + (r.stderr or r.stdout).strip())
        say("If WoW is under Program Files, try right-clicking 'Set up this PC.bat' > Run as administrator.")
        return False
    say(f"Linked {target}\n    -> {ADDON}")
    return True


def lupa():
    try:
        import lupa  # noqa: F401
        say("lupa is installed.")
        return True
    except ImportError:
        say("Installing lupa (the tests need it)...")
        r = subprocess.run([sys.executable, "-m", "pip", "install", "lupa"])
        return r.returncode == 0


def main():
    say("Pog Raid: setting up this computer")
    say("")
    client = pick_client()
    ok = link(client)
    say("")
    ok = lupa() and ok
    say("")
    if ok:
        say("Running the tests (about a minute)...")
        r = subprocess.run([sys.executable, os.path.join(ROOT, "tests", "run_tests.py")])
        ok = r.returncode == 0
        say("")
    if ok:
        say("All set. Start WoW (or restart it if it was open) and type /pog.")
    else:
        say("Something above needs attention before this computer is ready.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
