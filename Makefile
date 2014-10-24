
#
#   make - enumeration
#

    SCRIPTS:=$(notdir $(wildcard src/*) )

#
#   make - synchronize
#

    all:directories
	@$(foreach SCRIPT, $(SCRIPTS), $(MAKE) -C src/$(SCRIPT) clean && $(MAKE) -C src/$(SCRIPT) all && cp src/$(SCRIPT)/bin/* bin/ || ) true

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

#
#   make - implementation
#

    install:
	cp $(addprefix bin/,$(SCRIPTS)) /bin 2>/dev/null || :

    uninstall:
	@$(foreach SCRIPT, $(SCRIPTS), rm -f /bin/$(SCRIPT) && ) true

