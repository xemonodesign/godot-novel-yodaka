GODOT ?= godot
PYTHON = .venv/bin/python

.PHONY: install lint test format run import web serve
install:
	python3 -m venv .venv
	.venv/bin/pip install -r requirements-dev.txt
import:
	$(PYTHON) src/tools/import_scenario.py
lint:
	.venv/bin/ruff check src/tools tests/test_scenario.py
	$(GODOT) --headless --path . --editor --import --quit
format:
	.venv/bin/black src/tools tests/test_scenario.py
test:
	$(PYTHON) -m pytest --cov=src/tools --cov-fail-under=80 -q
	$(GODOT) --headless --path . --script tests/test_runtime.gd
run:
	$(GODOT) --path .
web:
	mkdir -p build/web
	touch build/.gdignore
	$(GODOT) --headless --path . --editor --import --quit
	$(GODOT) --headless --path . --export-release Web build/web/index.html
	cp src/assets/OFL-NotoSansJP.txt build/web/
	touch build/web/.nojekyll
serve:
	$(PYTHON) -m http.server 8060 --directory build/web
