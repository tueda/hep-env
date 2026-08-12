DOCKER_IMAGE_TAG = hep-env-local
DATA_DIR = .data
APPTAINER_IMAGE = $(DATA_DIR)/hep-env-local.sif
APPTAINER_IMAGE_STAMP = $(APPTAINER_IMAGE).docker-image-id
DOCKER_DATA = $(DATA_DIR)/docker
APPTAINER_DATA = $(DATA_DIR)/apptainer

.PHONY: update-docker update-apptainer run-docker run-apptainer

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

$(DOCKER_DATA): update-docker $(DATA_DIR)
	docker run --rm -v "$(PWD):/work" $(DOCKER_IMAGE_TAG) cp -r /data $(DOCKER_DATA)

$(APPTAINER_DATA): update-apptainer $(DATA_DIR)
	apptainer exec --bind "$(PWD):/work" $(APPTAINER_IMAGE) bash -c "cp -r /data $(APPTAINER_DATA)"

run-docker: update-docker $(DOCKER_DATA)
	docker run -it --rm -v "$(PWD):/work" -v "$(PWD)/$(DOCKER_DATA):/data" $(DOCKER_IMAGE_TAG)

run-apptainer: update-apptainer $(APPTAINER_DATA)
	apptainer shell --bind "$(PWD):/work" --bind "$(PWD)/$(APPTAINER_DATA):/data" $(APPTAINER_IMAGE)
