VENV              := .venv/bin
VENV_DTS          := .venv-dts/bin
DTS_VALIDATOR_SRC := .venv-dts/src/validator
SPEC              ?= api.yaml
BASE_URL          ?= http://localhost:8090/exist/restxq/ecocor
DTS_ENTRY         ?= $(BASE_URL)/dts
EXIST_REST        ?= http://localhost:8090/exist/rest/db/
EXIST_AUTH        ?= admin:
UNIT_TEST_DIR     := /db/apps/ecocor/unit-tests

# Run all checks (structural + drift + DTS conformance + unit tests).
test: validate schemathesis validate-dts xqsuite

# openapi-spec-validator: structural check of the OpenAPI file.
validate:
	$(VENV)/python -m openapi_spec_validator $(SPEC)

# schemathesis: spec-vs-server drift tests against the live API.
schemathesis: validate
	$(VENV)/schemathesis run $(SPEC) --url=$(BASE_URL) \
	  --checks=all --max-examples=20

# dts-validator: DTS v1.0 conformance of the /dts* endpoints.
# Lives in its own venv because it pins pytest <9 (schemathesis needs >=9).
# Installed as -e from the cloned repo so the validator finds its JSON schemas
# (the schemas are not included in the wheel — v0.2.3 packaging bug).
$(DTS_VALIDATOR_SRC):
	git clone --depth 1 https://github.com/distributed-text-services/validator.git $@
	/opt/homebrew/bin/python3 -m venv .venv-dts
	$(VENV_DTS)/pip install -q -e $(DTS_VALIDATOR_SRC)

validate-dts: $(DTS_VALIDATOR_SRC)
	$(VENV_DTS)/dts-validator $(DTS_VALIDATOR_SRC)/tests \
	  --entry-endpoint=$(DTS_ENTRY) \
	  --html=dts-report.html --self-contained-html

# xqsuite: run XQuery unit tests in-database. Tests live in
# unit-tests/*.xqm and are synced via the VS Code eXist-db extension
# (or packaged into the xar). This target discovers all test modules
# under $(UNIT_TEST_DIR) and runs them through xqsuite's test:suite.
xqsuite:
	@curl -sf -u $(EXIST_AUTH) --data-urlencode "_query=\
	  xquery version '3.1';\
	  import module namespace test = 'http://exist-db.org/xquery/xqsuite' \
	    at 'resource:org/exist/xquery/lib/xqsuite/xqsuite.xql';\
	  let \$$modules := xmldb:get-child-resources('$(UNIT_TEST_DIR)')[ends-with(., '.xqm')]\
	  return test:suite(\
	    for \$$m in \$$modules \
	    return inspect:module-functions( \
	      xs:anyURI('xmldb:exist://$(UNIT_TEST_DIR)/' || \$$m)))" \
	  $(EXIST_REST)

# openapi-generator: regenerate the ../pyecocor-base Python client (outer loop).
client:
	docker run --rm \
	  -v $$PWD:/spec \
	  -v $$PWD/../pyecocor-base:/out \
	  openapitools/openapi-generator-cli:v7.10.0 generate \
	    -i /spec/api.yaml -g python -o /out \
	    -p packageName=pyecocor_base \
	    -p packageVersion=0.0.1

.PHONY: test validate schemathesis validate-dts xqsuite client
