from prefect import flow
from prefect_shell import ShellOperation
from typing import List

def run_shell(cmd: str) -> List[str]:
    op = ShellOperation(commands=[cmd])
    return op.run()

@flow(log_prints=True)
def sysadmin_backup():
    print("boop")

@flow(log_prints=True)
def snapraid_sync(snapraid_conf: str):
    for line in run_shell(f"sudo snapraid --conf {snapraid_conf} diff"):
        print(line)
