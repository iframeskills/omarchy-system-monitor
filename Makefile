.PHONY: test

# The same checks as CI: the manifest, the model tests and the sensor discovery fixtures.
test:
	jq empty manifest.json
	node --test tests/model.test.js
	bash tests/discovery.test.sh
