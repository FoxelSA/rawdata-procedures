
#
#   make - enumeration
#

    SCRIPTS:=$(notdir $(wildcard src/*) )

#
#   make - synchronize
#

    all:directories
	@$(foreach SCRIPT, $(SCRIPTS), $(MAKE) -C src/$(SCRIPT) clean && $(MAKE) -C src/$(SCRIPT) all && cp src/$(SCRIPT)/bin/* bin/ && ) true

#
#   make - directories
#

    directories:
	mkdir -p bin

#
#   make - clean
#

    clean:
	rm bin/* -f
