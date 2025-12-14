from prefect import flow
from prefect.blocks.abstract import LoggerOrAdapter
from prefect.exceptions import MissingFlowError
from prefect.main import get_run_logger

from .utils import must_run, run_shell


def stop_container(log: LoggerOrAdapter, container_name: str) -> bool:
    log.info(f"Stopping container: {container_name}")
    run_code, _, run_err = run_shell(
        "sudo", "docker", "stop", "-t", "10", container_name
    )
    if len(run_err) > 0:
        err = "\n" + "\n".join(run_err)
        log.warning(f"Failed to stop container: {container_name}:{err}")
    return run_code == 0


def start_container(log: LoggerOrAdapter, container_name: str) -> bool:
    log.info(f"Starting container: {container_name}")
    run_code, _, run_err = run_shell("sudo", "docker", "start", container_name)
    if len(run_err) > 0:
        err = "\n" + "\n".join(run_err)
        log.warning(f"Failed to start container: {container_name}:{err}")
    return run_code == 0


@flow(log_prints=True)
def docker(mode: str):
    log = get_run_logger()
    log.info(f"Running docker flow: {mode}")
    match mode:
        case "prune":
            must_run(
                "sudo",
                "docker",
                "container",
                "prune",
                "--filter",
                "until=24h",
                "--force",
            )
            must_run(
                "sudo", "docker", "image", "prune", "--filter", "until=24h", "--force"
            )
            must_run(
                "sudo", "docker", "network", "prune", "--filter", "until=24h", "--force"
            )
            must_run(
                "sudo",
                "docker",
                "volume",
                "prune",
                "--filter",
                "label!=keep",
                "--force",
            )
        case _:
            log.error(f"Unknown mode for docker flow: {mode}")
            raise MissingFlowError()
