#!/usr/bin/env zsh

set -e +x

__get_obj__() {
  local ctx="$1"
  local ns=$([[ "$2" == "all" ]] && echo "{1} " || echo "$2")
  local name=$([[ "$2" == "all" ]] && echo "{2}" || echo "{1}")
  local res="$3"
  local cmd="kubectl ${@:4}"

  fzf --layout=reverse --header-lines=1 --info='inline: | ' --ghost='type to search...' \
    --pointer=' ' --scrollbar='' --multi $([[ "$2" == "all" ]] && echo --multi=1) \
    --prompt="[ ctx=$ctx ns=$namespace ] $res > " \
    --header=$'>> C-e (edit) || C-f (port-forward) || C-l (logs) || C-o (describe) || C-p (preview) || C-r (reload) || C-s (scale) || C-x (delete) <<\n' \
    --preview-window=hidden,right,border-left \
    --bind="start:reload:($cmd)" \
    --bind='enter:ignore' \
    --bind='ctrl-p:toggle-preview,ctrl-u:preview-half-page-up,ctrl-d:preview-half-page-down' \
    --bind="ctrl-r:reload:($cmd)" \
    --bind="ctrl-o:execute-multi:kubectl --context $ctx describe $res $name -n $ns | ${EDITOR:-vim} - -c 'setlocal buftype=nofile'" \
    --bind="ctrl-y:execute-multi:kubectl --context $ctx get $res $name -n $ns -o yaml | ${EDITOR:-vim} - -c 'setlocal buftype=nofile | setlocal filetype=yaml'" \
    --bind="ctrl-e:execute-multi:kubectl --context $ctx edit $res $name -n $ns" \
    --bind="ctrl-x:execute-multi:cc='kubectl --context=$ctx -n=$ns delete $res $name' && echo \${cc} && echo -n \"Run the command above? (y/N): \" && read confirm && [[ \$confirm =~ ^[Yy]\$ ]] && eval \$cc" \
    --bind="ctrl-s:execute-multi:echo -n 'Enter the replicas: ' && read replicas && [[ \$replicas =~ ^[0-9]+\$ ]] && kubectl --context $ctx scale --replicas=\$replicas $res $name -n $ns" \
    --bind="ctrl-l:execute:kubectl --context $ctx logs $res/$name -n $ns -f && echo -n 'Press any key to continue:' && read" \
    --bind="ctrl-f:execute:echo -n 'Enter local:remote port (e.g., 8080:80): ' && read ports && kubectl --context $ctx port-forward $name -n $ns \$ports > /dev/tty" \
    --preview="kubectl --context $ctx describe $res $name -n $ns"
}

# Function to show resource types
__list_resource_types() {
  local cmd="kubectl api-resources --verbs=list -o wide | sort"

  resource=$(fzf --layout=reverse --header-lines=1 --info='inline: | ' --ghost='type to search...' \
    --prompt="[ ctx=$(kubectl config current-context) ns=$namespace ] resources > " \
    --header=$'>> select Kubernetes resource type || CTRL-D (exit) <<\n\n' \
    --preview-window=hidden,right,border-left \
    --bind="start:reload:($cmd)" \
    --bind="ctrl-r:reload:($cmd)" \
    --bind='ctrl-p:toggle-preview,ctrl-u:preview-half-page-up,ctrl-d:preview-half-page-down' \
    --bind='enter:become:(echo {1})' \
    --preview='kubectl explain {1}')

  context="${context:-$(kubectl config current-context)}"
  namespace="${namespace:-$(kubectl --context $context config view --minify --output 'jsonpath={..namespace}')}"
  namespace="${namespace:-default}"

  [[ -n "$resource" ]] && __get_obj__ "$context" "$namespace" "$resource" "get $resource -n $namespace -o wide"
}

# Main kubectl wrapper function
k() {
  if [[ $# -eq 0 ]]; then
    __list_resource_types
    return
  fi

  local args=()
  local context=""
  local namespace=""
  local resource_type=""
  local output=""
  local found_get=false
  while [[ $# -gt 0 ]]; do
    args+=("$1")
    case $1 in
      --context=*)
        context="${1#--context=}"
        shift
        ;;
      --context)
        context="$2"
        args+=("$2")
        shift 2
        ;;
      --namespace=*|-n=*)
        namespace="${1#--namespace=}"
        namespace="${1#-n}"
        shift
        ;;
      --namespace|-n)
        namespace="$2"
        args+=("$2")
        shift 2
        ;;
      -A)
        namespace=all
        shift
        ;;
      --output=*|-o=*)
        output="${1#--output=}"
        output="${1#-o=}"
        shift
        ;;
      --output|-o)
        output="$2"
        args+=("$2")
        shift 2
        ;;
      -o*)
        output="${1#-o}"
        shift
        ;;
      -*|--*)
        shift
        ;;
      get)
        found_get=true
        shift
        ;;
      *)
        if [[ "$found_get" = true && -z "$resource_type" ]]; then
          resource_type="$1"
        fi
        shift
        ;;
    esac
  done

  set -- "${args[@]}"
  case "$1" in
    ctx)
      shift
      local ctx=$(
        kubectl config get-contexts "$@" |
          fzf --layout=reverse --header-lines=1 \
          --prompt "[ ctx=${context:-$(kubectl config current-context)} ns=${namespace:-$(kubectl config $@ view --minify --output 'jsonpath={..namespace}')}) ] contexts > " \
          --bind='enter:become:(echo {1})'
      )
      [[ -n "$ctx" && "$ctx" != "*" ]] && kubectl config use-context $ctx "$@"
      ;;
    ns)
      shift
      local ctx="${context:-$(kubectl config current-context)}"
      local ns=$(
        kubectl get ns "$@" | 
          fzf --layout=reverse --header-lines=1 \
          --prompt "[ ctx=$ctx ns=${namespace:-$(kubectl config $@ view --minify --output 'jsonpath={..namespace}' || "default")} ] namespaces > " \
          --bind='enter:become:(echo {1})'
      )
      [[ -n "$ns" ]] && kubectl config set contexts.$ctx.namespace $ns "$@"
      ;;
    *)
      if [[ -n "$output" && "$output" != "wide" || -z "$resource_type" || -z "$found_get" ]]; then
        kubectl "$@"
        return
      fi

      context="${context:-$(kubectl config current-context)}"
      namespace="${namespace:-$(kubectl --context $context config view --minify --output 'jsonpath={..namespace}')}"
      namespace="${namespace:-default}"

      __get_obj__ "$context" "$namespace" "$resource_type" "$@"
  esac
}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "Error: kubectl is not installed or not in PATH"
  exit 1
fi

if ! command -v fzf >/dev/null 2>&1; then
  echo "Error: fzf is not installed or not in PATH"
  exit 1
fi

k "$@"
