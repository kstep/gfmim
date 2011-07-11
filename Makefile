
gfmim: gfmim.vala
	valac --pkg gtk+-2.0 --pkg gmodule-2.0 --pkg posix $^

clean:
	rm -f gfmim gfmim.c

.DEFAULT: gfmim
.PHONY: clean
