import subprocess

from prefect import flow
from prefect.logging import get_run_logger

def run_shell(*cmd: str):
    out = subprocess.run(
        [arg for c in cmd for arg in c.split()],
        check=False,
        text=True,
        capture_output=True,
    )
    return out.returncode, out.stdout.splitlines(), out.stderr.splitlines()

@flow(log_prints=True)
def sysadmin_backup():
    print("boop")

@flow(log_prints=True)
def snapraid_sync(snapraid_conf: str):
    log = get_run_logger()
    diff_code, diff_out, diff_err = run_shell("sudo", "snapraid", "--conf", snapraid_conf, "diff")
    if len(diff_out) >= 8 and diff_out[-1] == 'There are differences!':
        diff = " ".join(l.strip() for l in diff_out[-8:][:7])
        log.info(f"Found diff in snapraid for syncing: {diff}")
