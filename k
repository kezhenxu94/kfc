#!/usr/bin/env zsh

set -e +x

SCRIPT_FILE=$(realpath "$0")

__resolve_ctx_ns__() {
  local ctx="${1:-$(kubectl config current-context)}"
  local ns="${2:-$(kubectl --context "$ctx" config view --minify --output 'jsonpath={..namespace}')}"
  echo "$ctx" "${ns:-default}"
}

__fzf_base__() {
  fzf --layout=reverse --info='inline: | ' --pointer=' ' --scrollbar='' "$@"
}

__list_containers__() {
  local ctx="$1" ns="$2" res="$3" name="$4"
  kubectl --context "$ctx" -n "$ns" get "$res/$name" \
    -o go-template='{{range .spec.template.spec.containers}}{{.name}} {{.image}}{{"\n"}}{{end}}{{range .spec.containers}}{{.name}} {{.image}}{{"\n"}}{{end}}'
}

__set_image__() {
  local ctx="$1" ns="$2" res="$3" name="$4"
  __list_containers__ "$ctx" "$ns" "$res" "$name" |
    __fzf_base__ --ghost='type to search containers' --prompt='container: ' --delimiter=' ' \
    --bind="enter:execute:
      image={2}
      vared -p 'New image for container {1}: ' -c image && echo \"Setting image to \$image\" && \
        kubectl --context $ctx -n $ns set image $res/$name {1}=\$image && \
        echo -n 'Press any key to continue:' && read"
}

__ssh_into__() {
  local ctx="$1" ns="$2" res="$3" name="$4"
  __list_containers__ "$ctx" "$ns" "$res" "$name" |
    __fzf_base__ --ghost='type to search containers' --prompt='container: ' --delimiter=' ' \
    --bind="enter:execute:kubectl --context $ctx -n $ns exec -it $res/$name -c {1} \
      -- sh -c 'command -v bash >/dev/null && exec bash || exec sh'"
}

__switch_type__() {
  local ctx="$1" ns="$2" all_ns="$3"
  local ns_flag=$([[ "$all_ns" == true ]] && echo '-A' || echo "-n $ns")
  local cmd="kubectl api-resources --verbs=list -o wide | sort"

  __fzf_base__ --header-lines=1 --ghost='type to search resource types...' \
    --prompt="[ ctx=$ctx ns=$ns ] resources > " \
    --header=$'>> enter (browse) | C-r (reload) | C-p (preview) <<\n' \
    --preview-window=hidden,right,border-left \
    --bind="start:reload:($cmd)" \
    --bind="ctrl-r:reload:($cmd)" \
    --bind='ctrl-p:toggle-preview+refresh-preview,ctrl-u:preview-half-page-up,ctrl-d:preview-half-page-down' \
    --bind="enter:become(
      source $SCRIPT_FILE && __get_obj__ $ctx $ns {1} \
        \"--context $ctx get {1} $ns_flag -o wide\"
    )" \
    --preview='kubectl explain {1}'
}

__switch_ns__() {
  local ctx="$1" res="$2"
  __fzf_base__ --prompt='namespace: ' \
    --bind="enter:become(
      source $SCRIPT_FILE && __get_obj__ $ctx {} $res \
        \"--context $ctx get $res -n {} -o wide\"
    )" < <(kubectl --context "$ctx" get ns --no-headers -o custom-columns=':metadata.name')
}

__get_obj__() {
  local ctx="$1" ns_arg="$2" res="$3"
  shift 3
  local all_ns=$([[ "$ns_arg" == "all" ]] && echo true || echo false)
  local ns_field=$($all_ns && echo "{+2}" || echo "$ns_arg")
  local name_field=$($all_ns && echo "{+3}" || echo "{+2}")
  local cmd="kubectl $* | sed -e '1s#^#TYPE  #' -e '2,\$s#^#$res  #'"

  __fzf_base__ --header-lines=1 -d " +" --separator='' --with-nth="2.." \
    --ghost='C-t switch type | C-n switch namespace | C-r reload' \
    --multi $($all_ns && echo --multi=1) \
    --prompt="[ ctx=$ctx ns=$ns_arg ] $res > " \
    --header=">> enter (describe) | C-e (edit) | C-f (forward) | C-l (logs) | C-o (image) | C-s (ssh/scale) | C-x (delete) | C-y (yaml) | C-p (preview) <<" \
    --preview-window=hidden,right,border-left \
    --bind="start:reload:$cmd" \
    --bind='ctrl-p:toggle-preview+refresh-preview,ctrl-u:preview-half-page-up,ctrl-d:preview-half-page-down' \
    --bind="ctrl-r:reload($cmd)+clear-query" \
    --bind="ctrl-t:become(source $SCRIPT_FILE && __switch_type__ $ctx $ns_arg $all_ns)" \
    --bind="ctrl-n:become(source $SCRIPT_FILE && __switch_ns__ $ctx $res)" \
    --bind="enter:execute:kubectl --context $ctx describe {1} $name_field -n $ns_field | \${EDITOR:-less}" \
    --bind="ctrl-y:execute:kubectl --context $ctx get {1} $name_field -n $ns_field -o yaml | \${EDITOR:-less}" \
    --bind="ctrl-e:execute:kubectl --context $ctx edit {1} $name_field -n $ns_field" \
    --bind="ctrl-o:execute:source $SCRIPT_FILE && __set_image__ $ctx $ns_field {1} $name_field" \
    --bind="ctrl-x:execute:
      cc=\"kubectl --context $ctx -n $ns_field delete {1} $name_field\"
      echo \$cc && echo -n 'Run the command above? (y/N): ' && read confirm && \
        [[ \$confirm =~ ^[Yy]\$ ]] && eval \$cc" \
    --bind="ctrl-s:execute:
      if [[ {1} == po* ]]; then
        source $SCRIPT_FILE && __ssh_into__ $ctx $ns_field {1} $name_field > /dev/tty
      else
        echo -n 'Enter the replicas: ' && read replicas && \
          [[ \$replicas =~ ^[0-9]+\$ ]] && kubectl --context $ctx scale --replicas=\$replicas {1} $name_field -n $ns_field
      fi" \
    --bind="ctrl-l:execute:kubectl --context $ctx logs {1}/$name_field -n $ns_field -f; \
      echo -n 'Press any key to continue:' && read" \
    --bind="ctrl-f:execute:echo -n 'Enter local:remote port (e.g., 8080:80): ' && read ports && \
      kubectl --context $ctx port-forward $name_field -n $ns_field \$ports > /dev/tty" \
    --preview="kubectl --context $ctx describe {1} $name_field -n $ns_field"
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
      local ctx_current="${context:-$(kubectl config current-context)}"
      local ns_current="${namespace:-$(kubectl --context "$ctx_current" config view --minify --output 'jsonpath={..namespace}')}"
      local ctx=$(
        kubectl config get-contexts "$@" |
          __fzf_base__ --header-lines=1 \
          --prompt "[ ctx=$ctx_current ns=${ns_current:-default} ] contexts > " \
          --bind='enter:become:(echo {1})'
      )
      [[ -n "$ctx" && "$ctx" != "*" ]] && kubectl config use-context "$ctx" "$@"
      ;;
    ns)
      shift
      local ctx="${context:-$(kubectl config current-context)}"
      local ns_current="${namespace:-$(kubectl --context "$ctx" config view --minify --output 'jsonpath={..namespace}')}"
      local ns=$(
        kubectl get ns "$@" |
          __fzf_base__ --header-lines=1 \
          --prompt "[ ctx=$ctx ns=${ns_current:-default} ] namespaces > " \
          --bind='enter:become:(echo {1})'
      )
      [[ -n "$ns" ]] && kubectl config set "contexts.$ctx.namespace" "$ns" "$@"
      ;;
    *)
      if [[ "$found_get" != true || -z "$resource_type" || ( -n "$output" && "$output" != "wide" ) ]]; then
        kubectl "$@"
        return
      fi

      local ctx ns
      read -r ctx ns <<< "$(__resolve_ctx_ns__ "$context" "$namespace")"

      __get_obj__ "$ctx" "$ns" "$resource_type" "$@"
      ;;
  esac
}

main() {
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "Error: kubectl is not installed or not in PATH" >&2
    exit 1
  fi

  if ! command -v fzf >/dev/null 2>&1; then
    echo "Error: fzf is not installed or not in PATH" >&2
    exit 1
  fi

  k "$@"
}

(
  [[ -n $ZSH_VERSION && $ZSH_EVAL_CONTEXT =~ :file$ ]] ||
  [[ -n $BASH_VERSION ]] && (return 0 2>/dev/null)
) || main "$@"
