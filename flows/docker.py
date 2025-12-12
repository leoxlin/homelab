from prefect.blocks.abstract import LoggerOrAdapter

from .utils import run_shell


def stop_container(log: LoggerOrAdapter, container_name: str) -> bool:
    run_code, _, run_err = run_shell(
        "sudo", "docker", "stop", "-t", "10", container_name
    )
    if len(run_err) > 0:
        err = "\n" + "\n".join(run_err)
        log.warning(f"Failed to stop container: {container_name}:{err}")
    return run_code == 0


def start_container(log: LoggerOrAdapter, container_name: str) -> bool:
    run_code, _, run_err = run_shell("sudo", "docker", "start", container_name)
    if len(run_err) > 0:
        err = "\n" + "\n".join(run_err)
        log.warning(f"Failed to start container: {container_name}:{err}")
    return run_code == 0
