#/usr/bin/env bash

_parse_manifest() {
manifest_path=$1
prefix=$2
prog=$(cat <<EOF
try:
    import fileinput, json, sys
    prefix = sys.argv.pop() if len(sys.argv) == 2 else ""

    manifest = json.loads("\n".join([line for line in fileinput.input()]))
    models = set(
        "{}{}".format(prefix, node['name'])
        for node in manifest['nodes'].values()
        if node['resource_type'] in ['model', 'seed']
    )
    tags = set(
        "{}tag:{}".format(prefix, tag)
        for node in manifest['nodes'].values()
        for tag in node.get('tags', [])
        if node['resource_type'] == 'model'
    )
    sources = set(
        "{}source:{}".format(prefix, source)
        for node in manifest['nodes'].values()
        if node['resource_type'] == 'source'
    )
    fqns = set(
        "{}{}.*".format(prefix, ".".join(node['fqn'][:i-1]))
        for node in manifest['nodes'].values()
        for i in range(len(node['fqn']))
        if node['resource_type'] == 'model'
    )
    selectors = [
        selector
        for selector in (models | tags | sources | fqns)
        if selector and selector != ''
    ]
    print("\n".join(selectors))
except:
    pass
EOF
)

cat $manifest_path | python -c "$prog" $prefix
}

_get_last_flag() {
    arg_index=$1
    shift
    arg_list=("$@")

    # iterate backwards from index
    # if the first flag we find is a selector
    #   (-m, --models, --exclude, etc)
    # then we are in resource selection
    first_flag=""
    for i in $(seq $arg_index 0); do
        arg=${arg_list[$i]}
        if [[ $arg == -* ]] ; then
            first_flag=$arg
            break
        fi
    done

    echo $first_flag
}

_flag_is_selector() {
    flag=$1

    if [[ $flag == '-m' ]] || \
       [[ $flag == --model* ]] || \
       [[ $flag ==  '--exclude' ]] ;
    then
        echo 0
    else
        echo 1
    fi
}

_get_arg_prefix() {
    arg=$1
    first_char=${arg:0:1}
    if [[ $first_char == '+' ]] || [[ $first_char == '@' ]] ; then
        echo "$first_char"
    else
        echo ""
    fi
}

_get_project_root() {
  slashes=${PWD//[^\/]/}
  directory="$PWD"
  for (( n=${#slashes}; n>0; --n ))
  do
    test -e "$directory/dbt_project.yml" && echo "$directory/dbt_project.yml" && return
    directory="$directory/.."
  done
}

_complete_it() {
    last_flag=$(_get_last_flag $COMP_CWORD "${COMP_WORDS[@]}")
    is_selector=$(_flag_is_selector $last_flag)
    if [[ $is_selector == 0 ]] ; then
        current_arg="${COMP_WORDS[$COMP_CWORD]}"
        prefix=$(_get_arg_prefix $current_arg)
        project_file=$(_get_project_root)
        project_dir=$(dirname $project_file)
        manifest_path="${project_dir}/target/manifest.json"
        models=$(_parse_manifest $manifest_path $prefix)
        if [[ $current_arg == -* ]]; then
            COMPREPLY=($(compgen -W "$models" ""))
        else
            COMPREPLY=($(compgen -W "$models" "$current_arg"))
        fi
    fi
}

complete -F _complete_it dbt
