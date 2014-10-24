
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
ifeq ($(shell whoami),root)
	cp $(addprefix bin/,$(SCRIPTS)) /bin 2>/dev/null || :
else
    $(error Install target need root privilege - see makefile content)
endif

    uninstall:
ifeq ($(shell whoami),root)
	@$(foreach SCRIPT, $(SCRIPTS), rm -f /bin/$(SCRIPT) && ) true
else
    $(error Uninstall target need root privilege - see makefile content)
endif
