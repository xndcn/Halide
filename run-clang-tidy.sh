#!/bin/bash

set -e

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

[[ "$1" != "" && "$1" != "-fix" ]] && echo "The only supported argument is -fix" && exit

# We are currently standardized on using LLVM/Clang10 for this script.
# Note that this is totally independent of the version of LLVM that you
# are using to build Halide itself. If you don't have LLVM10 installed,
# you can usually install what you need easily via:
#
# sudo apt-get install llvm-10 clang-10 libclang-10-dev clang-tidy-10
# export CLANG_TIDY_LLVM_INSTALL_DIR=/usr/lib/llvm-10

[ -z "$CLANG_TIDY_LLVM_INSTALL_DIR" ] && echo "CLANG_TIDY_LLVM_INSTALL_DIR must point to an LLVM installation dir for this script." && exit
echo CLANG_TIDY_LLVM_INSTALL_DIR = ${CLANG_TIDY_LLVM_INSTALL_DIR}

# Use a temp folder for the CMake stuff here, so it's fresh & correct every time
CLANG_TIDY_BUILD_DIR=`mktemp -d`
echo CLANG_TIDY_BUILD_DIR = ${CLANG_TIDY_BUILD_DIR}

echo Building compile_commands.json...
cmake -DCMAKE_BUILD_TYPE=Debug \
      -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
      -DLLVM_DIR=${CLANG_TIDY_LLVM_INSTALL_DIR} \
      -S ${ROOT_DIR} \
      -B ${CLANG_TIDY_BUILD_DIR} \
      -G Ninja \
      > /dev/null

[ -a ${CLANG_TIDY_BUILD_DIR}/compile_commands.json ]

# We must populate the includes directory to check things outside of src/
ninja -C ${CLANG_TIDY_BUILD_DIR} HalideIncludes

RUN_CLANG_TIDY=${CLANG_TIDY_LLVM_INSTALL_DIR}/share/clang/run-clang-tidy.py

# We deliberately skip apps/ and test/ for now, as the compile commands won't include
# generated headers files from Generators.
CLANG_TIDY_TARGETS=$(find \
     "${ROOT_DIR}/src" \
     "${ROOT_DIR}/tools" \
     "${ROOT_DIR}/util" \
     "${ROOT_DIR}/python_bindings" \
     -name *.cpp -o -name *.h -o -name *.c)

if [ $(uname -s) = "Darwin" ]; then
    LOCAL_CORES=`sysctl -n hw.ncpu`
else
    LOCAL_CORES=`nproc`
fi

${RUN_CLANG_TIDY} \
    $1 \
    -header-filter='.*(?!pybind11).*' \
    -j ${LOCAL_CORES} \
    -quiet \
    -p ${CLANG_TIDY_BUILD_DIR} \
    -clang-tidy-binary ${CLANG_TIDY_LLVM_INSTALL_DIR}/bin/clang-tidy \
    -clang-apply-replacements-binary ${CLANG_TIDY_LLVM_INSTALL_DIR}/bin/clang-apply-replacements \
    ${CLANG_TIDY_TARGETS} \
    2>&1 | grep -v "warnings generated" | sed "s|.*/||"

rm -rf ${CLANG_TIDY_BUILD_DIR}

