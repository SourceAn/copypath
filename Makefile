.PHONY: build install uninstall icon clean help

help:
	@echo "make build     构建到 ./build/CopyPath.app"
	@echo "make install   构建 + 安装到 /Applications + 注册 Finder 扩展"
	@echo "make uninstall 卸载 App 并注销扩展"
	@echo "make icon      重新生成 App 图标"
	@echo "make clean     删除构建产物"

build:
	./build.sh

install:
	./install.sh

uninstall:
	./uninstall.sh

icon:
	./Tools/make-icon.sh

clean:
	rm -rf build
