
gfmim: gfmim.vala
	valac --pkg gtk+-2.0 --pkg gmodule-2.0 $^

.DEFAULT: gfmim
