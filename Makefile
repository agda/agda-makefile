# Default values for variables exported to subpackages

export builddir ?= $(CURDIR)/build
export cachedir ?= $(builddir)/cache
export depdir ?= $(builddir)/dependencies

export prefix ?= $(builddir)
export bindir ?= $(prefix)/bin
export libdir ?= $(prefix)/lib
export datadir ?= $(prefix)/share
export cabaldir ?= $(builddir)/cabal
export agdadir ?= $(datadir)/agda
export haskelldir ?= $(datadir)/haskell

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
haskellfiles ?= $(patsubst $(srcdir)/%,$(haskelldir)/%,$(filter %.hs,$(srcfiles)))

agdadeps ?= $(filter %.agda,$(call findfiles,$(agdadir)))
haskelldeps ?= $(filter %.hs,$(call findfiles,$(haskelldir)))

# Default values for programs

export AGDA ?= agda
export AGDAC ?= $(AGDA) -c
export AGDADOC ?= $(AGDA) --html
export CABAL ?= cabal
export CURL ?= curl
export GHC ?= ghc
export GHCPKG ?= ghc-pkg
export INSTALL ?= install
export TAR ?= tar

# Default values for program flags

export AGDAFLAGS ?= $(addprefix -i,$(agdadir) $(stdlibdir))
export AGDACFLAGS ?= $(AGDAFLAGS) $(addprefix --ghc-flag=,$(GHCFLAGS))
export AGDADOCFLAGS ?= $(AGDAFLAGS)
export CABALFLAGS ?= --prefix=$(prefix) --libdir=$(libdir)
export GHCFLAGS ?= -odir$(libdir) $(addprefix -i,$(stdlibdir)) -package-conf$(cabaldir)

# A function to find all the files under a given directory
# (find is not one of the "blessed" applications for portable makefiles).

findfiles = $(if $(wildcard $(1)/.),$(foreach x,$(wildcard $(1)/*),$(call findfiles,$(x))),$(1))

# A string equality function (really, I have to define this?)

stringeq = $(if $(subst $(1),,$(2)),,$(if $(subst $(2),,$(1)),,true))

# Rules for building Agda libraries

.PRECIOUS: $(agdadir)/%.agda $(haskelldir)/%.hs $(agdadir)/%.agdai $(bindir)/% $(htmldir)/%.html

$(agdadir)/%.agda: $(srcdir)/%.agda
	$(INSTALL) -D $< $@

$(haskelldir)/%.hs: $(srcdir)/%.hs
	$(INSTALL) -D $< $@

$(agdadir)/%.agdai: $(agdadir)/%.agda $(agdafiles) $(agdadeps)
	$(AGDA) $(AGDAFLAGS) $<

$(bindir)/%: $(agdadir)/%.agda $(agdafiles) $(haskellfiles) $(agdadeps) $(haskelldeps)
	$(AGDAC) $(AGDACFLAGS) --compile-dir=$(haskelldir) $<
	$(INSTALL) -d $(dir $@)
	mv $(haskelldir)/$(notdir $@) $@

$(htmldir)/%.html: $(agdafiles) $(agdadeps)
	$(AGDADOC) $(AGDADOCFLAGS) --html-dir $(htmldir) $(agdadir)/$(subst .,/,$*).agda

# Rules for downloading files

.PRECIOUS: $(cachedir)/http/% $(cachedir)/https/% $(cachedir)/file/%

$(cachedir)/http/%:
	$(CURL) --create-dirs -o $(tmpdir)/http/$* -L http://$*
	$(INSTALL) -D $(tmpdir)/http/$* $@

$(cachedir)/https/%:
	$(CURL) --create-dirs -o $(tmpdir)/https/$* -L https://$*
	$(INSTALL) -D $(tmpdir)/https/$* $@

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
	$(TAR) -C $@ -xzf $(call dep2tgz,$*)

$(depdir)/%/downloaded:
	@rm -rf $(dir $@)/unpacked
	$(MAKE) $(dir $@)/unpacked
	@echo $(call dep2uri,$*) > $@

redownload-dependency-%:
	@rm -f $(depdir)/$*/downloaded
	$(MAKE) $(depdir)/$*/downloaded

download-dependency-%: $(depdir)/%/downloaded
	$(if $(call stringeq,$(call dep2uri,$*),$(shell cat $<)),,$(MAKE) redownload-dependency-$*)

download-dependencies:
	$(MAKE) $(addprefix download-dependency-,$(dependencies))

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

$(depdir)/%/installed:
	$(MAKE) $(dir $@)/unpacked/recursive-install
	@echo $(call dep2uri,$*) > $@

install-after-download-dependency-%: $(depdir)/%/installed
	$(if $(call stringeq,$(call dep2uri,$*),$(shell cat $<)),, \
	  $(error Package $* expected URI <$(call dep2uri,$*)> found <$(shell cat $<)>))

install-dependency-%: download-dependency-% install-after-download-dependency-%
	$(info Installed dependency $*)

install-dependencies:
	$(MAKE) $(addprefix install-dependency-,$(dependencies))

# Targets to install dependencies via cabal

.PRECIOUS: $(cabaldir)

$(cabaldir):
	$(GHCPKG) init $(GHCPKGFLAGS) $@

install-cabal-%: $(cabaldir)
	$(CABAL) --package-db=$(cabaldir) --ghc-pkg-option=--package-conf=$(cabaldir) $(CABALFLAGS) install $*
