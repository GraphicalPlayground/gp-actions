#!/bin/bash
# Copyright (c) - Graphical Playground. All rights reserved.
# For more information, see https://graphical-playground/legal
# mailto:support AT graphical-playground DOT com

# Guard against double-sourcing
[[ -n "${_GP_COMMON_LOADED:-}" ]] && return 0
_GP_COMMON_LOADED=1

# Color support — disabled when not a TTY or when NO_COLOR is set
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  _GP_RED='\033[0;31m'
  _GP_GREEN='\033[0;32m'
  _GP_YELLOW='\033[1;33m'
  _GP_BLUE='\033[0;34m'
  _GP_CYAN='\033[0;36m'
  _GP_MAGENTA='\033[0;35m'
  _GP_BOLD='\033[1m'
  _GP_DIM='\033[2m'
  _GP_RESET='\033[0m'
else
  _GP_RED='' _GP_GREEN='' _GP_YELLOW='' _GP_BLUE='' _GP_CYAN=''
  _GP_MAGENTA='' _GP_BOLD='' _GP_DIM='' _GP_RESET=''
fi

# Internal timer state
_GP_TIMER_START=0

# Open a collapsible log group
# Usage: gp.startGroup "My Group"
function gp.startGroup() {
  echo "::group::${1}"
}

# Close the current log group
# Usage: gp.endGroup
function gp.endGroup() {
  echo "::endgroup::"
}

# Run a block of commands inside a named group, then close it automatically
# Usage: gp.group "Build" cmake --build .
function gp.group() {
  local name="$1"; shift
  gp.startGroup "$name"
  "$@"
  local rc=$?
  gp.endGroup
  return $rc
}

# Emit a debug annotation (visible only when ACTIONS_STEP_DEBUG=true)
# Usage: gp.debug "verbose detail"
function gp.debug() {
  echo "::debug::${1}"
}

# Emit a notice annotation, optionally attached to a source location
# Usage: gp.notice "message" [file] [line] [col] [endLine] [endColumn] [title]
function gp.notice() {
  local message="$1"
  local file="${2:-}" line="${3:-}" col="${4:-}"
  local end_line="${5:-}" end_col="${6:-}" title="${7:-}"
  local meta
  meta="$(_gp_annotation_meta "$file" "$line" "$col" "$end_line" "$end_col" "$title")"
  [[ -n "$meta" ]] && echo "::notice ${meta}::${message}" || echo "::notice::${message}"
}

# Emit a warning annotation, optionally attached to a source location
# Usage: gp.warning "message" [file] [line] [col]
function gp.warning() {
  local message="$1"
  local file="${2:-}" line="${3:-}" col="${4:-}"
  local end_line="${5:-}" end_col="${6:-}" title="${7:-}"
  local meta
  meta="$(_gp_annotation_meta "$file" "$line" "$col" "$end_line" "$end_col" "$title")"
  [[ -n "$meta" ]] && echo "::warning ${meta}::${message}" || echo "::warning::${message}"
}

# Emit an error annotation, optionally attached to a source location
# Usage: gp.error "message" [file] [line] [col]
function gp.error() {
  local message="$1"
  local file="${2:-}" line="${3:-}" col="${4:-}"
  local end_line="${5:-}" end_col="${6:-}" title="${6:-}"
  local meta
  meta="$(_gp_annotation_meta "$file" "$line" "$col" "$end_line" "$end_col" "$title")"
  [[ -n "$meta" ]] && echo "::error ${meta}::${message}" || echo "::error::${message}"
}

# Mask a value so it is redacted in all subsequent log output
# Usage: gp.mask "$MY_SECRET"
function gp.mask() {
  echo "::add-mask::${1}"
}

# Stop processing workflow commands (safe to print literal :: strings until resumed)
# Prints the stop token — pass it to gp.resumeCommands
# Usage: token=$(gp.stopCommands); ...; gp.resumeCommands "$token"
function gp.stopCommands() {
  local token="gp-stop-$$-${RANDOM}"
  echo "::stop-commands::${token}"
  echo "$token"
}

# Resume workflow command processing after gp.stopCommands
# Usage: gp.resumeCommands "$token"
function gp.resumeCommands() {
  echo "::${1}::"
}

# Build the key=value metadata string used by annotation commands
function _gp_annotation_meta() {
  local file="$1" line="$2" col="$3" end_line="$4" end_col="$5" title="$6"
  local parts=()
  [[ -n "$file"     ]] && parts+=("file=${file}")
  [[ -n "$line"     ]] && parts+=("line=${line}")
  [[ -n "$col"      ]] && parts+=("col=${col}")
  [[ -n "$end_line" ]] && parts+=("endLine=${end_line}")
  [[ -n "$end_col"  ]] && parts+=("endColumn=${end_col}")
  [[ -n "$title"    ]] && parts+=("title=${title}")
  local IFS=','
  echo "${parts[*]}"
}

# Set a step output value (supports multi-line)
# Usage: gp.setOutput "name" "value"
function gp.setOutput() {
  local name="$1" value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      echo "${name}<<_GP_DELIM_${name}_$$"
      echo "${value}"
      echo "_GP_DELIM_${name}_$$"
    } >> "$GITHUB_OUTPUT"
  else
    echo "::set-output name=${name}::${value}"
  fi
}

# Export an environment variable to all subsequent steps
# Usage: gp.setEnv "MY_VAR" "value"
function gp.setEnv() {
  local name="$1" value="$2"
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    {
      echo "${name}<<_GP_DELIM_${name}_$$"
      echo "${value}"
      echo "_GP_DELIM_${name}_$$"
    } >> "$GITHUB_ENV"
  else
    echo "::set-env name=${name}::${value}"
  fi
  export "${name}=${value}"
}

# Prepend a directory to PATH for all subsequent steps
# Usage: gp.addPath "/usr/local/my-tool/bin"
function gp.addPath() {
  local path="$1"
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "$path" >> "$GITHUB_PATH"
  else
    echo "::add-path::${path}"
  fi
  export PATH="${path}:${PATH}"
}

# Read an action input by name (INPUT_<NAME> env convention)
# Dash and space in name are normalised to underscore
# Usage: value=$(gp.getInput "use-cache")
function gp.getInput() {
  local name="${1^^}"
  name="${name//[- ]/_}"
  local var="INPUT_${name}"
  echo "${!var:-}"
}

# Read a required input — exits 1 with an error if the value is empty
# Usage: value=$(gp.requireInput "token")
function gp.requireInput() {
  local value
  value="$(gp.getInput "$1")"
  if [[ -z "$value" ]]; then
    gp.fatal "Required input '${1}' is missing or empty."
  fi
  echo "$value"
}

# Assert that one or more environment variables are non-empty
# Usage: gp.requireEnv "GITHUB_TOKEN" "MY_SECRET"
function gp.requireEnv() {
  for var in "$@"; do
    if [[ -z "${!var:-}" ]]; then
      gp.fatal "Required environment variable '${var}' is not set."
    fi
  done
}

# Append raw markdown to the job step summary
# Usage: gp.summary "## My heading"
function gp.summary() {
  [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && echo "$1" >> "$GITHUB_STEP_SUMMARY"
}

function gp.summaryH1()  { gp.summary "# $1"; }
function gp.summaryH2()  { gp.summary "## $1"; }
function gp.summaryH3()  { gp.summary "### $1"; }
function gp.summaryHr()  { gp.summary "---"; }
function gp.summaryBlank() { gp.summary ""; }

# Append a fenced code block to the summary
# Usage: gp.summaryCode "$output" "bash"
function gp.summaryCode() {
  local content="$1" lang="${2:-}"
  gp.summary "\`\`\`${lang}"
  gp.summary "$content"
  gp.summary "\`\`\`"
}

# Append a Markdown table row (pass each cell as an argument)
# Usage: gp.summaryTableRow "Name" "Status" "Duration"
function gp.summaryTableRow() {
  local row="| "
  for cell in "$@"; do row+="${cell} | "; done
  gp.summary "$row"
}

# Append the separator row that turns the first row into a header
# Pass the same number of args as columns
function gp.summaryTableSep() {
  local sep="| "
  for _ in "$@"; do sep+=":--- | "; done
  gp.summary "$sep"
}

# Convenience: write a full table in one call
# First row is treated as the header
# Usage: gp.summaryTable "Name" "Value" ---- "foo" "bar" "baz" "qux"
function gp.summaryTable() {
  local -a rows=("$@")
  local cols=$#
  gp.summaryTableRow "${rows[@]:0:$cols}"
  local sep_args=()
  for (( i=0; i<cols; i++ )); do sep_args+=("-"); done
  gp.summaryTableSep "${sep_args[@]}"
}

function gp.log()     { echo -e "${_GP_RESET}${*}${_GP_RESET}"; }
function gp.info()    { echo -e "${_GP_BLUE}[INFO] ${_GP_RESET}${*}"; }
function gp.success() { echo -e "${_GP_GREEN}[OK]   ${_GP_RESET}${*}"; }
function gp.warn()    { echo -e "${_GP_YELLOW}[WARN] ${_GP_RESET}${*}"; }

# Print a bold section header
# Usage: gp.step "Configuring CMake"
function gp.step() {
  echo -e "\n${_GP_BOLD}${_GP_CYAN}>>> ${*}${_GP_RESET}"
}

# Log an error AND exit 1
# Usage: gp.fatal "Something went wrong"
function gp.fatal() {
  gp.error "${*}"
  echo -e "${_GP_RED}[FATAL]${_GP_RESET} ${*}" >&2
  exit 1
}

# Print all GITHUB_* environment variables (useful for debugging)
# Exception: GITHUB_TOKEN is redacted for security
function gp.dumpContext() {
  gp.startGroup "GitHub Actions Context"
  env | grep '^GITHUB_' | sort | sed 's/^GITHUB_TOKEN=.*/GITHUB_TOKEN=[REDACTED]/'
  gp.endGroup
}

# Returns: linux | macos | windows | unknown
function gp.getOS() {
  case "$(uname -s)" in
    Linux*)               echo "linux"   ;;
    Darwin*)              echo "macos"   ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *)                    echo "unknown" ;;
  esac
}

# Returns: x64 | arm64 | arm | x86 | <raw uname -m>
function gp.getArch() {
  case "$(uname -m)" in
    x86_64|amd64)  echo "x64"   ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l)        echo "arm"   ;;
    i386|i686)     echo "x86"   ;;
    *)             echo "$(uname -m)" ;;
  esac
}

function gp.isLinux()   { [[ "$(gp.getOS)"   == "linux"   ]]; }
function gp.isMacOS()   { [[ "$(gp.getOS)"   == "macos"   ]]; }
function gp.isWindows() { [[ "$(gp.getOS)"   == "windows" ]]; }
function gp.isX64()     { [[ "$(gp.getArch)" == "x64"     ]]; }
function gp.isArm64()   { [[ "$(gp.getArch)" == "arm64"   ]]; }

# Returns the Linux distribution ID from /etc/os-release (ubuntu, debian, fedora…)
function gp.getDistro() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    echo "${ID:-unknown}"
  elif command -v lsb_release &>/dev/null; then
    lsb_release -is | tr '[:upper:]' '[:lower:]'
  else
    echo "unknown"
  fi
}

# Returns VERSION_ID from /etc/os-release (e.g. "22.04")
function gp.getDistroVersion() {
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    echo "${VERSION_ID:-}"
  fi
}

# Returns the Ubuntu codename (e.g. "jammy", "noble") or empty string
function gp.getUbuntuCodename() {
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
  fi
}

function gp.isUbuntu()  { [[ "$(gp.getDistro)" == "ubuntu" ]]; }
function gp.isDebian()  { [[ "$(gp.getDistro)" == "debian" ]]; }
function gp.isFedora()  { [[ "$(gp.getDistro)" == "fedora" ]]; }
function gp.isAlpine()  { [[ "$(gp.getDistro)" == "alpine" ]]; }
function gp.isArch()    { [[ "$(gp.getDistro)" == "arch"   ]]; }

# Number of logical CPU cores (portable)
function gp.nproc() {
  if command -v nproc &>/dev/null; then
    nproc
  elif command -v sysctl &>/dev/null; then
    sysctl -n hw.logicalcpu
  else
    echo 1
  fi
}

# Total RAM in MiB (Linux / macOS)
function gp.ramMiB() {
  if [[ -f /proc/meminfo ]]; then
    awk '/^MemTotal/ { printf "%d\n", $2/1024 }' /proc/meminfo
  elif command -v sysctl &>/dev/null; then
    local bytes
    bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    echo $(( bytes / 1024 / 1024 ))
  else
    echo 0
  fi
}

function gp.isCI()          { [[ "${CI:-}" == "true" ]]; }
function gp.isPR()          { [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" ]]; }
function gp.isBranch()      { [[ "${GITHUB_REF:-}" == refs/heads/* ]]; }
function gp.isTag()         { [[ "${GITHUB_REF:-}" == refs/tags/* ]]; }
function gp.isMainBranch()  { [[ "${GITHUB_REF_NAME:-}" == "main" || "${GITHUB_REF_NAME:-}" == "master" ]]; }

function gp.getRepoOwner()  { echo "${GITHUB_REPOSITORY_OWNER:-}"; }
function gp.getRepoName()   { echo "${GITHUB_REPOSITORY:-}" | cut -d/ -f2; }
function gp.getRef()        { echo "${GITHUB_REF:-}"; }
function gp.getRefName()    { echo "${GITHUB_REF_NAME:-}"; }
function gp.getSHA()        { echo "${GITHUB_SHA:-}"; }
function gp.getShortSHA()   { echo "${GITHUB_SHA:0:7}"; }
function gp.getActor()      { echo "${GITHUB_ACTOR:-}"; }
function gp.getRunId()      { echo "${GITHUB_RUN_ID:-}"; }
function gp.getRunNumber()  { echo "${GITHUB_RUN_NUMBER:-}"; }
function gp.getWorkflow()   { echo "${GITHUB_WORKFLOW:-}"; }
function gp.getJob()        { echo "${GITHUB_JOB:-}"; }
function gp.getEventName()  { echo "${GITHUB_EVENT_NAME:-}"; }
function gp.getServerUrl()  { echo "${GITHUB_SERVER_URL:-https://github.com}"; }
function gp.getWorkspace()  { echo "${GITHUB_WORKSPACE:-$(pwd)}"; }
function gp.getActionPath() { echo "${GITHUB_ACTION_PATH:-}"; }

# Full URL to the current workflow run
function gp.getRunUrl() {
  echo "$(gp.getServerUrl)/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}"
}

# Branch name if on a branch push, empty otherwise
function gp.getBranch() {
  gp.isBranch && echo "${GITHUB_REF#refs/heads/}" || echo ""
}

# Tag name if on a tag push, empty otherwise
function gp.getTag() {
  gp.isTag && echo "${GITHUB_REF#refs/tags/}" || echo ""
}

# Require that the script is running inside a GitHub Actions workflow
function gp.requireCI() {
  gp.isCI || gp.fatal "This script must run inside a GitHub Actions workflow."
}

# Compare two semantic version strings
# Prints: -1 (a < b), 0 (a == b), or 1 (a > b)
# Usage: result=$(gp.versionCompare "1.2.3" "1.3.0")
function gp.versionCompare() {
  local a="$1" b="$2"
  [[ "$a" == "$b" ]] && { echo 0; return; }
  local IFS='.'
  local -a va=($a) vb=($b)
  local i
  for (( i=0; i < ${#va[@]} || i < ${#vb[@]}; i++ )); do
    local na="${va[i]:-0}" nb="${vb[i]:-0}"
    na="${na%%[^0-9]*}"   # strip pre-release suffixes
    nb="${nb%%[^0-9]*}"
    (( na < nb )) && { echo -1; return; }
    (( na > nb )) && { echo  1; return; }
  done
  echo 0
}

function gp.versionGte() { [[ "$(gp.versionCompare "$1" "$2")" -ge 0 ]]; }
function gp.versionGt()  { [[ "$(gp.versionCompare "$1" "$2")" -eq 1 ]]; }
function gp.versionLte() { [[ "$(gp.versionCompare "$1" "$2")" -le 0 ]]; }
function gp.versionLt()  { [[ "$(gp.versionCompare "$1" "$2")" -eq -1 ]]; }
function gp.versionEq()  { [[ "$(gp.versionCompare "$1" "$2")" -eq 0 ]]; }

function gp.versionMajor() { echo "${1%%.*}"; }
function gp.versionMinor() { local v="${1#*.}"; echo "${v%%.*}"; }
function gp.versionPatch() { local v="${1#*.}"; echo "${v#*.}"; }

# Strip a leading 'v' prefix (v1.2.3 → 1.2.3)
function gp.stripV() { echo "${1#v}"; }

# Returns 0 if a command is found in PATH
function gp.commandExists() { command -v "$1" &>/dev/null; }

# Exit with a fatal error if any of the listed commands are not in PATH
# Usage: gp.requireCommand cmake ninja git
function gp.requireCommand() {
  for cmd in "$@"; do
    gp.commandExists "$cmd" || gp.fatal "Required command not found in PATH: ${cmd}"
  done
}

# Run a command, logging the full invocation first
# Usage: gp.run cmake --build . --parallel
function gp.run() {
  gp.info "$ $*"
  "$@"
}

# Run a command as root (no-op if already root, uses sudo otherwise)
function gp.sudo() {
  if [[ "$EUID" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

# Run a command silently, only showing output on failure
# Usage: gp.quiet make -j4
function gp.quiet() {
  local tmp
  tmp=$(gp.tempFile)
  if ! "$@" >"$tmp" 2>&1; then
    cat "$tmp" >&2
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
}

# Retry a command up to <max> times with a fixed <delay> between attempts
# Usage: gp.retry 3 5 curl -fsSL https://example.com
function gp.retry() {
  local max="$1" delay="$2"; shift 2
  local attempt=1
  while true; do
    "$@" && return 0
    if (( attempt >= max )); then
      gp.error "Command failed after ${max} attempts: $*"
      return 1
    fi
    gp.warn "Attempt ${attempt}/${max} failed — retrying in ${delay}s…"
    sleep "$delay"
    (( attempt++ ))
  done
}

# Retry with exponential backoff (delay doubles each attempt, starting at 1s)
# Usage: gp.retryBackoff 5 curl -fsSL https://example.com
function gp.retryBackoff() {
  local max="$1"; shift
  local delay=1 attempt=1
  while true; do
    "$@" && return 0
    if (( attempt >= max )); then
      gp.error "Command failed after ${max} attempts: $*"
      return 1
    fi
    gp.warn "Attempt ${attempt}/${max} failed — retrying in ${delay}s…"
    sleep "$delay"
    delay=$(( delay * 2 ))
    (( attempt++ ))
  done
}

function gp.fileExists()   { [[ -f "$1" ]]; }
function gp.dirExists()    { [[ -d "$1" ]]; }
function gp.isReadable()   { [[ -r "$1" ]]; }
function gp.isWritable()   { [[ -w "$1" ]]; }
function gp.isExecutable() { [[ -x "$1" ]]; }
function gp.isSymlink()    { [[ -L "$1" ]]; }

# Exit if any of the listed files do not exist
function gp.requireFile() {
  for f in "$@"; do
    gp.fileExists "$f" || gp.fatal "Required file not found: ${f}"
  done
}

# Exit if any of the listed directories do not exist
function gp.requireDir() {
  for d in "$@"; do
    gp.dirExists "$d" || gp.fatal "Required directory not found: ${d}"
  done
}

# Create directories, including parents (no-op if already exists)
function gp.ensureDir() {
  for d in "$@"; do
    mkdir -p "$d"
  done
}

# Create a secure temporary directory and print its path
function gp.tempDir() {
  mktemp -d "${TMPDIR:-/tmp}/gp-actions-XXXXXX"
}

# Create a secure temporary file and print its path
function gp.tempFile() {
  mktemp "${TMPDIR:-/tmp}/gp-actions-XXXXXX"
}

# SHA-256 hash of a single file (works on both Linux and macOS)
function gp.hashFile() {
  if gp.commandExists sha256sum; then
    sha256sum "$1" | cut -d' ' -f1
  elif gp.commandExists shasum; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    gp.fatal "No sha256sum or shasum found in PATH"
  fi
}

# Combined hash of one or more files (stable, order-independent)
function gp.hashFiles() {
  local combined
  combined=$(for f in "$@"; do
    [[ -f "$f" ]] && gp.hashFile "$f"
  done | sort | tr -d '\n')
  echo "$combined" | sha256sum 2>/dev/null | cut -d' ' -f1 \
    || echo "$combined" | shasum -a 256 | cut -d' ' -f1
}

# File size in bytes (portable Linux/macOS)
function gp.fileSize() {
  if stat --version &>/dev/null 2>&1; then
    stat --printf="%s" "$1"
  else
    stat -f%z "$1"
  fi
}

# Resolve the absolute real path of a file or directory
function gp.realpath() {
  if gp.commandExists realpath; then
    realpath "$1"
  else
    ( cd "$(dirname "$1")" && echo "$(pwd)/$(basename "$1")" )
  fi
}

# Start the internal timer
function gp.timerStart() {
  _GP_TIMER_START=$(date +%s)
}

# Stop the timer and print a human-readable elapsed string (e.g. "2m 5s")
function gp.timerElapsed() {
  local end
  end=$(date +%s)
  local secs=$(( end - _GP_TIMER_START ))
  local h=$(( secs / 3600 ))
  local m=$(( (secs % 3600) / 60 ))
  local s=$(( secs % 60 ))
  if   (( h > 0 )); then printf "%dh %dm %ds" "$h" "$m" "$s"
  elif (( m > 0 )); then printf "%dm %ds" "$m" "$s"
  else                   printf "%ds" "$s"
  fi
}

# Time a command and log the elapsed duration afterwards
# Usage: gp.time cmake --build .
function gp.time() {
  gp.timerStart
  "$@"
  local rc=$?
  local elapsed
  elapsed=$(gp.timerElapsed)
  gp.info "Elapsed: ${elapsed}  ($*)"
  return $rc
}

function gp.toLower()    { echo "${1,,}"; }
function gp.toUpper()    { echo "${1^^}"; }
function gp.isEmpty()    { [[ -z "${1:-}" ]]; }
function gp.isNotEmpty() { [[ -n "${1:-}" ]]; }
function gp.contains()   { [[ "$1" == *"$2"* ]]; }
function gp.startsWith() { [[ "$1" == "$2"* ]]; }
function gp.endsWith()   { [[ "$1" == *"$2" ]]; }

# Trim leading and trailing whitespace
function gp.trim() {
  local s="$1"
  s="${s#"${s%%[! $'\t']*}"}"
  s="${s%"${s##*[! $'\t']}"}"
  echo "$s"
}

# Repeat a string N times
# Usage: gp.repeat "=" 40
function gp.repeat() {
  local str="$1" n="$2" result=""
  for (( i=0; i<n; i++ )); do result+="$str"; done
  echo "$result"
}

# Print a horizontal divider line
# Usage: gp.divider 60
function gp.divider() {
  gp.repeat "─" "${1:-60}"
}

# URL-encode a string (RFC 3986)
function gp.urlEncode() {
  local string="$1" encoded="" pos c o
  for (( pos=0; pos<${#string}; pos++ )); do
    c="${string:$pos:1}"
    case "$c" in
      [-_.~a-zA-Z0-9]) encoded+="$c" ;;
      *) printf -v o '%%%02X' "'$c"; encoded+="$o" ;;
    esac
  done
  echo "$encoded"
}

# Slugify a string (lowercase, spaces/slashes → dashes, strip non-alnum/dash)
function gp.slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' /' '--' | tr -cd '[:alnum:]-'
}

# Pad a string on the right to a minimum width
# Usage: gp.padRight "text" 20
function gp.padRight() {
  printf "%-${2}s" "$1"
}

# Check whether an array contains a specific value
# Usage: gp.arrayContains "needle" "${array[@]}"
function gp.arrayContains() {
  local needle="$1"; shift
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

# Join array elements with a delimiter
# Usage: gp.arrayJoin "," "a" "b" "c"  →  a,b,c
function gp.arrayJoin() {
  local delim="$1" result=""; shift
  for item in "$@"; do
    [[ -n "$result" ]] && result+="$delim"
    result+="$item"
  done
  echo "$result"
}

# Print unique values, preserving order
function gp.arrayUniq() {
  printf '%s\n' "$@" | awk '!seen[$0]++'
}

function gp.hasJq() { gp.commandExists jq; }

# Extract a value from a JSON string using a jq filter
# Usage: gp.jsonGet '{"k":"v"}' '.k'
function gp.jsonGet() {
  local json="$1" query="$2"
  echo "$json" | jq -r "$query"
}

# Extract a value from a JSON file using a jq filter
# Usage: gp.jsonGetFile path/to/file.json '.version'
function gp.jsonGetFile() {
  local file="$1" query="$2"
  jq -r "$query" "$file"
}

# Read the event payload for the current workflow run
function gp.getEventPayload() {
  local file="${GITHUB_EVENT_PATH:-}"
  [[ -f "$file" ]] && cat "$file" || echo "{}"
}

# Download a URL to a destination file, retrying up to 3 times by default
# Usage: gp.download "https://example.com/file.tar.gz" "/tmp/file.tar.gz"
function gp.download() {
  local url="$1" dest="$2" attempts="${3:-3}"
  gp.info "Downloading: ${url} → ${dest}"
  if gp.commandExists curl; then
    gp.retry "$attempts" 5 \
      curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 30 -o "$dest" "$url"
  elif gp.commandExists wget; then
    gp.retry "$attempts" 5 \
      wget -q --timeout=30 -O "$dest" "$url"
  else
    gp.fatal "Neither curl nor wget is available."
  fi
}

# Download and extract a .tar.gz archive to a directory
# Usage: gp.downloadTarGz "https://…/archive.tar.gz" "/opt/tool" [--strip-components=1]
function gp.downloadTarGz() {
  local url="$1" dest="$2"; shift 2
  local tmp
  tmp=$(gp.tempFile)
  gp.download "$url" "$tmp"
  gp.ensureDir "$dest"
  tar -xzf "$tmp" -C "$dest" "$@"
  rm -f "$tmp"
}

# Return 0 if a URL is reachable (HEAD request)
function gp.checkUrl() {
  local url="$1"
  if gp.commandExists curl; then
    curl -fsSL --head --silent "$url" &>/dev/null
  elif gp.commandExists wget; then
    wget -q --spider "$url" &>/dev/null
  else
    return 1
  fi
}

# apt-get install with automatic sudo and quiet output
# Usage: gp.aptInstall cmake ninja-build
function gp.aptInstall() {
  gp.requireCommand apt-get
  gp.info "apt-get install: $*"
  DEBIAN_FRONTEND=noninteractive gp.sudo apt-get install -y --no-install-recommends "$@"
}

# apt-get update (quiet)
function gp.aptUpdate() {
  gp.sudo apt-get update -qq
}

# apt-get update then install
function gp.aptInstallUpdated() {
  gp.aptUpdate
  gp.aptInstall "$@"
}

# Add an apt repository (PPA or signed sources-list entry)
# Usage: gp.aptAddRepo "ppa:ubuntu-toolchain-r/test"
function gp.aptAddRepo() {
  gp.requireCommand add-apt-repository
  gp.sudo add-apt-repository -y "$@"
}

# Add an apt signing key from a URL
# Usage: gp.aptAddKey "https://example.com/key.gpg" "/etc/apt/trusted.gpg.d/example.gpg"
function gp.aptAddKey() {
  local url="$1" dest="${2:-/etc/apt/trusted.gpg.d/gp-key.gpg}"
  local tmp
  tmp=$(gp.tempFile)
  gp.download "$url" "$tmp"
  gp.sudo mv "$tmp" "$dest"
  gp.sudo chmod 644 "$dest"
}

# brew install (macOS / Linux Homebrew)
function gp.brewInstall() {
  gp.requireCommand brew
  brew install "$@"
}

# pip install
function gp.pipInstall() {
  gp.requireCommand pip3
  pip3 install --quiet "$@"
}

# Generate a cache key suffix from the hash of one or more lock files
# Usage: key="mylib-$(gp.cacheKey CMakeLists.txt vcpkg.json)"
function gp.cacheKey() {
  local parts=()
  for f in "$@"; do
    [[ -f "$f" ]] && parts+=("$(gp.hashFile "$f")")
  done
  gp.arrayJoin '-' "${parts[@]}"
}

# Assert a condition; exit with a message if it evaluates to false
# Usage: gp.assert test -f "myfile.txt" "myfile.txt must exist before this step"
function gp.assert() {
  # Last argument is the message, all preceding args are the test expression
  local msg="${*: -1}"
  local -a cond=("${@:1:$#-1}")
  if ! "${cond[@]}" 2>/dev/null; then
    gp.fatal "Assertion failed: ${msg}"
  fi
}

# Emit a deprecation notice, optionally pointing to a replacement
# Usage: gp.deprecate "old-input" "new-input"
function gp.deprecate() {
  local old="$1" new="${2:-}"
  local msg="DEPRECATED: '${old}' is deprecated."
  [[ -n "$new" ]] && msg+=" Use '${new}' instead."
  gp.warning "$msg"
}

# Print all available gp.* function names (useful for help / discovery)
function gp.help() {
  echo "Available gp.* functions:"
  declare -F | awk '{print $3}' | grep '^gp\.' | grep -v '^_' | sort \
    | awk '{printf "  %s\n", $1}'
}

# Set all env vars and outputs for the local test environment (simulate a workflow run)
function gp.mockCI() {
  export CI=true
  export GITHUB_EVENT_NAME="push"
  export GITHUB_REPOSITORY="GraphicalPlayground/gp-actions"
  export GITHUB_REPOSITORY_OWNER="GraphicalPlayground"
  export GITHUB_REF="refs/heads/main"
  export GITHUB_REF_NAME="main"
  export GITHUB_SHA="abcdef1234567890"
  export GITHUB_RUN_ID="123456789"
  export GITHUB_RUN_NUMBER="42"
  export GITHUB_WORKFLOW="Test Workflow"
  export GITHUB_JOB="test-job"
  export GITHUB_SERVER_URL="https://github.com"
  export GITHUB_WORKSPACE="$(pwd)"
  export GITHUB_ACTION_PATH="$(pwd)"
  export GITHUB_ENV="/dev/stdout"
  export GITHUB_OUTPUT="/dev/stdout"
  export GITHUB_TOKEN="ghp_mocktoken1234567890"
}
