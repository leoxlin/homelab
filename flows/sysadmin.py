import os

from prefect import flow

@flow(log_prints=True)
def sysadmin_backup():
    print("boop")

@flow(log_prints=True)
def snapraid_sync():
    print(os.getcwd())
    print("boop")
