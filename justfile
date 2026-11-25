# Install `just` using the command: `uv tool install rust-just`
# More info check https://just.systems/man/en/introduction.html

# Override on the command line, e.g. `just addr=0.0.0.0:9000 serve-docs`
properdocs := "uv run --group docs properdocs"
config     := "properdocs.yml"
addr       := "localhost:8000"
site_dir   := "site"

# Show available recipes
default:
    @just --list --unsorted

# Build the site into the site directory
build-docs:
    {{properdocs}} build -f {{config}} -d {{site_dir}}

# Serve locally with live reload
serve-docs:
    {{properdocs}} serve -f {{config}} -a {{addr}}

# Build and push to GitHub Pages (gh-pages branch)
deploy-docs:
    {{properdocs}} gh-deploy -f {{config}} --force

# Remove the built artifacts
clean:
    rm -rf {{site_dir}}
