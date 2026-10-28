# Convenience: forwards to the macOS app (macos/Makefile). The Windows app builds with dotnet in windows/.
.PHONY: build app run install uninstall reset-permissions test release publish clean icon
build app run install uninstall reset-permissions test release publish clean icon:
	$(MAKE) -C macos $@
