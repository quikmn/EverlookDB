"""Run EverlookDB Collector's offline tests in Lua 5.1 (same version as WoW) via lupa.

Usage: python -P tests/run.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lupa import lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace("\\", "/")


def main() -> int:
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    with open(f"{ROOT}/tests/wowmock.lua", encoding="utf-8") as f:
        lua.execute(f.read())
    with open(f"{ROOT}/tests/run.lua", encoding="utf-8") as f:
        runner = lua.execute("return function(...) " + "local f = assert(loadstring(...)); return f end")(f.read())
    failures = runner(ROOT)
    # a second game: the addon updated and reloaded without a restart (new files not loaded)
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    with open(f"{ROOT}/tests/wowmock.lua", encoding="utf-8") as f:
        lua.execute(f.read())
    with open(f"{ROOT}/tests/norestart.lua", encoding="utf-8") as f:
        failures += lua.execute("return function(...) local f = assert(loadstring(...)); return f end")(f.read())(ROOT)
    # the scripted play session, as far as the addon goes (the server's half is Quarry's collector_session test)
    import e2e
    sys.argv = sys.argv[:1]
    failures += e2e.main()
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
