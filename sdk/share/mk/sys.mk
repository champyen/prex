.SUFFIXES: .out .a .ln .o .c .cc .C .cpp .p .f .F .r .y .l .s .S .cl .p .h .sh .m4
.c.o:
	$(CC) $(CFLAGS) $(CPPFLAGS) -c -o $@ $<

