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

# Ninomae.Particles: the game launcher's particles drawn on the GPU (our own code, not from caelestia). It needs
# Qt's GPU headers (qt6-qtbase-private-devel); without them it's left out and the launcher draws on a Canvas
set(QT_NO_PRIVATE_MODULE_WARNING ON) # QRhi's headers are public in all but name since Qt 6.6
find_package(Qt6 QUIET COMPONENTS GuiPrivate)
if(NOT TARGET Qt::GuiPrivate)
    message(WARNING "qt6-qtbase-private-devel not installed: Ninomae.Particles is left out")
    return()
endif()
qt_add_library(ninomae-particles MODULE)
qt_add_qml_module(ninomae-particles
    URI Ninomae.Particles
    VERSION 1.0
    PLUGIN_TARGET ninomae-particles
    SOURCES
        src/particlelayer.cpp src/particlelayer.hpp
        src/particlesim.cpp src/particlesim.hpp
)
target_link_libraries(ninomae-particles PRIVATE Qt::Core Qt::Gui Qt::GuiPrivate Qt::Qml Qt::Quick)
target_include_directories(ninomae-particles PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src")
qt_add_shaders(ninomae-particles "particle_shaders"
    OPTIMIZED NOHLSL NOMSL
    GLSL "300es,330"
    PREFIX "/"
    BASE src
    FILES
        src/shaders/particle.frag
        src/shaders/particle.vert
)
