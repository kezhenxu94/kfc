#!/usr/bin/env zsh

set -e +x

SCRIPT_FILE=$(realpath "$0")

__resolve_ctx_ns__() {
  local ctx="${1:-$(kubectl config current-context)}"
  local ns="${2:-$(kubectl --context "$ctx" config view --minify --output 'jsonpath={..namespace}')}"
  echo "$ctx" "${ns:-default}"
}

__fzf_base__() {
  local state_file=$(mktemp)
  echo "hidden" > "$state_file"
  trap 'rm -f "$state_file"' EXIT
  fzf --layout=reverse --info='inline: | ' --pointer=' ' --scrollbar='' "$@" \
    --bind="ctrl-p:toggle-preview+transform([[ \$(cat $state_file) = hidden ]] && echo visible > $state_file || echo hidden > $state_file)" \
    --bind="ctrl-u:transform([[ \$(cat $state_file) = visible ]] && echo preview-half-page-up || echo half-page-up)" \
    --bind="ctrl-d:transform([[ \$(cat $state_file) = visible ]] && echo preview-half-page-down || echo half-page-down)"
}

__editor_base__() {
  nvim -R -c "set nomodifiable" -c "nnoremap q :q<CR>" "$@"
}

__list_containers__() {
  local ctx="$1" res="$2" name="$3"; shift 3
  kubectl --context "$ctx" "$@" get "$res/$name" \
    -o go-template='{{range .spec.template.spec.containers}}{{.name}} {{.image}}{{"\n"}}{{end}}{{range .spec.containers}}{{.name}} {{.image}}{{"\n"}}{{end}}' 2>/dev/null
}

__pick_container__() {
  local ctx="$1" res="$2" name="$3"; shift 3
  local enter_action="$1"; shift
  __list_containers__ "$ctx" "$res" "$name" "$@" |
    __fzf_base__ --ghost='type to search containers' --prompt='container: ' --delimiter=' ' \
    --bind="enter:execute:$enter_action"
}

__set_image__() {
  local ctx="$1" res="$2" name="$3"; shift 3
  __pick_container__ "$ctx" "$res" "$name" "
      image={2}
      vared -p 'New image for container {1}: ' -c image && echo \"Setting image to \$image\" && \
        kubectl --context $ctx $* set image $res/$name {1}=\$image && \
        echo -n 'Press any key to continue:' && read" "$@"
}

__ssh_into__() {
  local ctx="$1" res="$2" name="$3"; shift 3
  __pick_container__ "$ctx" "$res" "$name" \
    "kubectl --context $ctx $* exec -it $res/$name -c {1} \
      -- sh -c 'command -v bash >/dev/null && exec bash || exec sh'" "$@"
}

__view_yaml__() {
  local ctx="$1" res="$2" name="$3"; shift 3
  kubectl --context "$ctx" "$@" get "$res/$name" -o yaml 2>/dev/null | __editor_base__ -c "set ft=yaml" - > /dev/tty
}

__switch_type__() {
  local ctx="$1" ns="$2" all_ns="$3"
  local cmd="kubectl api-resources --verbs=list -o wide 2>/dev/null | sort"

  __fzf_base__ --header-lines=1 --ghost='type to search resource types...' \
    --prompt="[$ctx|$ns] resources> " \
    --header=$'>> enter (browse) | C-r (reload) | C-p (preview) <<\n' \
    --preview-window=hidden,right,border-left \
    --bind="start:reload:($cmd)" \
    --bind="ctrl-r:reload:($cmd)" \
    --bind="enter:become(
      source $SCRIPT_FILE
      namespaced={4}
      [[ \$namespaced != true && \$namespaced != false ]] && namespaced={3}
      if [[ \$namespaced == false ]]; then
        __get_obj__ $ctx $ns {1} false \"--context $ctx get {1} -o wide\"
      elif [[ '$all_ns' == true ]]; then
        __get_obj__ $ctx $ns {1} true \"--context $ctx get {1} -A -o wide\"
      else
        __get_obj__ $ctx $ns {1} true \"--context $ctx get {1} -n $ns -o wide\"
      fi
    )" \
    --preview='kubectl explain {1}'
}

__switch_ns__() {
  local ctx="$1" res="$2"
  __fzf_base__ --prompt='namespace: ' \
    --header=$'>> enter (browse) | C-p (preview) <<\n' \
    --preview-window=hidden,right,border-left \
    --preview="kubectl --context $ctx describe ns {}" \
    --bind="enter:become(
      source $SCRIPT_FILE && __get_obj__ $ctx {} $res true \
        \"--context $ctx get $res -n {} -o wide\"
    )" < <(kubectl --context "$ctx" get ns --no-headers -o custom-columns=':metadata.name' 2>/dev/null)
}

__get_obj__() {
  local ctx="$1" ns_arg="$2" res="$3" namespaced="$4"
  shift 4
  local all_ns=$([[ "$ns_arg" == "all" ]] && echo true || echo false)
  local name_field multi_flag="" ns_flag_str=""
  if [[ "$all_ns" == true ]]; then
    name_field="{+3}"; ns_flag_str="-n {+2}"; multi_flag="--multi=1"
  elif [[ "$namespaced" == false ]]; then
    name_field="{+2}"; ns_flag_str=""
  else
    name_field="{+2}"; ns_flag_str="-n $ns_arg"
  fi

  local display_ns="$ns_arg"
  [[ "$namespaced" == false ]] && display_ns="cluster"
  local cmd="kubectl $* 2>/dev/null | sed -e '1s#^#TYPE  #' -e '2,\$s#^#$res  #'"

  local enter_bind
  if [[ -n "$ns_flag_str" ]]; then
    enter_bind="enter:become(printf '$ns_flag_str %s' $name_field)"
  else
    enter_bind="enter:become(printf '%s' $name_field)"
  fi
  local header=">> enter (select) | C-e (edit) | C-f (forward) | C-l (logs) | C-o (image) | C-s (ssh/scale) | C-x (delete) | C-y (yaml) | C-p (preview) <<"

  local ghost_text ctrl_n_bind
  if [[ "$namespaced" == false ]]; then
    ghost_text='C-t switch type | C-r reload'
    ctrl_n_bind="ctrl-n:ignore"
  else
    ghost_text='C-t switch type | C-n switch namespace | C-r reload'
    ctrl_n_bind="ctrl-n:become(source $SCRIPT_FILE && __switch_ns__ $ctx $res)"
  fi

  __fzf_base__ --header-lines=1 -d " +" --separator='' --with-nth="2.." \
    --ghost="$ghost_text" \
    --multi $multi_flag \
    --prompt="[$ctx|$display_ns] $res > " \
    --header="$header" \
    --preview-window=hidden,right,border-left \
    --bind="start:reload:$cmd" \
    --bind="ctrl-r:reload($cmd)" \
    --bind="ctrl-t:become(source $SCRIPT_FILE && __switch_type__ $ctx $ns_arg $all_ns)" \
    --bind="$ctrl_n_bind" \
    --bind="$enter_bind" \
    --bind="ctrl-y:execute:source $SCRIPT_FILE && __view_yaml__ $ctx {1} $name_field $ns_flag_str" \
    --bind="ctrl-e:execute:kubectl --context $ctx $ns_flag_str edit {1} $name_field" \
    --bind="ctrl-o:execute:source $SCRIPT_FILE && __set_image__ $ctx {1} $name_field $ns_flag_str" \
    --bind="ctrl-x:execute:
      cc=\"kubectl --context $ctx $ns_flag_str delete {1} $name_field\"
      echo \$cc && echo -n 'Run the command above? (y/N): ' && read confirm && \
        [[ \$confirm =~ ^[Yy]\$ ]] && eval \$cc" \
    --bind="ctrl-s:execute:
      if [[ {1} == po* ]]; then
        source $SCRIPT_FILE && __ssh_into__ $ctx {1} $name_field $ns_flag_str > /dev/tty
      else
        echo -n 'Enter the replicas: ' && read replicas && \
          [[ \$replicas =~ ^[0-9]+\$ ]] && kubectl --context $ctx $ns_flag_str scale --replicas=\$replicas {1} $name_field
      fi" \
    --bind="ctrl-l:execute:kubectl --context $ctx $ns_flag_str logs {1}/$name_field -f; \
      echo -n 'Press any key to continue:' && read" \
    --bind="ctrl-f:execute:echo -n 'Enter local:remote port (e.g., 8080:80): ' && read ports && \
      kubectl --context $ctx $ns_flag_str port-forward $name_field \$ports > /dev/tty" \
    --preview="kubectl --context $ctx $ns_flag_str describe {1} $name_field"
}

k() {
  if [[ $# -eq 0 ]]; then
    local ctx ns
    read -r ctx ns <<< "$(__resolve_ctx_ns__)"
    __switch_type__ "$ctx" "$ns" false
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
      read -r ctx_current ns_current <<< "$(__resolve_ctx_ns__ "$context" "$namespace")"
      local ctx=$(
        kubectl config get-contexts "$@" 2>/dev/null |
          __fzf_base__ --header-lines=1 \
          --prompt "[$ctx_current|${ns_current:-default}] contexts> " \
          --bind='enter:become:(echo {1})'
      )
      [[ -n "$ctx" && "$ctx" != "*" ]] && kubectl config use-context "$ctx" "$@"
      ;;
    ns)
      shift
      local ctx ns_current
      read -r ctx ns_current <<< "$(__resolve_ctx_ns__ "$context" "$namespace")"
      local ns=$(
        kubectl get ns "$@" 2>/dev/null |
          __fzf_base__ --header-lines=1 \
          --prompt "[$ctx|${ns_current:-default}] namespaces> " \
          --bind='enter:become:(echo {1})'
      )
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
      read -r ctx ns <<< "$(__resolve_ctx_ns__ "$context" "$namespace")"

      local namespaced=true
      if [[ -z "$namespace" && "$ns" != "all" ]]; then
        if kubectl api-resources --namespaced=false --no-headers 2>/dev/null \
            | awk -v r="$resource_type" '$1==r||$2==r{found=1} END{exit !found}'; then
          namespaced=false
        fi
      fi

      __get_obj__ "$ctx" "$ns" "$resource_type" "$namespaced" "$@"
      ;;
  esac
}

main() {
  local cmd
  for cmd in kubectl fzf; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "Error: $cmd is not installed or not in PATH" >&2
      exit 1
    fi
  done

  k "$@"
}

(
  [[ -n $ZSH_VERSION && $ZSH_EVAL_CONTEXT =~ :file$ ]] ||
  [[ -n $BASH_VERSION ]] && (return 0 2>/dev/null)
) || main "$@"
