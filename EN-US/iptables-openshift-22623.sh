#!/usr/bin/env bash

# Definition of the image used for debugging in OpenShift
OCDEBUGIMAGE="quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:40c7eac9c5d21bb9dab4ef3bffa447c48184d28b74525e118147e29f96d32d8e"

# Number of parallel executions allowed
PARALLELJOBS=5

# Temporary file to store errors
ERRORFILE="/tmp/errorfile"

# Status codes for different results
OCERROR=1      # Error
OCOK=0         # Success
OCSKIP=2       # Insufficient permissions
OCUNKNOWN=3    # Unknown state

# Create a temporary file to store errors
tmperrorfile=$(mktemp)
trap "rm -f ${tmperrorfile}" EXIT  # Remove the temporary file upon script exit
echo 0 > "$tmperrorfile"

# Check if the user has permission to debug nodes in OpenShift
if ! oc auth can-i debug nodes >/dev/null 2>&1; then
  printf "No permission to debug nodes. Check your permissions.\n" >&2
  exit ${OCSKIP}
fi

printf "Checking and removing firewall rules on nodes...\n"

# Retrieve the list of nodes in the cluster
NODES=$(oc get nodes --no-headers -o custom-columns=":metadata.name")

# Iterate over each node to check and remove firewall rules
for node in ${NODES}; do
  ((i = i % PARALLELJOBS))  # Control parallel execution
  ((i++ == 0)) && wait
  (
    printf "Accessing node: %s\n" "$node"

    # Execute a debug command on the node and run a script inside the container
    OUTPUT=$(oc debug node/"${node}" -- bash -c '
      chroot /host /bin/bash -c "
        printf \"Checking and removing firewall rules...\n\"

        # Function to remove iptables rules
        remove_iptables_rules() {
          local CHAIN=\$1
          local PORT=\$2

          while true; do
            RULE_NUMS=\$(iptables -L \"\$CHAIN\" -n --line-numbers | grep \"dpt:\$PORT\" | awk \"{print \\\$1}\" | tac)

            [[ -z \"\$RULE_NUMS\" ]] && break

            for RULE_NUM in \$RULE_NUMS; do
              printf \"Removing rule %s number %s for port %s...\n\" \"\$CHAIN\" \"\$RULE_NUM\" \"\$PORT\"
              iptables -D \"\$CHAIN\" \"\$RULE_NUM\"
            done
          done
        }

        # Function to remove nftables rules
        remove_nft_rules() {
          local TABLE=\"filter\"
          local CHAIN=\$1
          local PORT=\$2

          RULE_HANDLES=\$(nft list ruleset | grep \"dport \$PORT\" | awk \"{print \\\$NF}\")

          for HANDLE in \$RULE_HANDLES; do
            printf \"Removing rule from chain %s for port %s (handle %s)...\n\" \"\$CHAIN\" \"\$PORT\" \"\$HANDLE\"
            nft delete rule ip \"\$TABLE\" \"\$CHAIN\" handle \"\$HANDLE\"
          done
        }

        # Check if iptables is available and execute rule removal
        if command -v iptables &>/dev/null && iptables -L &>/dev/null; then
          printf \"Using iptables...\n\"
          remove_iptables_rules FORWARD 22623
          remove_iptables_rules FORWARD 22624
          remove_iptables_rules OUTPUT 22623
          remove_iptables_rules OUTPUT 22624
        # Otherwise, check if nftables is available
        elif command -v nft &>/dev/null && nft list ruleset &>/dev/null; then
          printf \"Using nftables...\n\"
          remove_nft_rules FORWARD 22623
          remove_nft_rules FORWARD 22624
          remove_nft_rules OUTPUT 22623
          remove_nft_rules OUTPUT 22624
        else
          printf \"No compatible firewall found. Please check manually.\n\" >&2
          exit 1
        fi
      "
    ' 2>&1)

    # Record execution logs
    printf "NODE LOG %s:\n%s\n" "$node" "$OUTPUT" >> /tmp/debug_output.log

    # Check if rules were removed or if there was an error
    if [[ ${OUTPUT} =~ "Removing rule" ]]; then
      printf "Rules removed on node %s.\n" "$node"
    elif [[ ${OUTPUT} =~ "No compatible firewall found" ]]; then
      printf "Error on node %s: unsupported firewall.\n" "$node" >&2
      echo 1 > "$tmperrorfile"
    else
      printf "Unknown error on node %s. Check /tmp/debug_output.log\n" "$node" >&2
      echo 1 > "$tmperrorfile"
    fi
  ) &
done

wait

# Display the final result of the script
if [[ "$(cat "$tmperrorfile")" -eq 1 ]]; then
  printf "Errors were found on some nodes. Check logs in /tmp/debug_output.log\n" >&2
  exit ${OCERROR}
else
  printf "Process completed successfully. No rules blocking ports 22623/tcp and 22624/tcp were found or all were removed.\n"
  exit ${OCOK}
fi