cmake_minimum_required(VERSION 3.24)

#-------------------------------------------------------------------------------
# 1) Project declaration with version and language
#-------------------------------------------------------------------------------
project(cspice
    VERSION 67.0.0
    DESCRIPTION "NAIF CSPICE Toolkit"
    LANGUAGES C
)

# -----------------------------------------------------------------------------
# Define the version of CSPICE.
# -----------------------------------------------------------------------------
set(CSPICE_VERSION "N0067")

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

  #-------------------------------------------------------------------------------
  # Patch to use MSVC's isatty if using MSVC
  #-------------------------------------------------------------------------------
  if (MSVC)
    set(FIO_H1 "${CSPICE_SOURCE_ROOT}/include/fio.h")
  
    file(READ "${FIO_H1}" FIO_H1_CONTENTS)
  
    string(REPLACE "extern int isatty(int);" 
                 "#ifndef _WIN32\nextern int isatty(int);\n#endif"
                 FIO_H1_CONTENTS_FIXED 
                 "${FIO_H1_CONTENTS}")
    
    file(WRITE "${FIO_H1}" "${FIO_H1_CONTENTS_FIXED}")
  
    # If it's worth doing once, it's worth doing twice
  
    set(FIO_H2 "${CSPICE_SOURCE_ROOT}/src/cspice/fio.h")
    
    file(READ "${FIO_H2}" FIO_H2_CONTENTS)
  
    string(REPLACE "extern int isatty(int);" 
                 "#ifndef _WIN32\nextern int isatty(int);\n#endif"
                 FIO_H2_CONTENTS_FIXED 
                 "${FIO_H2_CONTENTS}")
  
    file(WRITE "${FIO_H2}" "${FIO_H2_CONTENTS_FIXED}")
  endif()

  # -------------------------------------------------------------------
  # Function to patch bad f2c prototypes inside specific CSPICE .c files
  # -------------------------------------------------------------------
  function(fix_f2c_prototypes file_path pattern replacement)
      file(READ "${file_path}" FILE_CONTENTS)
      string(REGEX REPLACE "${pattern}" "${replacement}" FILE_CONTENTS_FIXED "${FILE_CONTENTS}")
  
      if(NOT "${FILE_CONTENTS}" STREQUAL "${FILE_CONTENTS_FIXED}")
          message(STATUS "Patched prototypes in ${file_path}")
          file(WRITE "${file_path}" "${FILE_CONTENTS_FIXED}")
      else()
          message(STATUS "No changes needed in ${file_path}")
      endif()
  endfunction()
  
  # -------------------------------------------------------------------
  # Apply prototype fixes only once per build tree
  # -------------------------------------------------------------------
  set(CSPICE_PATCH_MARKER "${CMAKE_CURRENT_BINARY_DIR}/cspice_prototypes_patched")
  
  if(NOT EXISTS ${CSPICE_PATCH_MARKER})
      message(STATUS "Patching CSPICE f2c prototypes...")
  
      # ana.c: s_copy should be void
      fix_f2c_prototypes(
          "${CSPICE_SOURCE_ROOT}/src/cspice/ana.c"
          "/\\* Subroutine \\*/ int s_copy"
          "/* Subroutine */ void s_copy"
      )
  
      # ckmeta.c: s_cat should be void
      fix_f2c_prototypes(
          "${CSPICE_SOURCE_ROOT}/src/cspice/ckmeta.c"
          "/\\* Subroutine \\*/ int s_cat"
          "/* Subroutine */ void s_cat"
      )
  
      # rdker.c: zzsetnnread_ should be void
      fix_f2c_prototypes(
          "${CSPICE_SOURCE_ROOT}/src/cspice/rdker.c"
          "int zzsetnnread_"
          "void zzsetnnread_"
      )
  
      # Drop a marker so we don't patch twice
      file(WRITE ${CSPICE_PATCH_MARKER} "patched")
  else()
      message(STATUS "CSPICE prototypes already patched, skipping")
  endif()

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
set_target_properties(cspice PROPERTIES
    C_STANDARD 90
    C_STANDARD_REQUIRED       ON
    C_EXTENSIONS              ON  
    POSITION_INDEPENDENT_CODE ON
    VERSION                   ${PROJECT_VERSION}
    # No SOVERSION: CSPICE doesn’t guarantee ABI compatibility
)

# -----------------------------------------------------------------------------
# Platform-specific compile and link flags.
# -----------------------------------------------------------------------------

# Common compile options for Unix-like systems (macOS + Linux/BSD)
if(APPLE OR UNIX)
  target_compile_options(cspice PRIVATE 
    -ansi
    -DVOID=void  
    -UKR_headers 
    -Wimplicit-int
  )
endif()

if(APPLE)
  target_link_options(cspice PRIVATE
                      -dynamiclib
                      -install_name "@rpath/libcspice.dylib")
elseif(UNIX) # Linux, BSD, etc. (but not macOS)
  target_link_options(cspice PRIVATE
                      -shared
                      -Wl,-soname,libcspice.so)
endif()

# -----------------------------------------------------------------------------
# Windows-specific configuration: Use a .def file for symbol exports.
# -----------------------------------------------------------------------------
if(MSVC)
  target_compile_definitions(cspice PRIVATE _COMPLEX_DEFINED MSDOS OMIT_BLANK_CC NON_ANSI_STDIO)
  target_compile_options(cspice PRIVATE /nologo)
  set(CSPICE_DEF_FILE "${CMAKE_CURRENT_SOURCE_DIR}/cspice.def")
  if(EXISTS ${CSPICE_DEF_FILE})
    message(STATUS "Using CSPICE .def file: ${CSPICE_DEF_FILE}")
    target_link_options(cspice PRIVATE "/DEF:${CSPICE_DEF_FILE}")
  else()
    message(WARNING "CSPICE .def file not found: ${CSPICE_DEF_FILE}")
  endif()
elseif(WIN32)
  # MinGW/other Windows GCC
  target_compile_definitions(cspice PRIVATE _COMPLEX_DEFINED MSDOS OMIT_BLANK_CC NON_ANSI_STDIO)
endif()


#-------------------------------------------------------------------------------
# Link math library
#-------------------------------------------------------------------------------
if(NOT MSVC)
  target_link_libraries(cspice PRIVATE m)
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
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}       # Windows .dll
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}       # Unix .so / macOS .dylib
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}       # static / import libs
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
  target_link_libraries(test_cspice PRIVATE cspice)
  set_target_properties(test_cspice PROPERTIES
      C_STANDARD 11
      C_STANDARD_REQUIRED ON
      C_EXTENSIONS OFF
  )
  add_test(NAME cspice_test
           COMMAND test_cspice
           WORKING_DIRECTORY ${CMAKE_BINARY_DIR})
endif()
