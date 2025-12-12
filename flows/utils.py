import subprocess
from typing import Callable


def run_shell(*cmd: str):
    out = subprocess.run(
        [arg for c in cmd for arg in c.split()],
        check=False,
        text=True,
        capture_output=True,
    )
    return out.returncode, out.stdout.splitlines(), out.stderr.splitlines()


def run_stream(
    out_func: Callable[[str], None],
    err_func: Callable[[str], None],
    *cmd: str,
):
    out = subprocess.Popen(
        [arg for c in cmd for arg in c.split()],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    for line in out.stdout or []:
        out_func(line)
    for line in out.stderr or []:
        err_func(line)
    _ = out.wait()
    return out.returncode
