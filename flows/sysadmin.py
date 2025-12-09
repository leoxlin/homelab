from prefect import flow

@flow(log_prints=True)
def sysadmin_backup():
    print("boop")

@flow(log_prints=True)
def snapraid_fs():
    print("boop")
