"""End to end, the addon's half: a scripted play session through the real addon (tests/e2e.lua).

Checks that everything the session did is in the addon's data, then writes the SavedVariables file and what the
site must read from it. Quarry's `collector_session_end_to_end` test sends that file through the server's import.

Usage: python -P tests/e2e.py [out dir]     (out dir: where collector-session.lua and .json go; none: only check)
"""
import os
import sys

from lupa import lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace("\\", "/")


def main() -> int:
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    with open(f"{ROOT}/tests/wowmock.lua", encoding="utf-8") as f:
        lua.execute(f.read())
    with open(f"{ROOT}/tests/e2e.lua", encoding="utf-8") as f:
        session = lua.execute("return function(...) local f = assert(loadstring(...)); return f end")(f.read())
    failures, saved, expect = session(ROOT)
    failures = list(failures.values())
    for line in failures:
        print("  FAIL " + line)
    if failures:
        print(f"\nend to end: {len(failures)} failed")
        return 1
    if len(sys.argv) > 1:
        out = sys.argv[1]
        os.makedirs(out, exist_ok=True)
        with open(os.path.join(out, "collector-session.lua"), "w", encoding="utf-8", newline="\n") as f:
            f.write(saved)
        with open(os.path.join(out, "collector-session.json"), "w", encoding="utf-8", newline="\n") as f:
            f.write(expect)
        print(f"wrote collector-session.lua ({len(saved)} bytes) and collector-session.json to {out}")
    print("end to end: the session's data is complete")
    return 0


if __name__ == "__main__":
    sys.exit(main())
