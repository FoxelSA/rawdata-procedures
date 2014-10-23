SYSTEM_PREFIX=/

#
#   make - synchronize
#

    all:directories
	cp -rv src/bin . 

    system-tools:
	${MAKE} -C src/system-tools install SYSTEM_PREFIX=${SYSTEM_PREFIX}

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
