#! /bin/sh
# -*- shell-script -*-

# The MIT License (MIT)
# Copyright (c) 2018 Acclution <github@acclution.se>

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.


######
# Setup build configuration
read -p "Pull from git? " -n 1 -r
export GIT_PULL=$REPLY
printf "\n"

read -p "Build godot? " -n 1 -r
export BUILD_GODOT=$REPLY
printf "\n"

read -p "Build export templates? " -n 1 -r
export BUILD_TEMPLATES=$REPLY
printf "\n"

read -p "Build godot-cpp? " -n 1 -r
export BUILD_GODOT_CPP=$REPLY
printf "\n"

read -p "Install Editor? " -n 1 -r
export INSTALL_EDITOR=$REPLY
printf "\n"

read -p "Install godot-cpp? " -n 1 -r
export INSTALL_GODOT_CPP=$REPLY
printf "\n"


#####
# Godot build
if [[ $BUILD_GODOT =~ ^[Yy]$ ]]
then
	if [ -d "godot" ]; then
		cd godot
		if [[ $GIT_PULL =~ ^[Yy]$ ]]
		then
			git stash
			git reset --hard
			git pull origin master
		fi
	else
	  git clone https://github.com/godotengine/godot.git
	  cd godot
	fi

	# Remove old builds
	rm -f bin/*

	### Build binaries normally
	# Editor
	scons p=x11 use_llvm=yes target=release_debug tools=yes -j 4
	mv bin/godot.x11.opt.tools.64.llvm bin/godot_editor
	scons p=x11 use_llvm=yes target=debug tools=yes -j 4
	mv bin/godot.x11.tools.64.llvm bin/godot_editor_debug
	# Editor Server
	scons p=server use_llvm=yes target=release_debug tools=yes -j 4
	mv bin/godot_server.x11.opt.tools.64.llvm bin/godot_server_editor
	scons p=server use_llvm=yes target=debug tools=yes -j 4
	mv bin/godot_server.x11.tools.64.llvm bin/godot_server_editor_debug

	######
	# Export templates

	if [[ $BUILD_TEMPLATES =~ ^[Yy]$ ]]
	then
		# Just a marker to show that templates has been built
		touch bin/has_templates

		# Linux 64bit
		scons p=x11 use_llvm=yes target=debug tools=no -j 4
		mv bin/godot.x11.debug.64.llvm bin/linux_x11_64_debug
		scons p=x11 use_llvm=yes target=release tools=no -j 4
		mv bin/godot.x11.opt.64.llvm bin/linux_x11_64_release

		# Linux 32bit
		#scons p=x11 use_llvm=yes tools=no target=release bits=32 -j 4
		#mv bin/godot.x11.opt.64.llvm bin/linux_x11_32_release
		#scons p=x11 use_llvm=yes tools=no target=release_debug bits=32 -j 4
		#mv bin/godot.x11.opt.64.llvm bin/linux_x11_32_debug

		# Linux server
		scons p=server use_llvm=yes target=debug tools=no -j 4
		mv bin/godot_server.x11.debug.64.llvm bin/linux_server_64_debug
		scons p=server use_llvm=yes target=release tools=no -j 4
		mv bin/godot_server.x11.opt.64.llvm bin/linux_server_64

		# Web
		source /etc/profile.d/emscripten.sh
		scons platform=javascript tools=no target=release javascript_eval=no -j 4
		mv bin/godot.javascript.opt.zip bin/webassembly_release.zip
		scons platform=javascript tools=no target=release_debug javascript_eval=no -j 4
		mv bin/godot.javascript.opt.debug.zip bin/webassembly_debug.zip

		# Android
		scons p=android target=release android_arch=armv7 -j 4
		scons p=android target=release android_arch=arm64v8 -j 4
		scons p=android target=release android_arch=x86 -j 4
		cd platform/android/java
		gradle build
		cd ../../../
		scons p=android target=release_debug android_arch=armv7 -j 4
		scons p=android target=release_debug android_arch=arm64v8 -j 4
		scons p=android target=release_debug android_arch=x86 -j 4
		cd platform/android/java
		gradle build
		cd ../../../

		# Cross compile to windows
		#export MINGW32_PREFIX="/path/to/i686-w64-mingw32-"
		#export MINGW64_PREFIX="/path/to/x86_64-w64-mingw32-"
		#scons platform=windows tools=no target=release bits=64
		#scons platform=windows tools=no target=release_debug bits=64
	fi

	cd ..
fi

#####
# GodotCpp build
if [[ $BUILD_GODOT_CPP =~ ^[Yy]$ ]]
then
	# Pull and build the native plugin api
	if [ -d "godot-cpp" ]; then
		cd godot-cpp
		if [[ $GIT_PULL =~ ^[Yy]$ ]]
		then
			git stash
			git reset --hard
			git pull origin master
		fi
	else
		git clone https://github.com/GodotNativeTools/godot-cpp
		cd godot-cpp
	fi

	# Define our build types and android toolchains here for building with cmake
	build_types=(Debug Release)
	android_toolchains=(arm-linux-androideabi-4.9 aarch64-linux-android-4.9 x86-4.9 x86_64-4.9)

	export GODOT_DIR=../godot

	rm -r bin

	for build_type in ${build_types[*]}
	do
		# If we are building for debug then generate the api from the debug editor
		if [ $build_type == Debug ]
		then
			$GODOT_DIR/bin/godot_editor_debug --gdnative-generate-json-api godot_headers/api.json
		else
			$GODOT_DIR/bin/godot_editor --gdnative-generate-json-api godot_headers/api.json
		fi

		mkdir -p .cmake_build
		cd .cmake_build

		# Build Linux version with clang
		mkdir -p Linux$build_type
		cd Linux$build_type
		cmake -DGODOT_HEADERS_DIR=$GODOT_DIR/modules/gdnative/include -DCMAKE_BUILD_TYPE=$build_type -G Ninja ../..
		cmake --build . -j 4
		cd ..

		for toolchain in ${android_toolchains[*]}
		do
			# Build Android version with the defined toolchains
			mkdir -p Android$build_type$toolchain
			cd Android$build_type$toolchain
			$ANDROID_SDK/cmake/3.6.4111459/bin/cmake -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake -DANDROID_TOOLCHAIN=clang -DANDROID_TOOLCHAIN_NAME=$toolchain \
			-DANDROID_PLATFORM=android-23 -DGODOT_HEADERS_DIR=$GODOT_DIR/modules/gdnative/include -DCMAKE_BUILD_TYPE=$build_type ../..
			cmake --build . -j 4
			cd ..
		done

		cd ..
	done

	cd ..
fi

#####
# Install Editor
if [[ $INSTALL_EDITOR =~ ^[Yy]$ ]]
then
	cp godot/bin/godot_editor ~/.local/bin
	cp godot/bin/godot_editor_debug ~/.local/bin
	cp godot/bin/godot_server_editor ~/.local/bin
	cp godot/bin/godot_server_editor_debug ~/.local/bin
	rm -r ~/.local/include/godot
	cp -r godot/modules/gdnative/include ~/.local/include/godot

	if [ -f "godot/bin/has_templates" ]
	then
		# Get godot version and remove revision and custom_build from version
		# version looks like: 3.1.dev.custom_build.6c09cdd
		version=$(godot/bin/godot_editor --version 2>&1)
		version="${version%.*}" # Removes revision
		version="${version%.*}" # Removes custom_build

		# Copy templates to template folder
		mkdir -p ~/.local/share/godot/templates
		rm -rf ~/.local/share/godot/templates/$version
		cp -r godot/bin ~/.local/share/godot/templates/$version
		echo $version > ~/.local/share/godot/templates/$version/version.txt
	fi
fi


#####
# Install godot-cpp
if [[ $INSTALL_GODOT_CPP =~ ^[Yy]$ ]]
then
	cp godot-cpp/bin/* ~/.local/lib
	rm -r ~/.local/include/godot-cpp
	cp -r godot-cpp/include ~/.local/include/godot-cpp
fi
