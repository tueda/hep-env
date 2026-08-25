DOCKER_IMAGE_TAG = hep-env-local

# Configurable directory paths must be absolute, contain neither whitespace
# nor Make/shell metacharacters, and must not end with a slash.
WORK_DIR = $(CURDIR)
DATA_DIR = $(WORK_DIR)/.data
DOCKER_DATA_DIR = $(DATA_DIR)/docker
APPTAINER_DATA_DIR = $(DATA_DIR)/apptainer

# Derived paths.
APPTAINER_IMAGE = $(DATA_DIR)/hep-env-local.sif
APPTAINER_IMAGE_STAMP = $(APPTAINER_IMAGE).docker-image-id
DOCKER_DATA_STAMP = $(DOCKER_DATA_DIR)/.hep-env-initialized
APPTAINER_DATA_STAMP = $(APPTAINER_DATA_DIR)/.hep-env-initialized

.PHONY: update-docker update-apptainer \
	run-docker run-docker-no-bind run-apptainer

update-docker:
	docker build --progress=plain -t $(DOCKER_IMAGE_TAG) .

update-apptainer: update-docker $(DATA_DIR)
	$(_check_docker_image) || $(_build_apptainer_image)

_check_docker_image = { \
	[ -f $(APPTAINER_IMAGE) ] && [ -f $(APPTAINER_IMAGE_STAMP) ] && { \
	old_id=$$(cat $(APPTAINER_IMAGE_STAMP)); \
	current_id=$$(docker image inspect --format '{{.Id}}' $(DOCKER_IMAGE_TAG)); \
	[ "$$old_id" = "$$current_id" ]; \
	}; \
	}

_build_apptainer_image = { \
	docker image inspect --format '{{.Id}}' $(DOCKER_IMAGE_TAG) >$(APPTAINER_IMAGE_STAMP).tmp$$$$ \
	&& apptainer build --force $(APPTAINER_IMAGE) docker-daemon://$(DOCKER_IMAGE_TAG):latest \
	&& mv $(APPTAINER_IMAGE_STAMP).tmp$$$$ $(APPTAINER_IMAGE_STAMP); \
	}

$(DATA_DIR):
	mkdir -p $(DATA_DIR)
	echo '*' >$(DATA_DIR)/.gitignore

$(DOCKER_DATA_STAMP): | update-docker $(DATA_DIR)
	@if [ -e $(DOCKER_DATA_DIR) ] || [ -L $(DOCKER_DATA_DIR) ]; then \
		echo "$(DOCKER_DATA_DIR) exists without an initialization stamp" >&2; \
		exit 1; \
	fi
	mkdir -p $(dir $(DOCKER_DATA_DIR))
	docker run --rm \
		-v $(dir $(DOCKER_DATA_DIR)):/work \
		$(DOCKER_IMAGE_TAG) \
		sh -c 'cp -r /data /work/$(notdir $(DOCKER_DATA_DIR)) \
		&& touch /work/$(notdir $(DOCKER_DATA_DIR))/$(notdir $@)'

$(APPTAINER_DATA_STAMP): | update-apptainer $(DATA_DIR)
	@if [ -e $(APPTAINER_DATA_DIR) ] || [ -L $(APPTAINER_DATA_DIR) ]; then \
		echo "$(APPTAINER_DATA_DIR) exists without an initialization stamp" >&2; \
		exit 1; \
	fi
	mkdir -p $(dir $(APPTAINER_DATA_DIR))
	apptainer exec \
		--bind $(dir $(APPTAINER_DATA_DIR)):/work \
		$(APPTAINER_IMAGE) \
		cp -r /data /work/$(notdir $(APPTAINER_DATA_DIR))
	@touch $@

run-docker: update-docker $(DOCKER_DATA_STAMP)
	docker run -it --rm \
		-v $(WORK_DIR):/work \
		-v $(DOCKER_DATA_DIR):/data \
		$(DOCKER_IMAGE_TAG)

run-docker-no-bind: update-docker
	docker run -it --rm $(DOCKER_IMAGE_TAG)

run-apptainer: update-apptainer $(APPTAINER_DATA_STAMP)
	apptainer shell \
		--bind $(WORK_DIR):/work \
		--bind $(APPTAINER_DATA_DIR):/data \
		$(APPTAINER_IMAGE)
