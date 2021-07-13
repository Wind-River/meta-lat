
OBJS = mttyexec

DEST=/usr/bin

all: $(OBJS)

clean:
	rm -f $(OBJS) *.o

%.o: %.c
	$(CC) $(CFLAGS) -Wall -c $<

mttyexec: mttyexec.o
	$(CC) $(LDFLAGS) -Wall -o $@ $^ -lutil

install: $(OBJS)
	install -d $(DEST)
	install -m 0755 mttyexec $(DEST)

