-include .env
export

.PHONY: all build test reset-submodules clean-yarn

all: yarn.lock build test

# ensures yarn install was run before tests
yarn.lock: node_modules package.json
	$(MAKE clean-yarn)
	yarn install

# formats and builds the project
build:
	@forge fmt
	@forge build

# runs all forge tests except live integration tests
test: build yarn.lock
	@forge test -vv --no-match-test "Live"

# runs all forge tests including live integration tests
test-full: build yarn.lock
	@forge test -vv

gas-report: build yarn.lock
	@forge test  --no-match-test "Live" --gas-report

# resets all submodules to their latest commit and discards any local 
# changes
reset-submodules:
	@git submodule deinit -f . 
	@git submodule update --init

node_modules:
	mkdir -p $@

# clean js files
clean-yarn:
	rm -fr node_modules yarn.lock
