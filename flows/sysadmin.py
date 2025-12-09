import os

from prefect import flow
from prefect_shell import ShellOperation

@flow(log_prints=True)
def sysadmin_backup():
    print("boop")

@flow(log_prints=True)
def snapraid_sync():
    with ShellOperation(
        commands=[
            'sudo snapraid --version'
        ]
    ) as cmd:
        proc = cmd.trigger()
        proc.wait_for_completion()
        res = proc.fetch_result()
        print(res)
