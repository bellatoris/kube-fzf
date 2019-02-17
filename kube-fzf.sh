#!/usr/bin/env bash

_kube_fzf_usage() {
  local func=$1
  echo -e "\nUSAGE:\n"
  case $func in
    findpod)
      echo -e "findpod [-a | -n <namespace-query>] [pod-query]\n"
      ;;
    tailpod)
      echo -e "tailpod [-a | -n <namespace-query>] [pod-query]\n"
      ;;
    execpod)
      echo -e "execpod [-a | -n <namespace-query>] [pod-query] <command>\n"
      ;;
    describepod)
      echo -e "describepod [-a | -n <namespace-query>] [pod-query]\n"
      ;;
  esac
  cat << EOF
-a                    -  Search in all namespaces
-n <namespace-query>  -  Find namespaces matching <namespace-query> and do fzf.
                         If there is only one match then it is selected automatically.
-h                    -  Show help
EOF
}

_kube_fzf_handler() {
  local opt namespace_query pod_query cmd
  local OPTIND=1
  local func=$1

  shift $((OPTIND))

  while getopts ":hn:a" opt; do
    case $opt in
      h)
        _kube_fzf_usage "$func"
        return 1
        ;;
      n)
        namespace_query="$OPTARG"
        ;;
      a)
        namespace_query="--all-namespaces"
        ;;
      \?)
        echo "Invalid Option: -$OPTARG."
        _kube_fzf_usage "$func"
        return 1
        ;;
      :)
        echo "Option -$OPTARG requires an argument."
        _kube_fzf_usage "$func"
        return 1
        ;;
    esac
  done

  shift $((OPTIND - 1))

  if [ "$func" = "execpod" ]; then
    if [ $# -eq 1 ]; then
      cmd=$1
      [ -z "$cmd" ] && cmd="sh"
    elif [ $# -eq 2 ]; then
      pod_query=$1
      cmd=$2
      [ -z "$cmd" ] && echo "Command required." && _kube_fzf_usage "$func" && return 1
    else
      [ -z "$cmd" ] && cmd="sh"
    fi
  else
    pod_query=$1
  fi

  args="$namespace_query|$pod_query|$cmd"
}

_kube_fzf_fzf_args() {
  local search_query=$1
  local extra_args=$2
  local fzf_args="--height=30 --ansi --reverse $extra_args"
  [ -n "$search_query" ] && fzf_args="$fzf_args --query=$search_query"
  echo "$fzf_args"
}

_kube_fzf_search_pod() {
  local namespace pod_name
  local namespace_query=$1
  local pod_query=$2
  local pod_fzf_args=$(_kube_fzf_fzf_args "$pod_query")

  if [ -z "$namespace_query" ]; then
      context=$(kubectl config current-context)
      namespace=$(kubectl config get-contexts --no-headers $context \
        | awk '{ print $5 }')

      namespace=${namespace:=default}
      pod_name=$(kubectl get pod --namespace=$namespace --no-headers \
          | fzf $(echo $pod_fzf_args) \
        | awk '{ print $1 }')
  elif [ "$namespace_query" = "--all-namespaces" ]; then
    read namespace pod_name <<< $(kubectl get pod --all-namespaces --no-headers \
        | fzf $(echo $pod_fzf_args) \
      | awk '{ print $1, $2 }')
  else
    local namespace_fzf_args=$(_kube_fzf_fzf_args "$namespace_query" "--select-1")
    namespace=$(kubectl get namespaces --no-headers \
        | fzf $(echo $namespace_fzf_args) \
      | awk '{ print $1 }')

    namespace=${namespace:=default}
    pod_name=$(kubectl get pod --namespace=$namespace --no-headers \
        | fzf $(echo $pod_fzf_args) --preview "echo {} | cut -d ' ' -f 1 - | xargs kubectl -n $namespace describe pods" \
      | awk '{ print $1 }')
  fi

  [ -z "$pod_name" ] && echo "No pods found, namespace: $namespace" && return 1

  echo "$namespace|$pod_name"
}

_kube_fzf_echo() {
  local reset_color="\033[0m"
  local bold_green="\033[1;32m"
  local message=$1
  echo -e "\n$bold_green $message $reset_color\n"
}

_kube_fzf_teardown() {
  unset args
  echo $1
}
