from prefect import flow
from prefect.blocks.abstract import LoggerOrAdapter
from prefect.exceptions import FailedRun
from prefect.logging import get_run_logger

from .docker import start_container, stop_container
from .utils import run_shell, run_stream

WRITER_CONTAINERS = ["bazarr", "plex", "nzbget", "qbittorrent"]


def run_diff(log: LoggerOrAdapter, snapraid_conf: str) -> tuple[bool, dict[str, int]]:
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


def run_sync(log: LoggerOrAdapter, snapraid_conf: str):
    code = run_stream(
        lambda o: log.info(o),
        lambda o: log.error(o),
        "sudo",
        "snapraid",
        "--conf",
        snapraid_conf,
        "sync",
    )
    if code != 0:
        raise FailedRun(f"Failed to run snapraid sync on {snapraid_conf}")


def stop_writer_containers(log: LoggerOrAdapter):
    for container in WRITER_CONTAINERS:
        if not stop_container(log, container):
            raise FailedRun(f"Failed to stop containers: {container}")


def start_writer_containers(log: LoggerOrAdapter):
    for container in WRITER_CONTAINERS:
        if not start_container(log, container):
            raise FailedRun(f"Failed to start container: {container}")


@flow(log_prints=True)
def snapraid(mode: str, snapraid_conf: str):
    log = get_run_logger()
    match mode:
        case "sync":
            diff, _ = run_diff(log, snapraid_conf)
            if not diff:
                return
            stop_writer_containers(log)
            run_sync(log, snapraid_conf)
            start_writer_containers(log)
        case _:
            log.error(f"Cannot run unknown mode {mode} for snapraid")
