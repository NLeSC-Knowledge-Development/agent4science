# Override on the command line, e.g. `make serve-docs ADDR=0.0.0.0:9000`
PROPERDOCS ?= uv run properdocs
CONFIG     ?= properdocs.yml
ADDR       ?= localhost:8000
SITE_DIR   ?= site

.DEFAULT_GOAL := help
.PHONY: help build-docs serve-docs deploy-docs clean

help:  ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build-docs:  ## Build the site into $(SITE_DIR)/
	$(PROPERDOCS) build -f $(CONFIG) -d $(SITE_DIR)

serve-docs:  ## Serve locally with live reload at $(ADDR)
	$(PROPERDOCS) serve -f $(CONFIG) -a $(ADDR)

deploy-docs:  ## Build and push to GitHub Pages (gh-pages branch)
	$(PROPERDOCS) gh-deploy -f $(CONFIG) --force

clean: 
	rm -rf $(SITE_DIR)
