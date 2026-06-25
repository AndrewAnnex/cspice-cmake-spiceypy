cmake_minimum_required(VERSION 3.24)

# -----------------------------------------------------------------------------
# 1) Project declaration with version and language
# -----------------------------------------------------------------------------
project(cspice
    VERSION 67.0.0
    DESCRIPTION "NAIF CSPICE Toolkit"
    LANGUAGES C
)

# -----------------------------------------------------------------------------
# Define the version of CSPICE.
# -----------------------------------------------------------------------------
set(CSPICE_VERSION "N0067")
set(CSPICE_VERSION_INT 67)

# -----------------------------------------------------------------------------
# Define any options
# -----------------------------------------------------------------------------
option(BUILD_TESTING "Build the CSPICE simple c file test" OFF)
option(BUILD_EXECUTABLES "Build and install CSPICE example executables" OFF)

#-------------------------------------------------------------------------------
# 2) Build type default
# -----------------------------------------------------------------------------
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
# 3) Modules & install dirs
# -----------------------------------------------------------------------------
include(CTest)
include(GNUInstallDirs)
include(CMakePackageConfigHelpers)
include(FetchContent)
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(CspiceCommon)

if(DEFINED EMSCRIPTEN)
  # found out that this allowed us to avoid the custom target and to build the shared library as normal
  set_property(GLOBAL PROPERTY TARGET_SUPPORTS_SHARED_LIBS TRUE)
endif()

# -----------------------------------------------------------------------------
# Determine whether to use a local CSPICE source or to download it.
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# Patching helpers
#
# These operate on a *working copy* of the CSPICE source inside the build tree
# (prepared below). We never modify a user-provided CSPICE_SRC tree in place.
# -----------------------------------------------------------------------------

# Replace a literal string in a single file (warns if the pattern is absent).
function(cspice_patch_string_in_file file old new)
  file(READ "${file}" _contents)
  string(REPLACE "${old}" "${new}" _fixed "${_contents}")
  if(NOT "${_contents}" STREQUAL "${_fixed}")
    message(STATUS "Patched: ${file}")
    file(WRITE "${file}" "${_fixed}")
  else()
    message(WARNING "CSPICE patch: pattern not found in ${file}")
  endif()
endfunction()

# Regex-replace a symbol's f2c-generated declaration across all CSPICE .c files.
function(cspice_fix_f2c_symbol root symbol good_decl_pattern bad_decl_pattern)
  file(GLOB _cspice_cs ${root}/src/cspice/*.c)
  foreach(src ${_cspice_cs})
    file(READ "${src}" _contents)
    string(REGEX REPLACE "${bad_decl_pattern}" "${good_decl_pattern}" _fixed "${_contents}")
    if(NOT "${_contents}" STREQUAL "${_fixed}")
      message(STATUS "Patched ${symbol} prototype(s) in ${src}")
      file(WRITE "${src}" "${_fixed}")
    endif()
  endforeach()
endfunction()

# Apply every SpiceyPy-specific CSPICE patch to the tree rooted at <root>.
# Intended to run exactly once, on a fresh copy of the source.
function(cspice_apply_patches root)
  # ---------------------------------------------------------------------------
  # Patch to use MSVC's isatty if using MSVC
  # ---------------------------------------------------------------------------
  if(MSVC)
    foreach(_fio "${root}/include/fio.h" "${root}/src/cspice/fio.h")
      file(READ "${_fio}" _contents)
      string(REPLACE "extern int isatty(int);"
                     "#ifndef _WIN32\nextern int isatty(int);\n#endif"
                     _fixed "${_contents}")
      file(WRITE "${_fio}" "${_fixed}")
    endforeach()
  endif()

  # ---------------------------------------------------------------------------
  # EMSCRIPTEN: sprintf fort.* format strings
  # ---------------------------------------------------------------------------
  if(DEFINED EMSCRIPTEN)
    message(STATUS "Patching CSPICE sprintf fort.* format strings for Emscripten.")
    set(_endfile_c "${root}/src/cspice/endfile.c")
    set(_open_c    "${root}/src/cspice/open.c")

    # endfile.c: sprintf(nbuf,"fort.%ld",a->aunit);
    cspice_patch_string_in_file("${_endfile_c}"
      "sprintf(nbuf,\"fort.%ld\",a->aunit);"
      "sprintf(nbuf,\"fort.%d\",(int)a->aunit);")

    # open.c: sprintf(buf, "fort.%ld", a->ounit);
    cspice_patch_string_in_file("${_open_c}"
      "sprintf(buf, \"fort.%ld\", a->ounit);"
      "sprintf(buf, \"fort.%d\", (int)a->ounit);")

    # open.c: (void) sprintf(nbuf,"fort.%ld",n);
    cspice_patch_string_in_file("${_open_c}"
      "(void) sprintf(nbuf,\"fort.%ld\",n);"
      "(void) sprintf(nbuf,\"fort.%d\",(int)n);")
  endif()

  # ---------------------------------------------------------------------------
  # EMSCRIPTEN: fileno() prototype fix (err.c + s_paus.c)
  # ---------------------------------------------------------------------------
  if(DEFINED EMSCRIPTEN)
    message(STATUS "Patching CSPICE fileno() includes for Emscripten.")
    # Insert Emscripten-only includes immediately after '#include "f2c.h"'
    set(_fileno_insert
"#include \"f2c.h\"

#ifdef __EMSCRIPTEN__
  #ifndef _POSIX_C_SOURCE
  #define _POSIX_C_SOURCE 200809L
  #endif
  #include <stdio.h>  /* FILE, fileno */
  #include <unistd.h> /* isatty (if needed) */
  extern int fileno(FILE *);
  extern int isatty(int);
#endif
 ")
    cspice_patch_string_in_file("${root}/src/cspice/err.c"
      "#include \"f2c.h\"" "${_fileno_insert}")
    cspice_patch_string_in_file("${root}/src/cspice/s_paus.c"
      "#include \"f2c.h\"" "${_fileno_insert}")
  endif()

  # ---------------------------------------------------------------------------
  # f2c prototype fixes (all platforms)
  # ---------------------------------------------------------------------------
  message(STATUS "Patching CSPICE f2c prototypes...")
  cspice_fix_f2c_symbol("${root}" "s_copy"
    "/* Subroutine */ void s_copy" "/\\* Subroutine \\*/ int s_copy")
  cspice_fix_f2c_symbol("${root}" "s_cat"
    "/* Subroutine */ void s_cat" "/\\* Subroutine \\*/ int s_cat")
  cspice_fix_f2c_symbol("${root}" "zzsetnnread_"
    "void zzsetnnread_" "int zzsetnnread_")
endfunction()

# -----------------------------------------------------------------------------
# Whether to apply the patches above.
#
# Defaults to ON to preserve existing behavior for every consumer. Turn it OFF
# (e.g. when supplying an already-patched CSPICE_SRC) via either:
#   * CMake:       -DCSPICE_PATCH_SOURCE=OFF
#   * environment: CSPICE_PATCH_SOURCE=OFF (or 0/NO/FALSE)
# The environment variable, when set, overrides the CMake option/cache value.
# -----------------------------------------------------------------------------
option(CSPICE_PATCH_SOURCE "Apply SpiceyPy-specific patches to the CSPICE source" ON)
if(DEFINED ENV{CSPICE_PATCH_SOURCE})
  set(CSPICE_PATCH_SOURCE "$ENV{CSPICE_PATCH_SOURCE}")
  message(STATUS "CSPICE_PATCH_SOURCE overridden by environment: ${CSPICE_PATCH_SOURCE}")
endif()

# -----------------------------------------------------------------------------
# Determine the pristine CSPICE source: either a user-provided local tree
# (CSPICE_SRC) or a download from NAIF.
# -----------------------------------------------------------------------------
if(DEFINED ENV{CSPICE_SRC})
  set(CSPICE_SRC_PRISTINE "$ENV{CSPICE_SRC}")
  message(STATUS "Using local CSPICE source from: ${CSPICE_SRC_PRISTINE}")
else()
  # ---------------------------------------------------------------------------
  # Select the archive URL based on OS and architecture.
  # ---------------------------------------------------------------------------
  if(WIN32)
    set(CSPICE_ARCHIVE_URL "https://naif.jpl.nasa.gov/pub/naif/misc/toolkit_${CSPICE_VERSION}/C/PC_Windows_VisualC_64bit/packages/cspice.zip")
    set(CSPICE_ARCHIVE_HASH "SHA256=98d60b814b412fa55294aeaaeb7dab46d849cc87a8b709ffe835d08de17625dc")
  elseif(APPLE)
    if(CMAKE_SYSTEM_PROCESSOR STREQUAL "arm64")
      set(CSPICE_ARCHIVE_URL "https://naif.jpl.nasa.gov/pub/naif/misc/toolkit_${CSPICE_VERSION}/C/MacM1_OSX_clang_64bit/packages/cspice.tar.Z")
      set(CSPICE_ARCHIVE_HASH "SHA256=0deae048443e11ca4d093cac651d9785d4f2594631a183d85a3d58949f4d0aa9")
    else()
      set(CSPICE_ARCHIVE_URL "https://naif.jpl.nasa.gov/pub/naif/misc/toolkit_${CSPICE_VERSION}/C/MacIntel_OSX_AppleC_64bit/packages/cspice.tar.Z")
      set(CSPICE_ARCHIVE_HASH "SHA256=6f4980445fee4d363dbce6f571819f4a248358d2c1bebca47e0743eedfe9935e")
    endif()
  elseif(DEFINED EMSCRIPTEN)
    set(CSPICE_ARCHIVE_URL "https://naif.jpl.nasa.gov/pub/naif/misc/toolkit_${CSPICE_VERSION}/C/PC_Linux_GCC_32bit/packages/cspice.tar.Z")
    set(CSPICE_ARCHIVE_HASH "SHA256=33d75cd94acf6546e53d7ebc4e7d3d6d42ac27c83cb0d8f04c91a8b50c1149e3")
  else() # Assuming Linux or similar UNIX
    set(CSPICE_ARCHIVE_URL "https://naif.jpl.nasa.gov/pub/naif/misc/toolkit_${CSPICE_VERSION}/C/PC_Linux_GCC_64bit/packages/cspice.tar.Z")
    set(CSPICE_ARCHIVE_HASH "SHA256=60a95b51a6472f1afe7e40d77ebdee43c12bb5b8823676ccc74692ddfede06ce")
  endif()
  message(STATUS "No local CSPICE source provided. Downloading from: ${CSPICE_ARCHIVE_URL}")
  FetchContent_Declare(
    cspice_src
    URL ${CSPICE_ARCHIVE_URL}
    URL_HASH ${CSPICE_ARCHIVE_HASH}
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    SOURCE_DIR ${CMAKE_BINARY_DIR}/cspice-download
  )
  FetchContent_MakeAvailable(cspice_src)
  set(CSPICE_SRC_PRISTINE ${cspice_src_SOURCE_DIR})
endif()

# -----------------------------------------------------------------------------
# Prepare a working copy of the source in the build tree and patch *that copy*,
# so the pristine source (especially a user-provided CSPICE_SRC) is never
# modified. Guarded by a single marker so the copy + patch runs exactly once per
# build tree; starting from a fresh copy makes every patch idempotent by
# construction (notably the non-idempotent MSVC isatty guard).
# -----------------------------------------------------------------------------
set(CSPICE_SOURCE_ROOT ${CMAKE_BINARY_DIR}/cspice-src)
set(CSPICE_PREPARED_MARKER "${CMAKE_CURRENT_BINARY_DIR}/cspice_source_prepared")

if(NOT EXISTS "${CSPICE_PREPARED_MARKER}")
  message(STATUS "Preparing CSPICE working copy at: ${CSPICE_SOURCE_ROOT}")
  file(REMOVE_RECURSE "${CSPICE_SOURCE_ROOT}")
  file(COPY "${CSPICE_SRC_PRISTINE}/" DESTINATION "${CSPICE_SOURCE_ROOT}")

  if(CSPICE_PATCH_SOURCE)
    cspice_apply_patches("${CSPICE_SOURCE_ROOT}")
  else()
    message(STATUS "CSPICE_PATCH_SOURCE is OFF; skipping CSPICE source patches.")
  endif()

  file(WRITE "${CSPICE_PREPARED_MARKER}" "prepared")
else()
  message(STATUS "CSPICE working copy already prepared, skipping copy + patch.")
endif()

# -----------------------------------------------------------------------------
# Global MSVC Flags
# -----------------------------------------------------------------------------
if(MSVC)
  # Enable automatic export of all symbols for all Windows DLLs
  set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON)
endif()


# -----------------------------------------------------------------------------
# CSPICE
# -----------------------------------------------------------------------------

# Locate the CSPICE source files.
file(GLOB CSPICE_SOURCES
  ${CSPICE_SOURCE_ROOT}/src/cspice/*.c
)

# Create the shared library target.
add_library(cspice SHARED ${CSPICE_SOURCES})

target_include_directories(cspice PUBLIC
  $<BUILD_INTERFACE:${CSPICE_SOURCE_ROOT}/include>
  $<INSTALL_INTERFACE:include/cspice>
)

# Configure using the custom command that handles the platform specific stuff
configure_platform(cspice)

# Add the so version as a symlink so libcspice.##.0.0, libcspice.##, and libcspice are made
set_target_properties(cspice PROPERTIES
  VERSION        ${PROJECT_VERSION}    # “current_version” (real file)
  SOVERSION      ${CSPICE_VERSION_INT} # “compatibility_version” (soname)
  OUTPUT_NAME    cspice   # ensures base name is libcspice*.dylib
  INSTALL_NAME_DIR "@rpath"
)

# Create a namespaced alias so downstream can do “cspice::cspice”
add_library(CSPICE::cspice ALIAS cspice)

# Installs for cspice headers/shared library etc
install(TARGETS cspice
    EXPORT CSPICETargets
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}       # Windows .dll TODO WHY again is this bindir?
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}       # Unix .so / macOS .dylib
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}       # static / import libs
    PUBLIC_HEADER DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/cspice
)

# Install the header directory once
install(DIRECTORY ${CSPICE_SOURCE_ROOT}/include/ DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/cspice)


# -----------------------------------------------------------------------------
# CSUPPORT
# -----------------------------------------------------------------------------
if(BUILD_EXECUTABLES AND NOT DEFINED EMSCRIPTEN)
  # Locate the CSUPPORT source files.
  file(GLOB CSUPPORT_SOURCES
    ${CSPICE_SOURCE_ROOT}/src/csupport/*.c
  )

  # Create the shared library target.
  add_library(csupport SHARED ${CSUPPORT_SOURCES})
  target_link_libraries(csupport PRIVATE CSPICE::cspice)
  target_include_directories(csupport PUBLIC
    $<BUILD_INTERFACE:${CSPICE_SOURCE_ROOT}/include>
    $<INSTALL_INTERFACE:include/cspice>
  )

  # Configure using the custom command that handles the platform specific stuff
  configure_platform(csupport)

  # Add the so version as a symlink so libcsupport.##.0.0, libcsupport.##, and libcsupport are made
  set_target_properties(csupport PROPERTIES
    VERSION        ${PROJECT_VERSION}    # “current_version” (real file)
    SOVERSION      ${CSPICE_VERSION_INT} # “compatibility_version” (soname)
    OUTPUT_NAME    csupport  # ensures base name is libcspice*.dylib
    INSTALL_NAME_DIR "@rpath"
  )

  # Create a namespaced alias so downstream can do “cspice::csupport”
  add_library(CSPICE::csupport ALIAS csupport)

  # Installs for cspice headers/shared library etc
  install(TARGETS csupport
      EXPORT CSPICETargets
      RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}       # Windows
      LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}       # Unix .so / macOS .dylib
      ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}       # static / import libs
  )
endif()
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
    PATH_VARS CSPICE_VERSION   # <- tell CMake to substitute @CSPICE_VERSION@
)

# Export a CMake package config so others can do find_package(CSPICE)
install(EXPORT CSPICETargets
  FILE   cspiceTargets.cmake
  NAMESPACE CSPICE::
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/cspice
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
  set_target_properties(test_cspice PROPERTIES
      C_STANDARD 11
      C_STANDARD_REQUIRED ON
      C_EXTENSIONS OFF
  )
  target_link_libraries(test_cspice PRIVATE CSPICE::cspice)
  if(DEFINED EMSCRIPTEN)
    target_compile_options(test_cspice PRIVATE -fPIC)
    target_link_options(test_cspice PRIVATE -sMAIN_MODULE=2 -sINITIAL_MEMORY=134217728 )
    add_test(NAME cspice_test COMMAND node ${CMAKE_CURRENT_BINARY_DIR}/test_cspice.js)
  else()
    add_test(NAME cspice_test COMMAND test_cspice WORKING_DIRECTORY ${CMAKE_BINARY_DIR})
  endif()
endif()

# --------------------------------------------------------------------------------------
# Optional Build Executables, only build & register tests if BUILD_EXECUTABLES is ON
# --------------------------------------------------------------------------------------
set(CSPICE_EXECUTABLE_DIRS
    "${CSPICE_SOURCE_ROOT}/src/brief_c"
    "${CSPICE_SOURCE_ROOT}/src/chrnos_c"
    "${CSPICE_SOURCE_ROOT}/src/ckbref_c"
    "${CSPICE_SOURCE_ROOT}/src/commnt_c"
    "${CSPICE_SOURCE_ROOT}/src/dskbrief_c"
    "${CSPICE_SOURCE_ROOT}/src/dskexp_c"
    "${CSPICE_SOURCE_ROOT}/src/frmdif_c"
    "${CSPICE_SOURCE_ROOT}/src/inspkt_c"
    "${CSPICE_SOURCE_ROOT}/src/mkdsk_c"
    "${CSPICE_SOURCE_ROOT}/src/mkspk_c"
    "${CSPICE_SOURCE_ROOT}/src/msopck_c"
    "${CSPICE_SOURCE_ROOT}/src/spacit_c"
    "${CSPICE_SOURCE_ROOT}/src/spkdif_c"
    "${CSPICE_SOURCE_ROOT}/src/spkmrg_c"
    "${CSPICE_SOURCE_ROOT}/src/tobin_c"
    "${CSPICE_SOURCE_ROOT}/src/toxfr_c"
    "${CSPICE_SOURCE_ROOT}/src/versn_c"
)


if(BUILD_EXECUTABLES AND NOT DEFINED EMSCRIPTEN)
  foreach(exec_dir IN LISTS CSPICE_EXECUTABLE_DIRS)
    # Find the .pgm file (the real program name comes from this)
    file(GLOB pgm_files CONFIGURE_DEPENDS "${exec_dir}/*.pgm")
    set_source_files_properties(${pgm_files} PROPERTIES LANGUAGE C)

    if(NOT pgm_files)
      message(STATUS "Skipping ${exec_dir}: no .pgm file found")
      continue()
    endif()

    list(LENGTH pgm_files pgm_count)
    if(pgm_count GREATER 1)
      message(FATAL_ERROR "More than one .pgm file in ${exec_dir}, script assumes only one")
    endif()

    get_filename_component(exec_name "${pgm_files}" NAME_WE) # basename w/o .pgm

    # Step 1: gather sources
    file(GLOB local_c_sources CONFIGURE_DEPENDS "${exec_dir}/*.c")
    file(GLOB pgm_sources CONFIGURE_DEPENDS "${exec_dir}/*.pgm")
    set_source_files_properties(${pgm_sources} PROPERTIES LANGUAGE C)

    # Object library for the local code
    add_library(${exec_name}_objs OBJECT ${local_c_sources} ${pgm_sources})
    set_target_properties(${exec_name}_objs PROPERTIES
       C_STANDARD 90
       C_STANDARD_REQUIRED       ON
       C_EXTENSIONS              ON
       POSITION_INDEPENDENT_CODE ON
       VERSION                   ${PROJECT_VERSION}
    )
    target_include_directories(${exec_name}_objs PRIVATE ${CSPICE_SOURCE_ROOT}/include)

    # Step 2: main.x object
    set(main_x "${exec_dir}/main.x")
    set_source_files_properties(${main_x} PROPERTIES LANGUAGE C)

    add_library(${exec_name}_main OBJECT ${main_x})
    set_target_properties(${exec_name}_main PROPERTIES
       C_STANDARD 90
       C_STANDARD_REQUIRED       ON
       C_EXTENSIONS              ON
       POSITION_INDEPENDENT_CODE ON
       VERSION                   ${PROJECT_VERSION}
    )
    target_include_directories(${exec_name}_main PRIVATE ${CSPICE_SOURCE_ROOT}/include)

    # Step 3: link everything into an executable
    add_executable(${exec_name}
      $<TARGET_OBJECTS:${exec_name}_objs>
      $<TARGET_OBJECTS:${exec_name}_main>
    )
    set_target_properties(${exec_name} PROPERTIES
       C_STANDARD 90
       C_STANDARD_REQUIRED       ON
       C_EXTENSIONS              ON
       POSITION_INDEPENDENT_CODE ON
       VERSION                   ${PROJECT_VERSION}
    )
    target_link_libraries(${exec_name} PRIVATE CSPICE::cspice CSPICE::csupport)
    if(NOT MSVC AND NOT DEFINED EMSCRIPTEN)
      target_link_libraries(${exec_name} PRIVATE m)
    endif()
    if(MINGW)
      target_link_options(${exec_name} PRIVATE -Wl,--allow-multiple-definition)
    elseif(MSVC)
      target_link_options(${exec_name} PRIVATE "/FORCE:MULTIPLE")
    endif()

    # # Install and export so downstream can use cspice::chronos, etc.
    install(TARGETS ${exec_name}
      EXPORT CSPICETargets
      RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    )

  endforeach()
endif()
