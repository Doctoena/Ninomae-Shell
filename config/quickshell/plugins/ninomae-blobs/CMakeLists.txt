# Ninomae.Blobs: gooey blob renderer for the shell's drawers.
# Derived from the Caelestia.Blobs module of caelestia-dots/shell (GPL-3.0, see LICENSE and NOTICE;
# upstream commit in UPSTREAM_COMMIT). Changes: module/namespace renamed to Ninomae.
cmake_minimum_required(VERSION 3.19)
project(ninomae-blobs LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick ShaderTools)
qt_standard_project_setup(REQUIRES 6.9)
set(QT_QML_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qml")

# The backing library is the plugin itself: one self-contained .so, nothing to rpath
qt_add_library(ninomae-blobs MODULE)
qt_add_qml_module(ninomae-blobs
    URI Ninomae.Blobs
    VERSION 1.0
    PLUGIN_TARGET ninomae-blobs
    SOURCES
        src/blobgroup.cpp src/blobgroup.hpp
        src/blobshape.cpp src/blobshape.hpp
        src/blobrect.cpp src/blobrect.hpp
        src/blobinvertedrect.cpp src/blobinvertedrect.hpp
        src/blobmaterial.cpp src/blobmaterial.hpp
)
target_link_libraries(ninomae-blobs PRIVATE Qt::Core Qt::Gui Qt::Qml Qt::Quick)
# Generated type-registration code includes the headers by bare name
target_include_directories(ninomae-blobs PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src")

qt_add_shaders(ninomae-blobs "blob_shaders"
    BATCHABLE OPTIMIZED NOHLSL NOMSL
    GLSL "300es,330"
    PREFIX "/"
    BASE src
    FILES
        src/shaders/blob.frag
        src/shaders/blob.vert
)
