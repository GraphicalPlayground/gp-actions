#!/bin/bash
# Copyright (c) - Graphical Playground. All rights reserved.
# For more information, see https://graphical-playground/legal
# mailto:support AT graphical-playground DOT com

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../common/common.sh
source "${_SCRIPT_DIR}/../../common/common.sh"

set -euo pipefail

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && \
  gp.fatal "This script is not intended to be sourced. Please run it directly."

gp.isCI || gp.mockCI

# Save current directory for later use; the SOT checkout step will change it
# to the SOT repo, but we need to return to the original workspace for syncing.
current_dir="$(pwd)"

#  Constants

readonly _SOT_PARTIAL_START="<!-- gp:protected:start -->"
readonly _SOT_PARTIAL_END="<!-- gp:protected:end -->"
readonly _SOT_LICENSE_DIR="licenses"

# Python script used for template substitution (defined here to avoid heredoc
# indentation issues inside functions)
read -r -d '' _SOT_TEMPLATE_PY << 'PYEOF' || true
import sys, json
with open(sys.argv[1]) as f:
    variables = json.load(f)
with open(sys.argv[2]) as f:
    content = f.read()
for k, v in variables.items():
    content = content.replace('{{' + k + '}}', v)
with open(sys.argv[3], 'w') as f:
    f.write(content)
PYEOF

#  Global state

declare -A _SOT_VARS=()
declare -a _SOT_RESULTS=()
_SOT_WORKSPACE=""
_SOT_PR_URL=""

#  Input parsing

_sot_parse_inputs() {
  local raw_input="$1"

  repository_name="$(gp.getRepoName)"
  repository_owner="$(gp.getRepoOwner)"

  _sot_field() { echo "$raw_input" | jq -r "${1} // empty"; }

  license="$(_sot_field '.license')"
  sot_repository="$(_sot_field '.["sot-repository"]')"
  sot_branch="$(_sot_field '.["sot-branch"]')"
  sot_path="$(_sot_field '.["sot-path"]')"
  allow_templatization="$(_sot_field '.["allow-templatization"]')"
  files_to_sync="$(_sot_field '.["file-to-sync"]')"
  custom_vars_raw="$(_sot_field '.["custom-vars"] // "{}"')"
  push_changes="$(_sot_field '.["push-changes"]')"
  target_branches="$(_sot_field '.["target-branches"]')"
  create_pr="$(_sot_field '.["create-pr"]')"
  pr_branch="$(_sot_field '.["pr-branch"]')"

  _SOT_WORKSPACE="$(gp.getWorkspace)"
}

#  GitHub API helpers

_sot_fetch_last_tag() {
  local repo="${repository_owner}/${repository_name}"
  if gp.commandExists gh; then
    gh release view --repo "$repo" --json tagName -q '.tagName' 2>/dev/null || true
  elif gp.commandExists curl; then
    curl -fsSL \
      -H "Accept: application/vnd.github+json" \
      ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
      "https://api.github.com/repos/${repo}/releases/latest" \
      2>/dev/null | jq -r '.tag_name // empty' 2>/dev/null || true
  fi
}

_sot_fetch_default_branch() {
  local repo="${repository_owner}/${repository_name}"
  if gp.commandExists gh; then
    gh repo view "$repo" --json defaultBranchRef \
      -q '.defaultBranchRef.name' 2>/dev/null || echo "main"
  else
    echo "main"
  fi
}

#  Template variable map

_sot_build_vars() {
  gp.startGroup "Building Template Variables"

  local last_tag default_branch
  last_tag="$(_sot_fetch_last_tag)"
  default_branch="$(_sot_fetch_default_branch)"

  # Built-in variables
  _SOT_VARS["GP_REPO_OWNER"]="$repository_owner"
  _SOT_VARS["GP_REPO_NAME"]="$repository_name"
  _SOT_VARS["GP_REPO_FULL_NAME"]="${repository_owner}/${repository_name}"
  _SOT_VARS["GP_YEAR"]="$(date +%Y)"
  _SOT_VARS["GP_DATE"]="$(date +%F)"
  _SOT_VARS["GP_LICENSE"]="${license}"
  _SOT_VARS["GP_LAST_TAG"]="${last_tag:-}"
  _SOT_VARS["GP_DEFAULT_BRANCH"]="${default_branch}"
  _SOT_VARS["GP_SOT_REPO"]="${sot_repository}"
  _SOT_VARS["GP_SOT_BRANCH"]="${sot_branch}"
  _SOT_VARS["GP_RUN_ID"]="$(gp.getRunId)"
  _SOT_VARS["GP_RUN_NUMBER"]="$(gp.getRunNumber)"

  # Custom variables from input
  if [[ -n "$custom_vars_raw" && "$custom_vars_raw" != "{}" ]]; then
    while IFS=$'\t' read -r key val; do
      [[ -n "$key" ]] && _SOT_VARS["$key"]="$val"
    done < <(echo "$custom_vars_raw" | jq -r 'to_entries[] | "\(.key)\t\(.value)"')
  fi

  for key in "${!_SOT_VARS[@]}"; do
    gp.info "  {{${key}}} = ${_SOT_VARS[$key]}"
  done

  gp.endGroup
}

#  Template substitution

_sot_apply_templates() {
  local input_file="$1"
  local output_file="$2"

  if [[ "$allow_templatization" != "true" ]]; then
    cp "$input_file" "$output_file"
    return 0
  fi

  # Build a JSON object of vars using jq to safely handle any value content
  local vars_json="{}"
  for key in "${!_SOT_VARS[@]}"; do
    vars_json=$(jq --arg k "$key" --arg v "${_SOT_VARS[$key]}" \
      '. + {($k): $v}' <<< "$vars_json")
  done

  local tmp_vars
  tmp_vars="$(gp.tempFile)"
  printf '%s' "$vars_json" > "$tmp_vars"

  if gp.commandExists python3; then
    python3 -c "$_SOT_TEMPLATE_PY" "$tmp_vars" "$input_file" "$output_file"
  else
    # Fallback: sed-based substitution (safe for simple single-line values)
    cp "$input_file" "$output_file"
    for key in "${!_SOT_VARS[@]}"; do
      local val="${_SOT_VARS[$key]}"
      # Escape chars special in sed replacement (\, &, and the | delimiter)
      local esc_val
      esc_val=$(printf '%s' "$val" | sed 's/[\\&|]/\\&/g')
      sed -i "s|{{${key}}}|${esc_val}|g" "$output_file"
    done
  fi

  rm -f "$tmp_vars"
}

#  Partial template support
#
#  A "partial" template is a SOT file that contains the protected-region markers.
#  The header (above the start marker) and footer (below the end marker) are
#  always overwritten from the SOT.  The protected region in the target file is
#  preserved; if the target has no markers yet the default content from the SOT
#  is used to seed the region.
#
#  SOT template layout:
#    <header, fully managed>
#    <!-- gp:protected:start -->
#    <default protected content>
#    <!-- gp:protected:end -->
#    <footer, fully managed>

_sot_is_partial() {
  grep -qF "$_SOT_PARTIAL_START" "$1"
}

_sot_merge_partial() {
  local sot_file="$1"    # SOT template with templates already applied
  local target_file="$2" # Destination file (may not exist)

  local tmp_header tmp_footer tmp_protected
  tmp_header="$(gp.tempFile)"
  tmp_footer="$(gp.tempFile)"
  tmp_protected="$(gp.tempFile)"

  # Header: everything before (and not including) the start marker
  # GNU sed 0,/pattern/ matches even if the pattern is on the first line
  sed -n "0,/^${_SOT_PARTIAL_START}$/{ /^${_SOT_PARTIAL_START}$/d; p }" \
    "$sot_file" > "$tmp_header"

  # Footer: everything after (and not including) the end marker
  sed -n "/^${_SOT_PARTIAL_END}$/,\${ /^${_SOT_PARTIAL_END}$/d; p }" \
    "$sot_file" > "$tmp_footer"

  # Protected content: prefer what is already in the target file
  if [[ -f "$target_file" ]] \
      && grep -qF "$_SOT_PARTIAL_START" "$target_file" \
      && grep -qF "$_SOT_PARTIAL_END" "$target_file"; then
    sed -n "/^${_SOT_PARTIAL_START}$/,/^${_SOT_PARTIAL_END}$/{
      /^${_SOT_PARTIAL_START}$/d
      /^${_SOT_PARTIAL_END}$/d
      p
    }" "$target_file" > "$tmp_protected"
  else
    # No existing protected region, use the default from the SOT template
    sed -n "/^${_SOT_PARTIAL_START}$/,/^${_SOT_PARTIAL_END}$/{
      /^${_SOT_PARTIAL_START}$/d
      /^${_SOT_PARTIAL_END}$/d
      p
    }" "$sot_file" > "$tmp_protected"
  fi

  # Assemble the final file
  {
    cat "$tmp_header"
    printf '%s\n' "$_SOT_PARTIAL_START"
    cat "$tmp_protected"
    printf '%s\n' "$_SOT_PARTIAL_END"
    cat "$tmp_footer"
  } > "$target_file"

  rm -f "$tmp_header" "$tmp_footer" "$tmp_protected"
}

#  Result tracking

_sot_record() {
  _SOT_RESULTS+=("${1}::${2}")
}

#  Sync a single file

_sot_sync_file() {
  local target_rel="$1"

  # Reject path traversal attempts
  if [[ "$target_rel" == *".."* ]]; then
    gp.warning "Skipping suspicious path: '${target_rel}'"
    _sot_record "$target_rel" "skipped (path traversal)"
    return 0
  fi

  # Resolve the source file in the SOT checkout
  local source_file
  if [[ "$target_rel" == "LICENSE.md" ]]; then
    source_file="${sot_path}/${_SOT_LICENSE_DIR}/${license}.md"
    if [[ ! -f "$source_file" ]]; then
      gp.warning "License '${license}' not found at '${source_file}', skipping LICENSE.md"
      _sot_record "LICENSE.md" "skipped (license '${license}' not found in SOT)"
      return 0
    fi
  else
    source_file="${sot_path}/${target_rel}"
    if [[ ! -f "$source_file" ]]; then
      gp.warning "Source not found in SOT: '${target_rel}', skipping"
      _sot_record "$target_rel" "skipped (not found in SOT)"
      return 0
    fi
  fi

  local target_file="${_SOT_WORKSPACE}/${target_rel}"
  gp.ensureDir "$(dirname "$target_file")"

  # Apply template substitutions into a temp file
  local tmp_content
  tmp_content="$(gp.tempFile)"
  _sot_apply_templates "$source_file" "$tmp_content"

  # Full overwrite or partial merge
  if _sot_is_partial "$source_file"; then
    gp.info "Partial sync : ${target_rel}"
    _sot_merge_partial "$tmp_content" "$target_file"
    _sot_record "$target_rel" "partial sync"
  else
    gp.info "Full sync    : ${target_rel}"
    cp "$tmp_content" "$target_file"
    _sot_record "$target_rel" "synced"
  fi

  rm -f "$tmp_content"
  gp.success "  ✓ ${target_rel}"
}

#  Commit and push changes

_sot_commit_and_push() {
  gp.startGroup "Committing Changes"

  cd "$current_dir"

  gp.requireCommand git

  git config --global user.name  "github-actions[bot]"
  git config --global user.email "github-actions[bot]@users.noreply.github.com"

  local sot_rel
  sot_rel="$(realpath --relative-to="$_SOT_WORKSPACE" "$sot_path")"
  git add -- . ":(exclude)${sot_rel}"

  if git diff --cached --quiet; then
    gp.info "No changes to commit."
    gp.endGroup
    return 0
  fi

  # Branch whitelist check
  local current_branch
  current_branch="$(git rev-parse --abbrev-ref HEAD)"

  local branch_allowed=false
  IFS=',' read -ra _allowed_branches <<< "$target_branches"
  for _b in "${_allowed_branches[@]}"; do
    _b="$(gp.trim "$_b")"
    if [[ "$_b" == "$current_branch" || "$_b" == "*" ]]; then
      branch_allowed=true
      break
    fi
  done

  if [[ "$branch_allowed" != "true" ]]; then
    gp.warning "Branch '${current_branch}' is not in target-branches (${target_branches}), skipping commit."
    gp.endGroup
    return 0
  fi

  local commit_msg="sync[bot]: from source of truth: ${sot_repository}@${sot_branch}"

  if [[ "$create_pr" == "true" ]]; then
    gp.requireCommand gh

    git checkout -B "$pr_branch"
    git commit -m "$commit_msg"
    git push --force-with-lease origin "$pr_branch"

    local existing_pr
    existing_pr="$(gh pr list \
      --head "$pr_branch" \
      --base "$current_branch" \
      --json number \
      --jq '.[0].number // empty' 2>/dev/null || true)"

    if [[ -z "$existing_pr" ]]; then
      _SOT_PR_URL="$(gh pr create \
        --title "$commit_msg" \
        --body "Automated synchronization from \`${sot_repository}@${sot_branch}\`, run [#$(gp.getRunNumber)]($(gp.getRunUrl))." \
        --base "$current_branch" \
        --head "$pr_branch")"
      gp.setOutput "pr-url" "$_SOT_PR_URL"
      gp.success "Pull request created: ${_SOT_PR_URL}"
    else
      gp.success "Pull request #${existing_pr} updated (branch force-pushed)."
    fi
  else
    git commit -m "$commit_msg"
    git push
    gp.success "Changes committed and pushed."
  fi

  gp.endGroup
}

#  Step summary

_sot_write_summary() {
  gp.summaryH2 "Source of Truth Sync"
  gp.summaryBlank
  gp.summaryTableRow "File" "Status"
  gp.summaryTableSep "-" "-"
  for entry in "${_SOT_RESULTS[@]}"; do
    gp.summaryTableRow "${entry%%::*}" "${entry##*::}"
  done
  gp.summaryBlank
  gp.summaryHr
  gp.summaryBlank
  gp.summary "_Synced from \`${sot_repository}@${sot_branch}\`, run [#$(gp.getRunNumber)]($(gp.getRunUrl))_"
  if [[ -n "$_SOT_PR_URL" ]]; then
    gp.summaryBlank
    gp.summary "_Pull request: ${_SOT_PR_URL}_"
  fi
}

#  Main

main() {
  gp.requireCommand jq
  gp.requireCommand sed

  if ! gp.isLinux; then
    gp.fatal "This script must run on Linux."
  fi

  # Parse inputs from stdin JSON
  local raw_input
  raw_input="$(cat)"
  _sot_parse_inputs "$raw_input"

  gp.startGroup "Configuration"
  gp.info "Repository    : ${repository_owner}/${repository_name}"
  gp.info "License       : ${license}"
  gp.info "SOT Repo      : ${sot_repository}"
  gp.info "SOT Branch    : ${sot_branch}"
  gp.info "SOT Path      : ${sot_path}"
  gp.info "Templatization: ${allow_templatization}"
  gp.info "Workspace     : ${_SOT_WORKSPACE}"
  gp.info "Files         : ${files_to_sync}"
  gp.info "Push Changes  : ${push_changes}"
  gp.info "Target Branches: ${target_branches}"
  gp.info "Create PR     : ${create_pr}"
  [[ "$create_pr" == "true" ]] && gp.info "PR Branch     : ${pr_branch}"
  gp.endGroup

  _sot_build_vars

  # Validate SOT path
  if [[ ! -d "$sot_path" ]]; then
    gp.fatal "SOT path does not exist: '${sot_path}'. Ensure the SOT repository was checked out."
  fi

  # Sync each requested file
  gp.startGroup "Synchronizing Files"
  local synced=0 skipped=0
  IFS=',' read -ra _files <<< "$files_to_sync"
  for _file in "${_files[@]}"; do
    _file="$(gp.trim "$_file")"
    [[ -z "$_file" ]] && continue
    if _sot_sync_file "$_file"; then
      (( synced++ )) || true
    else
      (( skipped++ )) || true
    fi
  done
  gp.endGroup

  gp.success "Done: ${synced} file(s) processed, ${skipped} error(s)."

  _sot_write_summary

  # Expose counts as step outputs
  gp.setOutput "synced-count" "$synced"
  gp.setOutput "skipped-count" "$skipped"

  [[ "$push_changes" == "true" ]] && _sot_commit_and_push
}

main
