#!/usr/bin/env zsh

set -e +x

SCRIPT_FILE=$(realpath "$0")

_run_fzf_picker() {
  local state_file=$(mktemp)
  echo "hidden" > "$state_file"
  trap 'rm -f "$state_file"' EXIT
  fzf --layout=reverse --info='inline: | ' --pointer=' ' --scrollbar='' "$@" \
    --bind="ctrl-p:toggle-preview+transform([[ \$(cat $state_file) = hidden ]] && echo visible > $state_file || echo hidden > $state_file)" \
    --bind="ctrl-u:transform([[ \$(cat $state_file) = visible ]] && echo preview-half-page-up || echo half-page-up)" \
    --bind="ctrl-d:transform([[ \$(cat $state_file) = visible ]] && echo preview-half-page-down || echo half-page-down)"
}

_view_in_editor() {
  nvim -R -c "set nomodifiable" -c "nnoremap q :q<CR>" "$@"
}

_resolve_context_namespace() {
  local ctx="${1:-$(kubectl config current-context)}"
  local ns="${2:-$(kubectl --context "$ctx" config view --minify --output 'jsonpath={..namespace}')}"
  echo "$ctx" "${ns:-default}"
}

_list_containers() {
  local ctx="$1" res="$2" name="$3"; shift 3
  kubectl --context "$ctx" "$@" get "$res/$name" \
    -o go-template='{{range .spec.template.spec.containers}}{{.name}} {{.image}}{{"\n"}}{{end}}{{range .spec.containers}}{{.name}} {{.image}}{{"\n"}}{{end}}' 2>/dev/null
}

_select_container_interactive() {
  local ctx="$1" res="$2" name="$3"; shift 3
  local enter_action="$1"; shift
  _list_containers "$ctx" "$res" "$name" "$@" |
    _run_fzf_picker --ghost='type to search containers' --prompt='container: ' --delimiter=' ' \
    --bind="enter:execute:$enter_action"
}

_exec_into_container() {
  local ctx="$1" res="$2" name="$3"; shift 3
  _select_container_interactive "$ctx" "$res" "$name" \
    "kubectl --context $ctx $* exec -it $res/$name -c {1} \
      -- sh -c 'command -v bash >/dev/null && exec bash || exec sh'" "$@"
}

_view_resource_yaml() {
  local ctx="$1" res="$2" name="$3"; shift 3
  kubectl --context "$ctx" "$@" get "$res/$name" -o yaml 2>/dev/null | _view_in_editor -c "set ft=yaml" - > /dev/tty
}

_browse_resource_types() {
  local ctx="$1" ns="$2"
  local cmd="kubectl api-resources --verbs=list -o wide 2>/dev/null | sort"

  _run_fzf_picker --header-lines=1 --ghost='type to search resource types...' \
    --prompt="[$ctx|$ns] resources> " \
    --header=$'>> enter (browse) | C-r (reload) | C-p (preview) <<\n' \
    --preview-window=hidden,right,border-left \
    --bind="start:reload:($cmd)" \
    --bind="ctrl-r:reload:($cmd)" \
    --bind="enter:become(
      source $SCRIPT_FILE
      local namespaced={4}
      [[ \$namespaced != true && \$namespaced != false ]] && namespaced={3}
      _browse_resources $ctx $ns {1} \$namespaced
    )" \
    --preview='kubectl explain {1}'
}

_select_namespace() {
  local ctx="$1" prompt="$2"
  kubectl --context "$ctx" get ns --no-headers -o custom-columns=':metadata.name' 2>/dev/null |
    _run_fzf_picker --prompt="$prompt" \
      --header=$'>> enter (select) | C-p (preview) <<\n' \
      --preview-window=hidden,right,border-left \
      --preview="kubectl --context $ctx describe ns {}" \
      --bind='enter:become:(echo {1})'
}

_browse_namespaces() {
  local ctx="$1" res="$2"
  local ns=$(_select_namespace "$ctx" "[$ctx] namespace> ")
  [[ -n "$ns" ]] && _browse_resources "$ctx" "$ns" "$res" true
}

_browse_resources() {
  local ctx="$1" ns="$2" res="$3" namespaced="$4"
  local name_field multi_flag="" ns_flag_str="" kubectl_list_cmd="--context $ctx get $res -o wide"
  if [[ "$namespaced" == false ]]; then
    name_field="{2}"; ns_flag_str=""
  elif [[ "$ns" == "all" ]]; then
    name_field="{3}"; ns_flag_str="-n {2}"; multi_flag="--multi=1"
    kubectl_list_cmd="$kubectl_list_cmd -A"
  else
    name_field="{2}"; ns_flag_str="-n $ns"
    kubectl_list_cmd="$kubectl_list_cmd -n $ns"
  fi

  local display_ns="$ns"
  [[ "$namespaced" == false ]] && display_ns="cluster"
  local cmd="kubectl $kubectl_list_cmd 2>/dev/null | sed -e '1s#^#TYPE  #' -e '2,\$s#^#$res  #'"

  local kubectl_base_flags="--context $ctx${ns_flag_str:+ $ns_flag_str}"
  local enter_bind="enter:become(printf '${ns_flag_str:+$ns_flag_str }%s' $name_field)"
  local header=">> enter (select) | C-e (edit) | C-f (forward) | C-l (logs) | C-s (ssh/scale) | C-x (delete) | C-y (yaml) | C-p (preview) <<"

  # Default ghost text and bindings (non-namespaced resources)
  local ghost_text='C-t switch type | C-r reload'
  local ctrl_n_bind='ctrl-n:ignore'

  # Add namespace-switching capability for namespaced resources
  if [[ "$namespaced" != false ]]; then
    ghost_text='C-t switch type | C-n switch namespace | C-r reload'
    ctrl_n_bind="ctrl-n:become(source $SCRIPT_FILE && _browse_namespaces $ctx $res)"
  fi

  _run_fzf_picker --header-lines=1 -d " +" --separator='' --with-nth="2.." \
    --ghost="$ghost_text" \
    --multi $multi_flag \
    --prompt="[$ctx|$display_ns] $res > " \
    --header="$header" \
    --preview-window=hidden,right,border-left \
    --bind="start:reload:$cmd" \
    --bind="ctrl-r:reload($cmd)" \
    --bind="ctrl-t:become(source $SCRIPT_FILE && _browse_resource_types $ctx $ns)" \
    --bind="$ctrl_n_bind" \
    --bind="$enter_bind" \
    --bind="ctrl-y:execute:source $SCRIPT_FILE && _view_resource_yaml $ctx {1} $name_field${ns_flag_str:+ $ns_flag_str}" \
    --bind="ctrl-e:execute:kubectl $kubectl_base_flags edit {1} $name_field" \
    --bind="ctrl-x:execute:
      delete_cmd=\"kubectl $kubectl_base_flags delete {1} $name_field\"
      echo \$delete_cmd && echo -n 'Run the command above? (y/N): ' && read confirm && \
        [[ \$confirm =~ ^[Yy]\$ ]] && eval \$delete_cmd" \
    --bind="ctrl-s:execute:
      # 'po*' matches pod/pods (kubectl resource abbreviation)
      if [[ {1} == po* ]]; then
        source $SCRIPT_FILE && _exec_into_container $ctx {1} $name_field${ns_flag_str:+ $ns_flag_str} > /dev/tty
      else
        echo -n 'Enter the replicas: ' && read replicas && \
          [[ \$replicas =~ ^[0-9]+\$ ]] && kubectl $kubectl_base_flags scale --replicas=\$replicas {1} $name_field
      fi" \
    --bind="ctrl-l:execute:kubectl $kubectl_base_flags logs {1}/$name_field -f; \
      echo -n 'Press any key to continue:' && read" \
    --bind="ctrl-f:execute:echo -n 'Enter local:remote port (e.g., 8080:80): ' && read ports && \
      kubectl $kubectl_base_flags port-forward $name_field \$ports > /dev/tty" \
    --preview="kubectl $kubectl_base_flags describe {1} $name_field"
}

k() {
  if [[ $# -eq 0 ]]; then
    local ctx ns
    read -r ctx ns <<< "$(_resolve_context_namespace)"
    _browse_resource_types "$ctx" "$ns"
    return
  fi

  local context="" namespace="" resource_type="" output="" found_get=false
  local args=()

  while [[ $# -gt 0 ]]; do
    case $1 in
      --context=*) context="${1#*=}"; args+=("$1"); shift ;;
      --context)   context="$2"; args+=("$1" "$2"); shift 2 ;;
      --namespace=*) namespace="${1#*=}"; args+=("$1"); shift ;;
      -n=*)          namespace="${1#*=}"; args+=("$1"); shift ;;
      --namespace|-n) namespace="$2"; args+=("$1" "$2"); shift 2 ;;
      -A)          namespace=all; args+=("$1"); shift ;;
      --output=*)  output="${1#*=}"; args+=("$1"); shift ;;
      -o=*)        output="${1#*=}"; args+=("$1"); shift ;;
      --output|-o) output="$2"; args+=("$1" "$2"); shift 2 ;;
      -o*)         output="${1#-o}"; args+=("$1"); shift ;;
      get)         found_get=true; args+=("$1"); shift ;;
      *)
        if $found_get && [[ -z "$resource_type" && "$1" != -* ]]; then
          resource_type="$1"
        fi
        args+=("$1"); shift ;;
    esac
  done

  set -- "${args[@]}"
  case "$1" in
    ctx)
      shift
      local ctx_current ns_current
      read -r ctx_current ns_current <<< "$(_resolve_context_namespace "$context" "$namespace")"
      local ctx=$(
        kubectl config get-contexts "$@" 2>/dev/null |
          _run_fzf_picker --header-lines=1 \
          --prompt "[$ctx_current|${ns_current:-default}] contexts> " \
          --bind='enter:become:(echo {1})'
      )
      [[ -n "$ctx" && "$ctx" != "*" ]] && kubectl config use-context "$ctx" "$@"
      ;;
    ns)
      shift
      local ctx ns_current
      read -r ctx ns_current <<< "$(_resolve_context_namespace "$context" "$namespace")"
      local ns=$(_select_namespace "$ctx" "[$ctx|${ns_current:-default}] namespaces> ")
      [[ -n "$ns" ]] && kubectl config set "contexts.$ctx.namespace" "$ns" "$@"
      ;;
    *)
      # Fall through to plain kubectl for non-get commands, missing resource types,
      # or specific output formats (only -o wide triggers interactive mode)
      if [[ "$found_get" != true || -z "$resource_type" || ( -n "$output" && "$output" != "wide" ) ]]; then
        kubectl "$@"
        return
      fi

      local ctx ns
      read -r ctx ns <<< "$(_resolve_context_namespace "$context" "$namespace")"

      local namespaced=true
      if kubectl api-resources --namespaced=false --no-headers 2>/dev/null \
          | awk -v r="$resource_type" '$1==r||$2==r{found=1} END{exit !found}'; then
        namespaced=false
      fi

      _browse_resources "$ctx" "$ns" "$resource_type" "$namespaced"
      ;;
  esac
}

main() {
  # Check required dependencies
  local cmd
  for cmd in kubectl fzf; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "Error: $cmd is not installed or not in PATH" >&2
      exit 1
    fi
  done
  k "$@"
}

_kfc_widget() {
  [[ -z "$commands[kubectl]" ]] && return
  local result
  result=$(k)
  if [[ -n "$result" ]]; then
    LBUFFER+="$result"
  fi
  zle reset-prompt
}

_kfc_setup_widget() {
  zle -N _kfc_widget
  bindkey -M viins '^k' _kfc_widget
}

# Only setup widget when explicitly requested during sourcing
if [[ -n "$KFC_WIDGET" ]]; then
  _kfc_setup_widget
fi

(
  [[ -n $ZSH_VERSION && $ZSH_EVAL_CONTEXT =~ :file$ ]] ||
  [[ -n $BASH_VERSION ]] && (return 0 2>/dev/null)
) || main "$@"
