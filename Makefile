# Default values for variables exported to subpackages

export builddir ?= $(CURDIR)/build
export cachedir ?= $(builddir)/cache
export depdir ?= $(builddir)/dependencies

export prefix ?= $(builddir)
export datadir ?= $(prefix)/share
export agdadir ?= $(datadir)/agda

# Try to guess the stdlib location

export stdlibdir ?= $(firstword $(wildcard \
  $(datadir)/agda-stdlib \
  /usr/local/share/agda-stdlib /usr/local/lib/agda-stdlib \
  /usr/share/agda-stdlib /usr/lib/agda-stdlib ))

# Default values for local variables

pkgid ?= $(notdir $(CURDIR))
tmpdir ?= $(builddir)/tmp/$(pkgid)
docdir ?= $(datadir)/doc/$(pkgid)
htmldir ?= $(docdir)/html

srcdir ?= $(CURDIR)/src
srcfiles ?= $(filter-out %\#,$(filter-out %~,$(call findfiles,$(srcdir))))
agdafiles ?= $(patsubst $(srcdir)/%,$(agdadir)/%,$(filter %.agda,$(srcfiles)))

agdadeps ?= $(call findfiles,$(agdadir))

# Default values for programs

export AGDA ?= agda
export AGDADOC ?= $(AGDA) --html
export CURL ?= curl
export INSTALL ?= install
export TAR ?= tar

# Default values for program flags

export AGDAFLAGS ?= $(addprefix -i,$(agdadir) $(stdlibdir))
export AGDADOCFLAGS ?= $(AGDAFLAGS)

# A function to find all the files under a given directory
# (find is not one of the "blessed" applications for portable makefiles).

findfiles = $(if $(wildcard $(1)/.),$(foreach x,$(wildcard $(1)/*),$(call findfiles,$(x))),$(1))

# A string equality function (really, I have to define this?)

stringeq = $(if $(subst $(1),,$(2)),,$(if $(subst $(2),,$(1)),,true))

# Create the target directories if need be

$(agdadir) $(builddir) $(cachedir) $(datadir) $(depdir) $(docdir) $(htmldir) $(tmpdir):
	$(INSTALL) -d $@

# Rules for building Agda libraries

.PRECIOUS: $(agdadir)/%.agda $(agdadir)/%.agdai $(htmldir)/%.html

$(agdadir)/%.agda: $(srcdir)/%.agda
	$(INSTALL) -D $< $@

$(agdadir)/%.agdai: $(agdadir)/%.agda $(agdafiles) $(agdadeps)
	$(AGDA) $(AGDAFLAGS) $<

$(htmldir)/%.html: $(agdadir)/%.agda $(agdafiles) $(agdadeps) $(htmldir)
	$(AGDADOC) $(AGDADOCFLAGS) --html-dir $(htmldir) $<

# Rules for downloading files

.PRECIOUS: $(cachedir)/http/% $(cachedir)/https/% $(cachedir)/file/%

$(cachedir)/http/%:
	$(CURL) --create-dirs -o $(tmpdir)/http/$* http://$*
	$(INSTALL) -D $(tempdir)/http/$* $@

$(cachedir)/https/%:
	$(CURL) --create-dirs -o $(tmpdir)/https/$* https://$*
	$(INSTALL) -D $(tempdir)/https/$* $@

$(cachedir)/file/%: /%
	$(INSTALL) -D $< $@

# Assert that a string is non-empty

assert = $(if $(1),$(1),$(error $(2)))

# Convert a dependency to a URI.

dep2uri = $(call assert,$($(patsubst %/,%,$(1))),No URI declared for $(1))

# Convert a dependency to a cache file.

dep2tgz = $(cachedir)/$(subst ://,/,$(call dep2uri,$(1)))

# Rules to unpack dependencies

.PRECIOUS: $(depdir)/%/unpacked  $(depdir)/%/downloaded

$(depdir)/%/unpacked:
	$(MAKE) $(call dep2tgz,$*)
	$(INSTALL) -d $@
	$(TAR) -C $@ -xf $(call dep2tgz,$*)

$(depdir)/%/downloaded:
	@rm -rf $(dir $@)/unpacked
	$(MAKE) $(dir $@)/unpacked
	@echo $(call dep2uri,$*) > $@

redownload-%:
	@rm -f $(depdir)/%/downloaded
	$(MAKE) $(depdir)/%/downloaded

download-%: $(depdir)/%/downloaded
	$(if $(call stringeq,$(call dep2uri,$*),$(shell cat $<)),,$(MAKE) redownload-$*)

download-dependencies:
	$(MAKE) $(addprefix download-,$(dependencies))

# Rules to clean dependencies, by recursively calling make clean.

$(depdir)/%/recursive-clean: $(depdir)/%/Makefile
	$(MAKE) -C $(dir $@) clean

$(depdir)/%/recursive-clean: $(depdir)/%/makefile
	$(MAKE) -C $(dir $@) clean

$(depdir)/%/recursive-clean:
	$(MAKE) $(addsuffix recursive-clean,$(dir $(wildcard $(dir $@)/*/.)))

$(depdir)/%/cleaned: $(depdir)/%/downloaded
	$(MAKE) $(dir $@)/unpacked/recursive-clean

clean-dependency-%: $(depdir)/%/cleaned
	@rm -f $(depdir)/$*/installed

clean-dependencies:
	$(MAKE) $(addprefix clean-dependency-,$(dependencies))

# Rules to install dependencies, by recursively calling make install.

$(depdir)/%/recursive-install: $(depdir)/%/Makefile
	$(MAKE) -C $(dir $@) install

$(depdir)/%/recursive-install: $(depdir)/%/makefile
	$(MAKE) -C $(dir $@) install

$(depdir)/%/recursive-install:
	$(MAKE) $(addsuffix recursive-install,$(dir $(wildcard $(dir $@)/*/.)))

.PRECIOUS: $(depdir)/%/installed

$(depdir)/%/installed: $(depdir)/%/downloaded
	$(MAKE) $(dir $@)/unpacked/recursive-install
	@echo $(call dep2uri,$*) > $@

install-dependency-%: $(depdir)/%/installed
	$(if $(call stringeq,$(call dep2uri,$*),$(shell cat $<)),, \
	  $(error Package $* expected URI <$(call dep2uri,$*)> found <$(shell cat $<)>))

install-dependencies:
	$(MAKE) $(addprefix install-dependency-,$(dependencies))
