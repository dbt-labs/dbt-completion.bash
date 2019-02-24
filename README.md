
## dbt-completion.bash

### What

This script adds autocompletion to the [dbt](https://www.getdbt.com/) CLI. Once installed, users can tab-complete model, tag, source, and package selectors to node selection flags like `--models` and `--exclude`. Need a refresher on resource selection? Check out [the docs](https://docs.getdbt.com/reference#run).

**Example usage (using the [redshift package](https://github.com/fishtown-analytics/redshift)):**
```
$ dbt run --model red<TAB>
redshift.*                                  redshift_admin_queries                      redshift_constraints
redshift.base.*                             redshift_admin_table_stats                  redshift_cost
redshift.introspection.*                    redshift_admin_users_schema_privileges      redshift_sort_dist_keys
redshift.views.*                            redshift_admin_users_table_view_privileges  redshift_tables
redshift_admin_dependencies                 redshift_columns
```


### Installation
This script can be installed by moving it to your home directory (as a dotfile), then sourcing it in your `~/.bash_profile` file.

```
curl https://raw.githubusercontent.com/fishtown-analytics/dbt-bash-autocomplete/master/dbt-completion.bash > ~/.dbt-completion.bash
echo 'source ~/.dbt-completion.bash' >> ~/.bash_profile
```

### Notes and caveats

- This script uses the manifest (assumed to be at `target/manifest.json`) to _quickly_ provide a list of existing selectors. As such, a dbt resource must be compiled before it will be available for tab completion. In the future, this script should use dbt directly to parse the project directory and generate possible selectors. Until then, brand new models/sources/tags/packages will not be displayed in the tab complete menu
- This script was tested on macOS using bash 4.4.23. It's very likely that this script will not work as expected on other operating systems or in other shells. If you're interested in helping make this script work on another platform, please open an issue!
