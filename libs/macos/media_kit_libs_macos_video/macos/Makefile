all: Frameworks/.symlinks

MPV_XCFRAMEWORKS_VERSION=0.6.8-mediaio.1
MPV_XCFRAMEWORKS_NAMES=Ass Avcodec Avfilter Avformat Avutil Dav1d Freetype Fribidi Harfbuzz Mbedcrypto Mbedtls Mbedx509 Mpv Png16 Swresample Swscale Uchardet Xml2
MPV_XCFRAMEWORKS_PREFIX=libmpv-xcframeworks_${MPV_XCFRAMEWORKS_VERSION}_macos-universal-video-default
MPV_XCFRAMEWORKS_RELEASE=https://github.com/xweiba/libmpv-darwin-build/releases/download/${MPV_XCFRAMEWORKS_VERSION}
MPV_XCFRAMEWORKS_CACHE=.cache/xcframeworks
MPV_XCFRAMEWORKS_ARCHIVES=$(addprefix ${MPV_XCFRAMEWORKS_CACHE}/${MPV_XCFRAMEWORKS_PREFIX}_,$(addsuffix .zip,${MPV_XCFRAMEWORKS_NAMES}))
MPV_XCFRAMEWORKS_STAMP=Frameworks/.artifacts-${MPV_XCFRAMEWORKS_VERSION}

SED=sed
SED_INPLACE_FLAG := $(shell ${SED} --version 2>&1 | grep -q 'GNU' && echo "" || echo "''")

${MPV_XCFRAMEWORKS_CACHE}/${MPV_XCFRAMEWORKS_PREFIX}_%.zip:
	mkdir -p ${MPV_XCFRAMEWORKS_CACHE}
	curl --fail --location --http1.1 --retry 3 --retry-all-errors --continue-at - \
		${MPV_XCFRAMEWORKS_RELEASE}/$(notdir $@) \
		-o $@.tmp
	EXPECTED=$$(awk '$$2 == "$(notdir $@)" { print $$1 }' libmpv-xcframeworks.sha256); \
		ACTUAL=$$(shasum -a 256 $@.tmp | awk '{ print $$1 }'); \
		test -n "$$EXPECTED" && \
		if test "$$ACTUAL" != "$$EXPECTED"; then rm -f $@.tmp; exit 1; fi
	mv $@.tmp $@

${MPV_XCFRAMEWORKS_STAMP}: ${MPV_XCFRAMEWORKS_ARCHIVES}
	mkdir -p Frameworks
	rm -rf Frameworks/*.xcframework Frameworks/.artifacts-*
	for archive in $^; do unzip -q -o "$$archive" -d Frameworks; done
	touch $@

Frameworks/.symlinks: ${MPV_XCFRAMEWORKS_STAMP}
	rm -rf Frameworks/.symlinks
	mkdir -p Frameworks/.symlinks/mpv
	${SED} -i ${SED_INPLACE_FLAG} 's/\r$$//g' create_framework_symlinks.sh # remove CRLF line terminator added by Flutter packaging (https://github.com/media-kit/media-kit/issues/338)
	sh create_framework_symlinks.sh Frameworks/Mpv.xcframework Frameworks/.symlinks/mpv

.PHONY: clean
clean:
	rm -rf .cache
	rm -f ./Headers/mpv/*.h
	rm -rf ./Frameworks/*.xcframework ./Frameworks/.artifacts-* ./Frameworks/.symlinks
