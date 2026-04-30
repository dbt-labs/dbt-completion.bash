# dbt.fish - tab completion for dbt (dbt Core and Fusion) and dbtf (Fusion alias)
#
# Supports both dbt Core (Click) and Fusion (clap_complete). The appropriate
# completion script is generated once and cached by binary mtime, so it only
# regenerates when the binary changes.
#
# Model/selector completions (-s/--select, --exclude, etc.) are sourced from
# target/manifest.json and work the same for both dbt Core and Fusion.
#
# INSTALLATION
#   Copy dbt.fish to your fish completions directory:
#     cp dbt.fish ~/.config/fish/completions/dbt.fish
#
# CREDITS
#   https://github.com/dbt-labs/dbt-completion.bash


# --- Project root and manifest helpers ---

function __dbt_get_project_root
    if set -q DBT_PROJECT_DIR
        echo $DBT_PROJECT_DIR
        return
    end
    set -l dir $PWD
    while test $dir != /
        if test -f $dir/dbt_project.yml
            echo $dir
            return
        end
        set dir (dirname $dir)
    end
end

function __dbt_list_models
    set -l manifest
    if set -q DBT_MANIFEST_PATH
        set manifest $DBT_MANIFEST_PATH
    else
        set -l root (__dbt_get_project_root)
        test -n "$root" || return
        set manifest $root/target/manifest.json
    end
    test -f $manifest || return

    # If the current token starts with "-" we're still on the flag itself, not its argument.
    set -l cur (commandline -ct)
    string match -qr -- '^-' $cur && return

    # Parse comma-separated and +/@ prefixes from the current token.
    set -l comma_prefix ""
    set -l node_prefix ""
    if string match -qr -- ',' $cur
        set comma_prefix (string replace -r -- '[^,]*$' '' $cur)
        set cur (string replace -r -- '^.*,' '' $cur)
    end
    if string match -qr -- '^[+@]' $cur
        set node_prefix (string sub -l 1 $cur)
    end

    # Cache the base model list next to the manifest (in target/) so it is
    # project-scoped and cleaned up by `dbt clean`. Invalidated by manifest mtime.
    set -l models_cache (path dirname $manifest)/.dbt_completion_cache.txt
    set -l models_key_cache (path dirname $manifest)/.dbt_completion_cache.key
    set -l manifest_key (stat -f %m $manifest 2>/dev/null; or stat -c %Y $manifest 2>/dev/null)

    if not test -f $models_cache; or test (cat $models_key_cache 2>/dev/null) != $manifest_key
        python3 -c '
import json, sys
try:
    manifest = json.load(open(sys.argv[1]))
    results = set()
    for node in manifest.get("nodes", {}).values():
        if node.get("resource_type") in ("model", "seed"):
            results.add(node["name"])
    for node in manifest.get("sources", {}).values():
        results.add("source:" + node["source_name"])
        results.add("source:" + node["source_name"] + "." + node["name"])
    for node in manifest.get("exposures", {}).values():
        results.add("exposure:" + node["name"])
    for node in manifest.get("metrics", {}).values():
        results.add("metric:" + node["name"])
    print("\n".join(sorted(results)))
except:
    pass
' $manifest > $models_cache
        echo $manifest_key > $models_key_cache
    end

    # Apply prefix to cached results and print
    if test -n "$comma_prefix$node_prefix"
        string replace -r -- '^' "$comma_prefix$node_prefix" < $models_cache
    else
        cat $models_cache
    end
end

function __dbt_list_yaml_selectors
    set -l manifest
    if set -q DBT_MANIFEST_PATH
        set manifest $DBT_MANIFEST_PATH
    else
        set -l root (__dbt_get_project_root)
        test -n "$root" || return
        set manifest $root/target/manifest.json
    end
    test -f $manifest || return

    python3 -c "
import json
try:
    manifest = json.load(open('$manifest'))
    print('\n'.join(manifest.get('selectors', {}).keys()))
except:
    pass
"
end



# --- Binary detection and completion caching ---

function __dbt_setup_completions
    set -l cmd $argv[1]
    set -l bin_path $argv[2]
    test -x "$bin_path" || return

    set -l cache_dir (if set -q XDG_CACHE_HOME; echo $XDG_CACHE_HOME; else; echo $HOME/.cache; end)
    set -l script_cache $cache_dir/dbt_{$cmd}_completions.fish
    set -l key_cache $cache_dir/dbt_{$cmd}_completions.key
    set -l current_key "$bin_path:"(stat -f %m $bin_path 2>/dev/null; or stat -c %Y $bin_path 2>/dev/null)

    if not test -f $script_cache; or test (cat $key_cache 2>/dev/null) != $current_key
        mkdir -p $cache_dir
        set -l first_line ($bin_path --help 2>/dev/null | head -1)
        if string match -q '*dbt-fusion*' $first_line
            $bin_path completions fish 2>/dev/null \
                | sed "s/__fish_dbt_/__fish_{$cmd}_/g; s/complete -c dbt /complete -c $cmd /g" \
                > $script_cache
        else
            env _DBT_COMPLETE=fish_source $bin_path 2>/dev/null \
                | sed "s/complete -c dbt /complete -c $cmd /g" \
                > $script_cache
        end
        echo $current_key > $key_cache
    end

    test -f $script_cache && source $script_cache
end


# --- Set up completions for dbt ---

if set -l dbt_bin (command -v dbt)
    __dbt_setup_completions dbt $dbt_bin
end


# --- Set up completions for dbtf (Fusion alias created by installer) ---
# The installer adds: alias dbtf=/path/to/dbt
# In fish this becomes a function whose body contains the binary path.

if functions -q dbtf
    set -l dbtf_bin (functions dbtf | string match -rg '^\s+(/\S+)\s+\$argv')
    if test -n "$dbtf_bin" -a -x "$dbtf_bin"
        __dbt_setup_completions dbtf $dbtf_bin
    end
end


# --- Manifest-based model/selector completions (applies to both dbt and dbtf) ---
# Add model completions directly to the selector flags so fish associates them
# with the flag argument rather than relying on a separate condition check.

for __dbt_cmd in dbt dbtf
    complete -c $__dbt_cmd -f -s s -l select -r -a '(__dbt_list_models)'
    complete -c $__dbt_cmd -f -l exclude -r -a '(__dbt_list_models)'
    complete -c $__dbt_cmd -f -s m -l model -l models -r -a '(__dbt_list_models)'
    complete -c $__dbt_cmd -f -l selector -r -a '(__dbt_list_yaml_selectors)'
end
