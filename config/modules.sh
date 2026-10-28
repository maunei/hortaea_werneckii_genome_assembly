# Loads the software modules named in settings.yaml (key: modules) at the start of a job. Sourced by the job files before config.sh.
# Nothing is loaded when the key is empty or when the computer has no module system.
[ -f "$HW/config/local.sh" ] && source "$HW/config/local.sh"
if [ -n "${HW_MODULES:-}" ] && command -v module > /dev/null 2>&1; then module --force purge; module load $HW_MODULES; fi
