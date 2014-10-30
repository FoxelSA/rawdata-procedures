#
#   make - synchronize
#

    all:directories install
    
    install:
	cp -rv src/bin . 

    install-system-tools:
	${MAKE} -C src/system-tools install

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
