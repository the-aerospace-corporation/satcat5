#########################################################################
# Copyright 2019 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
#########################################################################

CC=g++
CFLAGS=-Wall -Wextra -ggdb -O0

OBJ=main.o ethernet.o slip.o spi.o uart.o
EXC=pi_wire

all: pi_wire

$(EXC): $(OBJ)
	$(CC) -pthread -o $@ $^ $(CFLAGS)

%.o: %.cpp
	$(CC) -pthread -c -o $@ $< $(CFLAGS)

clean:
	rm -f *.o $(EXC)
