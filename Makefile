
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
ifeq ($(whoami),root)
	@$(foreach SOFT, $(MAKE_SOFTS), cp $(MAKE_BINARY)/$(SOFT) /bin/ && ) true
else
    $(error Install target need root privilege - see makefile content)
endif

ifeq ($(whoami),root)
    uninstall:
	@$(foreach SOFT, $(MAKE_SOFTS), rm -f /bin/$(SOFT) && ) true
else
    $(error Uninstall target need root privilege - see makefile content)
endif
