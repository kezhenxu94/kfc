#!/usr/bin/env zsh

set -e +x

SCRIPT_FILE=$(realpath "$0")

__set_image__() {
  local ctx="$1"
  local ns="$2"
  local res="$3"
  local name="$4"
  kubectl --context $ctx -n $ns get $res/$name -o go-template='{{range .spec.template.spec.containers}}{{.name}} {{.image}}{{"\n"}}{{end}}{{range .spec.containers}}{{.name}} {{.image}}{{"\n"}}{{end}}' |
    fzf --layout=reverse --info='inline: | ' --ghost='type to search containers' \
    --pointer=' ' --scrollbar='' --prompt='container: ' --delimiter=' ' \
    --bind="enter:execute:
      image={2}
      vared -p 'New image for container {1}: ' -c image && echo \"Setting image to \$image\" && \
        kubectl --context $ctx -n $ns set image $res/$name {1}=\$image && echo -n 'Press any key to continue:' && read"
}

__ssh_into__() {
  local ctx="$1"
  local ns="$2"
  local res="$3"
  local name="$4"
  kubectl --context $ctx -n $ns get $res/$name -o go-template='{{range .spec.template.spec.containers}}{{.name}} {{.image}}{{"\n"}}{{end}}{{range .spec.containers}}{{.name}}{{"\n"}}{{end}}' |
    fzf --layout=reverse --info='inline: | ' --ghost='type to search containers' \
    --pointer=' ' --scrollbar='' --prompt='container: ' --delimiter=' ' \
    --bind="enter:execute:kubectl --context $ctx -n $ns exec -it $res/$name -c {1} -- sh -c 'command -v bash >/dev/null && exec bash || exec sh'"
}

__get_obj__() {
  local ctx="$1"
  local ns=$([[ "$2" == "all" ]] && echo "{1} " || echo "$2")
  local name=$([[ "$2" == "all" ]] && echo "{2}" || echo "{1}")
  local res="$3"
  local cmd="kubectl ${@:4}"

  fzf --layout=reverse --header-lines=1 --info='inline: | ' --separator='' --ghost='type to search...' \
    --pointer=' ' --scrollbar='' --multi $([[ "$2" == "all" ]] && echo --multi=1) \
    --prompt="[ ctx=$ctx ns=$namespace ] $res > " \
    --header=">> C-e (edit) || C-f (port-forward) || C-l (logs) || C-i (image) || C-o (describe) || C-p (preview) || C-r (reload) || C-s ($([[ "$res" == po* ]] && echo ssh || echo scale)) || C-x (delete) <<" \
    --preview-window=hidden,right,border-left \
    --bind="start:reload:$cmd" \
    --bind='enter:ignore' \
    --bind='ctrl-p:toggle-preview,ctrl-u:preview-half-page-up,ctrl-d:preview-half-page-down' \
    --bind="ctrl-r:reload:$cmd" \
    --bind="ctrl-m:execute:source $SCRIPT_FILE && __set_image__ $ctx $ns $res $name" \
    --bind="ctrl-o:execute-multi:kubectl --context $ctx describe $res $name -n $ns | ${EDITOR:-vim} - -c 'setlocal buftype=nofile'" \
    --bind="ctrl-y:execute-multi:kubectl --context $ctx get $res $name -n $ns -o yaml | ${EDITOR:-vim} - -c 'setlocal buftype=nofile | setlocal filetype=yaml'" \
    --bind="ctrl-e:execute-multi:kubectl --context $ctx edit $res $name -n $ns" \
    --bind="ctrl-x:execute-multi:cc='kubectl --context=$ctx -n=$ns delete $res $name' && echo \${cc} && echo -n \"Run the command above? (y/N): \" && read confirm && [[ \$confirm =~ ^[Yy]\$ ]] && eval \$cc" \
    --bind="ctrl-s:execute-multi:
      if [[ "$res" == po* ]]; then
        source $SCRIPT_FILE && __ssh_into__ $ctx $ns $res $name > /dev/tty
      else
        echo -n 'Enter the replicas: ' && read replicas && [[ \$replicas =~ ^[0-9]+\$ ]] && kubectl --context $ctx scale --replicas=\$replicas $res $name -n $ns
      fi
    " \
    --bind="ctrl-l:execute:kubectl --context $ctx logs $res/$name -n $ns -f && echo -n 'Press any key to continue:' && read" \
    --bind="ctrl-f:execute:echo -n 'Enter local:remote port (e.g., 8080:80): ' && read ports && kubectl --context $ctx port-forward $name -n $ns \$ports > /dev/tty" \
    --preview="kubectl --context $ctx describe $res $name -n $ns"
}

# Function to show resource types
__list_resource_types() {
  local cmd="kubectl api-resources --verbs=list -o wide | sort"
  local context="${context:-$(kubectl config current-context)}"
  local namespace="${namespace:-$(kubectl --context $context config view --minify --output 'jsonpath={..namespace}')}"
  local namespace="${namespace:-default}"

  fzf --layout=reverse --header-lines=1 --info='inline: | ' --ghost='type to search...' \
    --prompt="[ ctx=$(kubectl config current-context) ns=$namespace ] resources > " \
    --header=$'>> select Kubernetes resource type || CTRL-D (exit) <<\n\n' \
    --preview-window=hidden,right,border-left \
    --bind="start:reload:($cmd)" \
    --bind="ctrl-r:reload:($cmd)" \
    --bind='ctrl-p:toggle-preview,ctrl-u:preview-half-page-up,ctrl-d:preview-half-page-down' \
    --bind="enter:execute:(source $SCRIPT_FILE && __get_obj__ $context $namespace {1} \"get {1} -n $namespace -o wide\")" \
    --preview='kubectl explain {1}'
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

main() {
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "Error: kubectl is not installed or not in PATH"
    exit 1
  fi

  if ! command -v fzf >/dev/null 2>&1; then
    echo "Error: fzf is not installed or not in PATH"
    exit 1
  fi

  k "$@"
}

(
  [[ -n $ZSH_VERSION && $ZSH_EVAL_CONTEXT =~ :file$ ]] || 
  [[ -n $KSH_VERSION && "$(cd -- "$(dirname -- "$0")" && pwd -P)/$(basename -- "$0")" != "$(cd -- "$(dirname -- "${.sh.file}")" && pwd -P)/$(basename -- "${.sh.file}")" ]] || 
  [[ -n $BASH_VERSION ]] && (return 0 2>/dev/null)
) || main "$@"
