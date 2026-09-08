#!/bin/bash
# Shared OCI CLI profile selection for this lab bundle.

_oci_profile_values=()
for _oci_profile_value in "${OCI_PROFILE_NAME:-}" "${OCI_PROFILE:-}" "${OCI_CLI_PROFILE:-}"; do
  [ -z "${_oci_profile_value}" ] && continue
  if [[ " ${_oci_profile_values[*]} " != *" ${_oci_profile_value} "* ]]; then
    _oci_profile_values+=("${_oci_profile_value}")
  fi
done

if [ "${#_oci_profile_values[@]}" -gt 1 ]; then
  echo "ERROR: OCI_PROFILE_NAME, OCI_PROFILE, and OCI_CLI_PROFILE select different profiles." >&2
  echo "Set only one profile value before running this lab." >&2
  return 2 2>/dev/null || exit 2
fi

OCI_PROFILE_SELECTED="${_oci_profile_values[0]:-}"
OCI_PROFILE_ARGS=()
[ -n "${OCI_CONFIG_FILE:-${OCI_CLI_CONFIG_FILE:-}}" ] && OCI_PROFILE_ARGS+=(--config-file "${OCI_CONFIG_FILE:-${OCI_CLI_CONFIG_FILE:-}}")
[ -n "${OCI_PROFILE_SELECTED}" ] && OCI_PROFILE_ARGS+=(--profile "${OCI_PROFILE_SELECTED}")

oci_with_profile() {
  command oci "${OCI_PROFILE_ARGS[@]}" "$@"
}
