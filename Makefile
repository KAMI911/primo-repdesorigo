# Repdeső Rigó -- Primo Z80 assembly project. Same targets locally and in CI.
#   make            universal .ptp (runtime colour/mono detect) + -bw / -col variants + WAVs
#   make test       tool tests, Z80 unit tests and the headless gameplay run in z88dk-ticks
#   make check      verify every .ptp (structure, CRCs, memory ceiling)
#   make shots      PNG screenshots of the headless run (needs Pillow) in build/shots/
NAME      ?= repdesorigo
MAX_END   ?= 0xC800          # image must stay below the second screen buffer
# Pinned by digest on purpose: reproducible, and a moved tag cannot change what CI runs.
Z88DK_IMG ?= z88dk/z88dk@sha256:2aab19402c1846858e5fb80b1bb7582af2a94375c41a592512a9bef4bc90719f

ifeq ($(shell command -v z88dk-z80asm 2>/dev/null),)
RUN = docker run --rm --user $(shell id -u):$(shell id -g) -v $(CURDIR):/src -w /src $(Z88DK_IMG)
endif
ASM   = $(RUN) z88dk-z80asm -b -mz80 -Isrc -m
PTP   = python3 -I tools/ptp.py
SRC   = $(wildcard src/*.asm src/*.inc)
VARIANTS = $(NAME) $(NAME)-bw $(NAME)-col

.PHONY: all test check size clean shots assets
all: $(addprefix build/,$(addsuffix .ptp,$(VARIANTS))) $(addprefix build/,$(addsuffix .wav,$(VARIANTS))) check size

assets: src/data.inc
src/data.inc: tools/gen_assets.py ; python3 -I tools/gen_assets.py $@

build/$(NAME).bin: $(SRC)             ; @mkdir -p build; $(ASM) -obuild/$(NAME).bin src/main.asm
build/$(NAME)-bw.bin: $(SRC)          ; @mkdir -p build; $(ASM) -DTARGET_BW -obuild/$(NAME)-bw.bin src/main.asm
build/$(NAME)-col.bin: $(SRC)       ; @mkdir -p build; $(ASM) -DTARGET_COLOR -obuild/$(NAME)-col.bin src/main.asm
build/%.ptp: build/%.bin              ; $(PTP) build --name "$*" build/$*.bin $@
build/%.wav: build/%.ptp              ; $(PTP) wav $< $@

test: src/data.inc | build
	python3 -I tests/test_ptp.py
	python3 -I tests/run_tests.py

shots: | build
	python3 -I tests/run_tests.py --shots build/shots

build: ; @mkdir -p build

check:
	@for f in build/*.ptp; do $(PTP) verify --max-end $(MAX_END) $$f || exit 1; done

size:
	@for f in build/$(NAME)*.bin; do printf "%-32s %6d bytes\n" $$f $$(wc -c < $$f); done

clean: ; rm -rf build
