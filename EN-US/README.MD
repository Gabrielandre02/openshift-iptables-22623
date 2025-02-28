# OpenShift Node Firewall Rule Removal Script

## Description
This script checks and removes firewall rules that may be blocking ports **22623** and **22624** on OpenShift cluster nodes.

## Prerequisites
- Access to an OpenShift cluster with permissions to debug nodes (`oc auth can-i debug nodes`).
- `iptables` or `nftables` available in the environment.
- `oc` CLI installed and configured.

## How to Run
1. Download the script and grant execution permissions:
```bash
chmod +x iptables-openshift-22623.sh
```

## Run the script:
```bash
./iptables-openshift-22623.sh
```

## Logs and Debugging
Execution logs are stored in /tmp/debug_output.log.
If an error occurs, the script will exit with code 1 and display affected nodes.

## Exit Codes
```bash
0: Success.
1: Errors were found.
2: Insufficient permissions.
```