IMAGE ?= gks-ncbi:arm64
TARGET_PLATFORM ?= linux/arm64
NCBI_BUILD_JOBS ?= 8
NCBI_CXX_TOOLKIT_REF ?= fe8144adf21fc19db6b9c8c96aa623965419e8bd

.PHONY: preflight build test smoke

preflight:
	bash scripts/preflight.sh

build:
	docker buildx build --platform $(TARGET_PLATFORM) --load --progress=plain \
	  --build-arg NCBI_BUILD_JOBS=$(NCBI_BUILD_JOBS) \
	  --build-arg NCBI_CXX_TOOLKIT_REF=$(NCBI_CXX_TOOLKIT_REF) \
	  -t $(IMAGE) .

test:
	python3 -m unittest discover -s tests -p 'test_*.py'
	bash -n scripts/*.sh docker/*.sh

smoke:
	bash tests/smoke.sh
