import logging
import subprocess

from prefect import flow
from prefect.logging import get_run_logger
from prefect.logging.loggers import LoggingAdapter


def run_shell(*cmd: str):
    out = subprocess.run(
        [arg for c in cmd for arg in c.split()],
        check=False,
        text=True,
        capture_output=True,
    )
    return out.returncode, out.stdout.splitlines(), out.stderr.splitlines()


def run_diff(
    log: logging.Logger | LoggingAdapter, snapraid_conf: str
) -> tuple[bool, dict[str, int]]:
    diff_code, diff_out, diff_err = run_shell(
        "sudo", "snapraid", "--conf", snapraid_conf, "diff"
    )
    if (
        diff_code == 2
        and len(diff_out) >= 8
        and diff_out[-1] == "There are differences!"
    ):
        diff = [line.strip() for line in diff_out[-8:-1]]
        stats = {stat.split()[1]: int(stat.split()[0]) for stat in diff}
        log.info(f"Found diff in snapraid: {' '.join(diff)}")
        return True, stats
    elif diff_code == 0 and len(diff_out) >= 8 and diff_out[-1] == "No differences":
        log.info("No diff in snapraid")
        return False, {}
    else:
        log.warning(f"Unexpected diff output code: {diff_code}")
        log.debug(f"snapraid-diff stdout: {' '.join(diff_out)}")
        log.debug(f"snapraid-diff stderr: {' '.join(diff_err)}")
        return False, {}


@flow(log_prints=True)
def sysadmin_backup():
    print("boop")


@flow(log_prints=True)
def snapraid(snapraid_conf: str):
    log = get_run_logger()
    _ = run_diff(log, snapraid_conf)
