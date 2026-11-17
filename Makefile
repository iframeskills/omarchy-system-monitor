.PHONY: test

test:
	@if command -v jsv-file-length >/dev/null 2>&1; then jsv-file-length run . || true; else printf "%s\n" "warning: jsv-file-length is unavailable"; fi
	jq empty manifest.json
	node --test tests/model.test.js
	bash tests/no-comments.test.sh
	bash tests/discovery.test.sh
	bash tests/qml-smoke.test.sh
