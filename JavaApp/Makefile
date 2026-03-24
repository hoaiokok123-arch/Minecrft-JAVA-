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
	@set -e
	@echo "Checking for empty class files"
	$(eval EMPTY_CLASSES := $(shell find $(OUTPUTDIR) -name '*.class' -size 0))
	@if [ -n "$(EMPTY_CLASSES)" ]; then \
		echo "Error: found empty class files in $@: $(EMPTY_CLASSES)"; \
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
