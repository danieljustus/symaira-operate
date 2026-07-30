BINARY := symoperate

.PHONY: build release test lint coverage run doctor serve clean

build:
	swift build

release:
	swift build -c release

test:
	swift test

coverage:
	swift test --enable-code-coverage --filter SymOperateCoreTests || true
	PROFRAW_DIR=$$(find .build -type d -name codecov | head -1); \
	if [ -n "$$PROFRAW_DIR" ]; then \
	  llvm-profdata merge -sparse -o .build/coverage.profdata "$$PROFRAW_DIR"/*.profraw 2>/dev/null || \
	    xcrun llvm-profdata merge -sparse -o .build/coverage.profdata "$$PROFRAW_DIR"/*.profraw; \
	  BINARY="$$(find .build -name "SymOperateCore.o" -type f | head -1)"; \
	  if [ -n "$$BINARY" ] && [ -f .build/coverage.profdata ]; then \
	    xcrun llvm-cov report \
	      "$$BINARY" \
	      --instr-profile=.build/coverage.profdata \
	      --use-color=false \
	      Sources/SymOperateCore/ > .build/coverage-report.txt; \
	    TOTAL=$$(tail -1 .build/coverage-report.txt | awk '{print $$10}' | sed 's/%//'); \
	    printf '{"coverage": %.1f, "generated_at": "%s"}\n' "$$TOTAL" "$$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .build/coverage.json; \
	  fi; \
	fi

lint:
	@command -v swiftlint >/dev/null 2>&1 && swiftlint --quiet || echo "swiftlint not installed; skipping"

run: build
	swift run -q $(BINARY) doctor

doctor: build
	swift run -q $(BINARY) doctor

serve: build
	swift run -q $(BINARY) serve

clean:
	swift package clean
	rm -rf .build
