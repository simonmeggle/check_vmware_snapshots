# check_vmware_snapshots
Nagios plugin to check the number and age of snapshots in a VMWare vSphere environment 

## example config 

```
# command 'check_vmware_snapshots'
define command{
    command_name                   check_vmware_snapshots
    command_line                   $USER1$/check_vmware_snapshots.pl --server $HOSTADDRESS$ --username $ARG1$ --password $ARG2$ --mode $ARG3$ --critical $ARG4$ --warning $ARG5$ $ARG6$
}

# service 'Snapshot Age'
define service{
    service_description            Snapshot Age
    check_command                  check_vmware_snapshots!$USER4$!$USER5$!age!7!30
    ...
    }

# service 'Snapshot Count'
define service{
    service_description            Snapshot Count
    check_command                  check_vmware_snapshots!$USER4$!$USER5$!count!1!2
    ...
    }

# service 'Snapshot Count for all DWH VMs 
define service{
    service_description            Snapshot Count for all DWH VMs
    check_command                  check_vmware_snapshots!$USER4$!$USER5$!count!1!2!--whitelist 'emDWH.*'
    ...
    }

# service 'Snapshot count with Snapshot blacklist'
define service{
    service_description            Snapshot Count without Dev Snapshots
    check_command                  check_vmware_snapshots!$USER4$!$USER5$!count!1!2!--blacklist 'snapshot_dev_.*' --match_snapshot_names=1
    ...
    }
```

## Example Output

``` CRITICAL - Snapshot "Before update" (VM: 'vmHDX03-1') is 18.2 days old
 Snapshot "20120914_rc2" (VM: 'win2k8r2') is 32.9 days old
```


