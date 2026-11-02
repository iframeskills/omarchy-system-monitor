.PHONY: test

test:
	jq empty manifest.json
	node --test tests/model.test.js
	bash tests/discovery.test.sh
