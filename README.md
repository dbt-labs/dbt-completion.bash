
## dbt-completion.bash

### What

This script adds autocompletion to the [dbt](https://www.getdbt.com/) CLI. Once installed, users can tab-complete model, tag, source, and package selectors to node selection flags like `--select` and `--exclude`. Need a refresher on resource selection? Check out [the docs](https://docs.getdbt.com/reference/node-selection/syntax).

**Example usage (using the [redshift package](https://github.com/dbt-labs/redshift)):**
```
$ dbt run --model red<TAB>
redshift.*                                  redshift_admin_queries                      redshift_constraints
redshift.base.*                             redshift_admin_table_stats                  redshift_cost
redshift.introspection.*                    redshift_admin_users_schema_privileges      redshift_sort_dist_keys
redshift.views.*                            redshift_admin_users_table_view_privileges  redshift_tables
redshift_admin_dependencies                 redshift_columns
```

### Installation (bash)
This script can be installed by moving it to your home directory (as a dotfile), then sourcing it in your `~/.bash_profile` file.

```
curl https://raw.githubusercontent.com/fishtown-analytics/dbt-completion.bash/master/dbt-completion.bash > ~/.dbt-completion.bash
echo 'source ~/.dbt-completion.bash' >> ~/.bash_profile
```

### Installation (bash script on zsh)
The z shell requires a bit more work, you'll also want to automatically load `compinit` and `bashcompinit` if they are not already loaded.

This makes use of zsh's ability to import bash completion scripts and use them, as long as they're script-compatible.

```
curl https://raw.githubusercontent.com/fishtown-analytics/dbt-completion.bash/master/dbt-completion.bash > ~/.dbt-completion.bash
echo 'autoload -U +X compinit && compinit' >> ~/.zshrc
echo 'autoload -U +X bashcompinit && bashcompinit' >> ~/.zshrc
echo 'source ~/.dbt-completion.bash' >> ~/.zshrc
```

### Installation (zsh-only script, with more features)

#### Using oh-my-zsh

If using oh-my-zsh, the autocompletion script can be installed by putting the `_dbt` file in the folder `~/.oh-my-zsh/completions/` (create the completions folder if it doesn't exist).

#### Manual installation

If installing manually, instructions from [zsh-completions](https://github.com/zsh-users/zsh-completions) mention that you need to include the directory where `_dbt` is stored in your `$fpath` by adding the following to `~/.zshrc`
```
fpath=(path/to/_dbt/parent_directory $fpath)
```
And you may need to rebuild the zsh completion cache by running this in your terminal:
```
rm -f ~/.zcompdump; compinit
```
In many Linux distributions, the `zsh` package includes `/usr/local/share/zsh/site-functions` in its `fpath`, so simply copying `_dbt` in that directory should work.

### Bash Completion

In bash, the `:` character counts as a word separator, which causes this completion script to incorrectly handle selectors like `tag:...` and `source:...`. To make the script work with these characters, install the `bash-completion` program, then re-source the `dbt-completion.bash` script.

**macOS**
```
$ brew install bash-completion
```


### Notes and caveats

This script uses the manifest to _quickly_ provide a list of existing selectors. As such, a dbt resource must be compiled before it will be available for tab completion. In the future, this script should use dbt directly to parse the project directory and generate possible selectors. Until then, brand new models/sources/tags/packages will not be displayed in the tab complete menu.

By default the location of your `manifest.json` file is assumed to be at `target/manifest.json`. To change that you can specify the full path to the location of your `manifest.json` file in the environment variable `DBT_MANIFEST_PATH`. For example:

```shell
export DBT_MANIFEST_PATH=/tmp/dbt/target/manifest.json
```

This script was tested on macOS using bash 4.4.23. It's very likely that this script will not work as expected on other operating systems or in other shells. If you're interested in helping make this script work on another platform, please open an issue!

On zsh, when you want to use the `project.folder.*` notation, you may have to prefix with a quote, as otherwise you'll get autocompleted to something like `dbt compile -m project.folder.*`, and zsh will try to glob, find no matches, and throw an error.
