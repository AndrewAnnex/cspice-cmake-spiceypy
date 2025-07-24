cmake_minimum_required(VERSION 3.24)

#-------------------------------------------------------------------------------
# 1) Project declaration with version and language
#-------------------------------------------------------------------------------
project(cspice
    VERSION 67.0.0
    DESCRIPTION "NAIF CSPICE Toolkit"
    LANGUAGES C
)

#-------------------------------------------------------------------------------
# 2) Build type default
#-------------------------------------------------------------------------------
# Only seed a default; let the user override with -DCMAKE_BUILD_TYPE.
if(NOT DEFINED CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type (default Release)" )
endif()

# -----------------------------------------------------------------------------
# Log the C compiler and its ID
# -----------------------------------------------------------------------------
message(STATUS "Using C Compiler: ${CMAKE_C_COMPILER}")
message(STATUS "C Compiler ID: ${CMAKE_C_COMPILER_ID}")

# -----------------------------------------------------------------------------
# Define the version of CSPICE.
# -----------------------------------------------------------------------------
set(CSPICE_VERSION "N0067")

#-------------------------------------------------------------------------------
# 3) Modules & install dirs
#-------------------------------------------------------------------------------
include(CTest)
include(GNUInstallDirs)
include(CMakePackageConfigHelpers)
include(FetchContent)

# -----------------------------------------------------------------------------
# Determine whether to use a local CSPICE source or to download it.
# -----------------------------------------------------------------------------
if(DEFINED ENV{CSPICE_SRC})
  set(CSPICE_SOURCE_ROOT $ENV{CSPICE_SRC})
  message(STATUS "Using local CSPICE source from: $ENV{CSPICE_SRC}")
else()
  # -----------------------------------------------------------------------------
  # Select the archive URL based on OS and architecture.
  # -----------------------------------------------------------------------------
  if(WIN32)
    set(CSPICE_ARCHIVE_URL "https://naif.jpl.nasa.gov/pub/naif/misc/toolkit_${CSPICE_VERSION}/C/PC_Windows_VisualC_64bit/packages/cspice.zip")
  elseif(APPLE)
    if(CMAKE_SYSTEM_PROCESSOR STREQUAL "arm64")
      set(CSPICE_ARCHIVE_URL "https://naif.jpl.nasa.gov/pub/naif/misc/toolkit_${CSPICE_VERSION}/C/MacM1_OSX_clang_64bit/packages/cspice.tar.Z")
    else()
      set(CSPICE_ARCHIVE_URL "https://naif.jpl.nasa.gov/pub/naif/misc/toolkit_${CSPICE_VERSION}/C/MacIntel_OSX_AppleC_64bit/packages/cspice.tar.Z")
    endif()
  else() # Assuming Linux or similar UNIX
    if(CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
      set(CSPICE_ARCHIVE_URL "https://naif.jpl.nasa.gov/pub/naif/misc/toolkit_${CSPICE_VERSION}/C/PC_Linux_GCC_64bit/packages/cspice.tar.Z")
    else()
      set(CSPICE_ARCHIVE_URL "https://naif.jpl.nasa.gov/pub/naif/misc/toolkit_${CSPICE_VERSION}/C/PC_Linux_GCC_64bit/packages/cspice.tar.Z")
    endif()
  endif()
  message(STATUS "No local CSPICE source provided. Downloading from: ${CSPICE_ARCHIVE_URL}")
  FetchContent_Declare(
    cspice_src
    URL ${CSPICE_ARCHIVE_URL}
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    SOURCE_DIR ${CMAKE_BINARY_DIR}/cspice-src
  )
  FetchContent_MakeAvailable(cspice_src)
  set(CSPICE_SOURCE_ROOT ${cspice_src_SOURCE_DIR})
endif()

# -----------------------------------------------------------------------------
# 5) Locate the CSPICE source files.
# -----------------------------------------------------------------------------
file(GLOB_RECURSE CSPICE_SOURCES
  ${CSPICE_SOURCE_ROOT}/src/cspice/*.c
)

# -----------------------------------------------------------------------------
# Create the shared library target.
# -----------------------------------------------------------------------------
add_library(cspice SHARED ${CSPICE_SOURCES})

target_include_directories(cspice 
  PUBLIC 
  $<BUILD_INTERFACE:${CSPICE_SOURCE_ROOT}/include>
  $<INSTALL_INTERFACE:include/cspice>
)

# -----------------------------------------------------------------------------
# Additional compile definitions, flags, or versioning.
# -----------------------------------------------------------------------------
target_compile_definitions(cspice PRIVATE -DNDEBUG)
target_compile_features(cspice PUBLIC c_std_11)
set_target_properties(cspice PROPERTIES
    C_STANDARD_REQUIRED       ON
    C_EXTENSIONS              OFF
    POSITION_INDEPENDENT_CODE ON
    VERSION                   ${PROJECT_VERSION}
    SOVERSION                 ${PROJECT_VERSION_MAJOR}
)

# -----------------------------------------------------------------------------
# Platform-specific compile and link flags.
# -----------------------------------------------------------------------------
if(APPLE)
  target_link_options(cspice PRIVATE
                      -dynamiclib
                      -install_name "@rpath/libcspice.so")
endif()

# -----------------------------------------------------------------------------
# Windows-specific configuration: Use a .def file for symbol exports.
# -----------------------------------------------------------------------------
if(WIN32)
  target_compile_definitions(cspice PRIVATE _COMPLEX_DEFINED MSDOS OMIT_BLANK_CC NON_ANSI_STDIO)
  target_compile_options(cspice PRIVATE /nologo)
  set(CSPICE_DEF_FILE "${CMAKE_CURRENT_SOURCE_DIR}/cspice.def")
  if(EXISTS ${CSPICE_DEF_FILE})
    message(STATUS "Using CSPICE .def file: ${CSPICE_DEF_FILE}")
    target_link_options(cspice PRIVATE "/DEF:${CSPICE_DEF_FILE}")
  else()
    message(WARNING "CSPICE .def file not found: ${CSPICE_DEF_FILE}")
  endif()
endif()

#-------------------------------------------------------------------------------
# Link math library
#-------------------------------------------------------------------------------
if(NOT MSVC)
  target_link_libraries(cspice PUBLIC m)
endif()

# -----------------------------------------------------------------------------
# Create a namespaced alias so downstream can do “cspice::cspice”
# -----------------------------------------------------------------------------
add_library(CSPICE::cspice ALIAS cspice)

# -----------------------------------------------------------------------------
# Installs for cspice headers/shared library etc
# -----------------------------------------------------------------------------
install(TARGETS cspice 
        EXPORT CSPICETargets
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
        ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
        PUBLIC_HEADER DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/cspice
)

# Install the header directory 
install(DIRECTORY ${CSPICE_SOURCE_ROOT}/include/
        DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/cspice
)

#-------------------------------------------------------------------------------
# CMake package configuration
#-------------------------------------------------------------------------------
# Version file
write_basic_package_version_file(
    "${CMAKE_CURRENT_BINARY_DIR}/cspiceConfigVersion.cmake"
    VERSION     ${PROJECT_VERSION}
    COMPATIBILITY AnyNewerVersion
)

# Config file (template: cmake/cspiceConfig.cmake.in)
configure_package_config_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/cmake/cspiceConfig.cmake.in"
    "${CMAKE_CURRENT_BINARY_DIR}/cspiceConfig.cmake"
    INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/cspice
)

# Export a CMake package config so others can do find_package(CSPICE)
install(EXPORT CSPICETargets
  FILE   cspiceTargets.cmake
  NAMESPACE CSPICE::
  DESTINATION lib/cmake/CSPICE
)

install(FILES
   "${CMAKE_CURRENT_BINARY_DIR}/cspiceConfig.cmake"
   "${CMAKE_CURRENT_BINARY_DIR}/cspiceConfigVersion.cmake"
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/cspice
)

# -----------------------------------------------------------------------------
# Optional Testing, only build & register tests if BUILD_TESTING is ON
# -----------------------------------------------------------------------------
if(BUILD_TESTING)
  add_executable(test_cspice test_cspice.c)
  target_link_libraries(test_cspice PRIVATE cspice)
  add_test(NAME cspice_test
           COMMAND test_cspice
           WORKING_DIRECTORY ${CMAKE_BINARY_DIR})
endif()
