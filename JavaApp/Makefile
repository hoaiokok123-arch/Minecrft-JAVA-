# Prerequisite variables
SOURCEDIR := src
OUTPUTDIR := build

SOURCES := $(shell find $(SOURCEDIR) -type f -name '*.java')
CLASSES := $(SOURCES:$(SOURCEDIR)/%.java=$(OUTPUTDIR)/%.class)

TARGETS := $(shell find $(SOURCEDIR) -mindepth 1 -maxdepth 1 -type d)
TARGETS := $(TARGETS:$(SOURCEDIR)/%=$(OUTPUTDIR)/%.jar)
TARGETS += $(OUTPUTDIR)/lwjgl-3.3.1.jar

LWJGL331_VERSION := 3.3.1
LWJGL331_DIR := libs/lwjgl-3.3.1
LWJGL331_MODULES := lwjgl lwjgl-freetype lwjgl-glfw lwjgl-nanovg lwjgl-openal lwjgl-opengl lwjgl-shaderc lwjgl-stb lwjgl-tinyfd lwjgl-vma lwjgl-vulkan
COMPILE_LIBS := $(wildcard libs/lwjgl/*.jar) $(wildcard libs/others/*.jar) $(wildcard libs/caciocavallo/*.jar) $(wildcard libs/caciocavallo17/*.jar)

# Add all jars to classpath and allow compiling with private API
JCFLAGS := -cp "$(subst $() $(),:,$(wildcard $(SOURCEDIR)/*/):$(COMPILE_LIBS))" -XDignore.symbol.file

all: $(TARGETS)
	
# Sometimes the CI produces empty class file resulting in broken jar, so we check and abort here
check_empty_classes:
	@set -e; \
	echo "Checking for empty class files"; \
	EMPTY_CLASSES=$$(find $(OUTPUTDIR) -name '*.class' -size 0); \
	if [ -z "$$EMPTY_CLASSES" ]; then \
		exit 0; \
	fi; \
	echo "Found empty class files, recompiling affected sources"; \
	EMPTY_SOURCES=$$(printf '%s\n' "$$EMPTY_CLASSES" | sed \
		-e 's#^$(OUTPUTDIR)/classes/##' \
		-e 's#^$(OUTPUTDIR)/[^/]*/##' \
		-e 's#\\$$[^/]*\.class$$#.class#' \
		-e 's#\.class$$#.java#' | while IFS= read -r rel; do \
			find $(SOURCEDIR) -path "*/$$rel" -print -quit; \
		done | sort -u); \
	if [ -z "$$EMPTY_SOURCES" ]; then \
		echo "Error: unable to map empty class files to source files: $$EMPTY_CLASSES"; \
		exit 1; \
	fi; \
	for src in $$EMPTY_SOURCES; do \
		target=$${src#$(SOURCEDIR)/}; \
		target=$${target%%/*}; \
		class_rel=$${src#$(SOURCEDIR)/$$target/}; \
		class_rel=$${class_rel%.java}; \
		class_dir=$$(dirname "$$class_rel"); \
		echo "Recompiling $$src"; \
		$(BOOTJDK)/javac $(JCFLAGS) -d $(OUTPUTDIR)/classes "$$src"; \
		mkdir -p "$(OUTPUTDIR)/$$target/$$class_dir"; \
		cp $(OUTPUTDIR)/classes/$$class_rel*.class "$(OUTPUTDIR)/$$target/$$class_dir/"; \
	done; \
	EMPTY_CLASSES=$$(find $(OUTPUTDIR) -name '*.class' -size 0); \
	if [ -n "$$EMPTY_CLASSES" ]; then \
		echo "Error: found empty class files in $@: $$EMPTY_CLASSES"; \
		exit 1; \
	fi

# Rules for building java class
$(CLASSES): $(OUTPUTDIR)/%.class: $(SOURCEDIR)/%.java
	@set -e
	$(eval TARGET=$(word 2, $(subst /, ,$@)))
	@mkdir -p $(OUTPUTDIR)/classes
	@mkdir -p $(dir $@)
	@echo "Compiling $<"
	@$(BOOTJDK)/javac $(JCFLAGS) -d $(OUTPUTDIR)/classes $<
	@cp $(@:$(OUTPUTDIR)/$(TARGET)/%.class=$(OUTPUTDIR)/classes/%*.class) $(dir $@)/

$(OUTPUTDIR)/launcher.jar: $(CLASSES) check_empty_classes
	@set -e
	@echo "Creating $@"
	@$(BOOTJDK)/jar -cf $@ -C $(basename $@) .

$(OUTPUTDIR)/lwjgl.jar: $(CLASSES) check_empty_classes
	@set -e
	@echo "Creating $@"
	@mkdir -p $(OUTPUTDIR)/lwjgl_lib
	@cd $(OUTPUTDIR)/lwjgl_lib && find ../../libs/lwjgl -name 'lwjgl*.jar' -exec $(BOOTJDK)/jar -xf {} \; && rm -rf META-INF
	@cp -R $(OUTPUTDIR)/lwjgl/* $(OUTPUTDIR)/lwjgl_lib/
	@$(BOOTJDK)/jar -cf $@ -C $(OUTPUTDIR)/lwjgl_lib .

prepare_lwjgl_331:
	@set -e
	@mkdir -p $(LWJGL331_DIR)
	@for module in $(LWJGL331_MODULES); do \
		if [ ! -f "$(LWJGL331_DIR)/$$module.jar" ]; then \
			echo "Downloading $$module-$(LWJGL331_VERSION).jar"; \
			wget -q --show-progress -O "$(LWJGL331_DIR)/$$module.jar" "https://repo1.maven.org/maven2/org/lwjgl/$$module/$(LWJGL331_VERSION)/$$module-$(LWJGL331_VERSION).jar"; \
		fi; \
	done
	@if [ ! -f "$(LWJGL331_DIR)/lwjgl-lwjglx.jar" ]; then \
		cp libs/lwjgl/lwjgl-lwjglx.jar "$(LWJGL331_DIR)/lwjgl-lwjglx.jar"; \
	fi

$(OUTPUTDIR)/lwjgl-3.3.1.jar: $(CLASSES) check_empty_classes prepare_lwjgl_331
	@set -e
	@echo "Creating $@"
	@mkdir -p $(OUTPUTDIR)/lwjgl_331_lib
	@cd $(OUTPUTDIR)/lwjgl_331_lib && find ../../$(LWJGL331_DIR) -name 'lwjgl*.jar' -exec $(BOOTJDK)/jar -xf {} \; && rm -rf META-INF
	@cp -R $(OUTPUTDIR)/lwjgl/* $(OUTPUTDIR)/lwjgl_331_lib/
	@$(BOOTJDK)/jar -cf $@ -C $(OUTPUTDIR)/lwjgl_331_lib .

$(OUTPUTDIR)/patchjna_agent.jar: $(CLASSES)
	@set -e
	@mv $(basename $@)/com/sun/jna/Platform.class $(basename $@)/com/sun/jna/Platform.class.patch
	@echo "Creating $@"
	@$(BOOTJDK)/jar -cfm $@ $(SOURCEDIR)/patchjna_agent.txt -C $(basename $@) .

clean:
	rm -rf $(OUTPUTDIR)

.SUFFIXES: .java
.PHONY: all clean prepare_lwjgl_331
