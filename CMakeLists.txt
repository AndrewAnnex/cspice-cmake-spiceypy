cmake_minimum_required(VERSION 3.15)
project(CSPICE C)

# -----------------------------------------------------------------------------
# Log if using scikit-build
# -----------------------------------------------------------------------------
if(SKBUILD)
  message(STATUS "The project is built using scikit-build")
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

# -----------------------------------------------------------------------------
# Option to force macOS ARM build (set to ON to build for arm64 even on x86_64 hosts).
# -----------------------------------------------------------------------------
if(APPLE)
  option(BUILD_MACOS_ARM "Force build for macOS arm64" OFF)
endif()

# -----------------------------------------------------------------------------
# Determine whether to use a local CSPICE source or to download it.
# -----------------------------------------------------------------------------
if(DEFINED ENV{CSPICE_SRC})
  set(CSPICE_SOURCE_DIR $ENV{CSPICE_SRC})
  message(STATUS "Using local CSPICE source from: $ENV{CSPICE_SRC}")
else()
  # -----------------------------------------------------------------------------
  # Select the archive URL based on OS and architecture.
  # Replace the URLs below with your actual archive locations.
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
  include(FetchContent)
  FetchContent_Declare(
    cspice
    URL ${CSPICE_ARCHIVE_URL}
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    SOURCE_DIR ${CMAKE_BINARY_DIR}/cspice-src
  )
  FetchContent_MakeAvailable(cspice)
  set(CSPICE_SOURCE_DIR ${CMAKE_BINARY_DIR}/cspice-src)
endif()

# -----------------------------------------------------------------------------
# Locate the CSPICE source files and headers.
#
# Adjust the glob pattern if your archive has a different layout.
# -----------------------------------------------------------------------------
file(GLOB_RECURSE CSPICE_SOURCES
  "${CSPICE_SOURCE_DIR}/src/cspice/*.c"
)

# -----------------------------------------------------------------------------
# Create the shared library target.
# -----------------------------------------------------------------------------
add_library(cspice SHARED ${CSPICE_SOURCES})
target_include_directories(cspice PUBLIC "${CSPICE_SOURCE_DIR}/include")

# -----------------------------------------------------------------------------
# Platform-specific compile and link flags.
#
# This section emulates the following logic from your Python script:
#
#   - For Unix systems, compile with -fPIC, -O2, and -ansi.
#   - On Darwin, use a -target flag:
#         * "-target arm64-apple-macos11" if building for macOS arm64,
#         * "-target x86_64-apple-macos10.9" otherwise.
#     Also, link with -dynamiclib and set the install_name.
#   - On Linux, add a -Wl,-soname flag and link with -lm.
# -----------------------------------------------------------------------------
if(UNIX AND NOT WIN32)
  target_compile_options(cspice PRIVATE -fPIC -O3 -ansi)
  if(APPLE)
    target_link_options(cspice PRIVATE -dynamiclib -install_name "@rpath/libcspice.so")
  else()
    # is UNIX
    target_link_options(cspice PRIVATE -Wl,-soname,libcspice.so)
    # Link with the math library.
    target_link_libraries(cspice PRIVATE m)
  endif()
endif()

# -----------------------------------------------------------------------------
# Windows-specific configuration: Use a .def file for symbol exports.
# -----------------------------------------------------------------------------
if(WIN32)
  target_compile_definitions(cspice PRIVATE _COMPLEX_DEFINED MSDOS OMIT_BLANK_CC NON_ANSI_STDIO)
  target_compile_options(cspice PRIVATE /O2 /nologo)
  set(CSPICE_DEF_FILE "${CMAKE_CURRENT_SOURCE_DIR}/cspice.def")
  if(EXISTS ${CSPICE_DEF_FILE})
    message(STATUS "Using CSPICE .def file: ${CSPICE_DEF_FILE}")
    target_link_options(cspice PRIVATE "/DEF:${CSPICE_DEF_FILE}")
  else()
    message(WARNING "CSPICE .def file not found: ${CSPICE_DEF_FILE}")
  endif()
endif()

# -----------------------------------------------------------------------------
# Additional compile definitions, flags, or versioning.
# -----------------------------------------------------------------------------
target_compile_definitions(cspice PRIVATE -DNDEBUG)
set_target_properties(cspice PROPERTIES VERSION 67 SOVERSION 1)
set_target_properties(cspice PROPERTIES POSITION_INDEPENDENT_CODE ON)

# -----------------------------------------------------------------------------
# testing 
# -----------------------------------------------------------------------------
add_executable(test_cspice test_cspice.c)
target_link_libraries(test_cspice PRIVATE cspice)

# -----------------------------------------------------------------------------
# Install if using scikit-build
# -----------------------------------------------------------------------------
if(SKBUILD)
  install(TARGETS cspice
          LIBRARY DESTINATION cspice
          RUNTIME DESTINATION cspice
          ARCHIVE DESTINATION cspice)
endif()
