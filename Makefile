VERSION          ?= v1
ARCH             ?= amd64
AWS_REGION       ?= eu-central-1
AMI_NAME         ?= linux-troubleshooting-lab-$(VERSION)
PACKER_TEMPLATE  ?= ubuntu-2404.pkr.hcl
PACKER_DIR       ?= packer
ARTIFACT_DIR     ?= artifacts/$(VERSION)
TF_DIR           ?= terraform
TF_VARS_FILE     ?= $(TF_DIR)/terraform.tfvars           # optional, keep gitignored
TF_AMI_TFVARS    ?= $(TF_DIR)/ami.auto.tfvars            # auto-written (AMI id only)

# Help text: run `make help`
.PHONY: help
help:
	@echo "Targets:"
	@echo "  artifacts        Build local artifacts into $(ARTIFACT_DIR)"
	@echo "  packer-init      Run 'packer init' for HCL2 plugins"
	@echo "  packer-validate  Validate Packer template"
	@echo "  packer-build     Build AMI, then write AMI id to $(TF_AMI_TFVARS)"
	@echo "  tf-init          terraform init"
	@echo "  tf-validate      terraform validate"
	@echo "  tf-apply         terraform apply (auto-loads terraform.tfvars if present)"
	@echo "  tf-apply-file    terraform apply -var-file=$(TF_VARS_FILE)"
	@echo "  tf-output        terraform output"
	@echo "  tf-destroy       terraform destroy (uses $(TF_VARS_FILE) if present)"
	@echo "  up               artifacts -> packer-build -> tf-init -> tf-apply"
	@echo "  clean            remove .terraform & local tfstate (keeps AMIs)"
	@echo "  deep-clean       clean + remove packer cache and manifest"
	@echo ""
	@echo "Variables:"
	@echo "  VERSION=$(VERSION)  ARCH=$(ARCH)  AWS_REGION=$(AWS_REGION)  AMI_NAME=$(AMI_NAME)"

# ----- Artifacts -----
.PHONY: artifacts
artifacts:
	./tools/build-go.sh $(VERSION) $(ARCH)
	./tools/build-rust.sh $(VERSION) $(ARCH)

# ----- Packer -----
.PHONY: packer-init
packer-init:
	cd $(PACKER_DIR) && packer init .

.PHONY: packer-validate
packer-validate:
	cd $(PACKER_DIR) && packer validate \
	  -var "region=$(AWS_REGION)" \
	  -var "artifact_version=$(VERSION)" \
	  -var "ami_name=$(AMI_NAME)" \
	  $(PACKER_TEMPLATE)

# Build AMI and capture the AMI ID from packer/manifest.json
.PHONY: packer-build
packer-build: artifacts packer-init
	cd $(PACKER_DIR) && packer build \
	  -var "region=$(AWS_REGION)" \
	  -var "artifact_version=$(VERSION)" \
	  -var "ami_name=$(AMI_NAME)" \
	  $(PACKER_TEMPLATE)
	@# Write the last AMI ID from the Packer manifest to terraform/ami.auto.tfvars
	@if [ -f "$(PACKER_DIR)/manifest.json" ]; then \
	  AMI_ID=$$(grep -o '"artifact_id": *"[^"]*"' $(PACKER_DIR)/manifest.json | tail -1 | sed -E 's/.*"artifact_id": *"[^:]*:(ami-[a-zA-Z0-9]+)".*/\1/'); \
	  if [ -n "$$AMI_ID" ]; then \
	    echo 'ami_id = "'$$AMI_ID'"' > $(TF_AMI_TFVARS); \
	    echo "[*] Wrote AMI to $(TF_AMI_TFVARS): $$AMI_ID"; \
	  else \
	    echo "[!] Could not parse AMI ID from $(PACKER_DIR)/manifest.json"; exit 1; \
	  fi \
	else \
	  echo "[!] Missing $(PACKER_DIR)/manifest.json. Add a Packer manifest post-processor."; \
	  exit 1; \
	fi

# ----- Terraform -----
.PHONY: tf-init
tf-init:
	cd $(TF_DIR) && terraform init

.PHONY: tf-validate
tf-validate:
	cd $(TF_DIR) && terraform validate

.PHONY: tf-apply
tf-apply: tf-init
	cd $(TF_DIR) && terraform apply

# Use your private tfvars file explicitly (kept out of git)
.PHONY: tf-apply-file
tf-apply-file: tf-init
	cd $(TF_DIR) && terraform apply -var-file="$(TF_VARS_FILE)"

.PHONY: tf-output
tf-output:
	cd $(TF_DIR) && terraform output

.PHONY: tf-destroy
tf-destroy:
	@if [ -f "$(TF_VARS_FILE)" ]; then \
	  cd $(TF_DIR) && terraform destroy -var-file="$(TF_VARS_FILE)"; \
	else \
	  cd $(TF_DIR) && terraform destroy; \
	fi

# One-shot: build artifacts -> bake AMI -> write ami.auto.tfvars -> init/apply
.PHONY: up
up: packer-build tf-apply

# ----- Cleaning -----
.PHONY: clean
clean:
	rm -rf $(TF_DIR)/.terraform $(TF_DIR)/terraform.tfstate* $(TF_DIR)/*.backup

.PHONY: deep-clean
deep-clean: clean
	rm -rf $(PACKER_DIR)/packer_cache $(PACKER_DIR)/manifest.json
