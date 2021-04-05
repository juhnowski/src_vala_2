bin_PROGRAMS = orbita

orbita_SOURCES = \
	orbita.vala \
	orbita-app.vala

INCLUDES = \
	-include config.h \
	$(ORBITA_CFLAGS) \
	-DLOCALEDIR=\""$(localedir)"\" \
	-DPKGDATADIR=\""$(pkgdatadir)"\" \
	-DPKGLIBDIR=\""$(pkglibdir)"\"

VALAFLAGS = \
	--vapidir=$(srcdir)/../vapi --pkg config \
	@ORBITA_PACKAGES@

orbita_LDADD = \
	$(ORBITA_LIBS)
