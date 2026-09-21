BUILDER_IMAGE ?= linux-troubleshooting-lab-jslinux-builder
PORT ?= 8000

.PHONY: all image builder serve clean clean-system-output clean-database-output

all: image

builder:
	docker build --tag $(BUILDER_IMAGE) --file docker/Dockerfile .

image: builder
	docker run --rm \
		--user "$$(id -u):$$(id -g)" \
		--env HOME=/tmp/home \
		--volume "$$(pwd):/workspace" \
		$(BUILDER_IMAGE) \
		bash scripts/build-in-container.sh

serve:
	./scripts/serve.sh $(PORT)

clean:
	rm -rf build dist

clean-system-output:
	rm -rf build/buildroot-output-x86_64-musl

clean-database-output:
	rm -rf build/buildroot-output-x86_64-musl-database
