# -----------------------------------------------------------------------------
# Patching helpers
#
# These operate on a *working copy* of the CSPICE source inside the build tree
# (prepared in the top-level CMakeLists.txt). We never modify a user-provided
# CSPICE_SRC tree in place.
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


function(add_export_size target)

  if(CSPICE_EXPORT_SIZE STREQUAL "FULL")
      set(CSPICE_FLAVOR_ID 0)
  elseif(CSPICE_EXPORT_SIZE STREQUAL "MEDIUM")
      set(CSPICE_FLAVOR_ID 1)
  elseif(CSPICE_EXPORT_SIZE STREQUAL "VLITE")
      set(CSPICE_FLAVOR_ID 2)
  else()
      set(CSPICE_FLAVOR_ID 0)
  endif()

  # Generate header
  configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/cspice_flavor.h.in
    ${CMAKE_CURRENT_BINARY_DIR}/cspice_flavor.h
    @ONLY
  )
  
  # Add C file
  target_sources(${target} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/cspice_flavor.c)
  
  # Ensure build+install paths include the generated header
  target_include_directories(${target} PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}>
    $<INSTALL_INTERFACE:include/${target}>
  )
  
  install(FILES ${CMAKE_CURRENT_BINARY_DIR}/cspice_flavor.h
          DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/cspice)
  
  message(STATUS "Set CSPICE_FLAVOR_ID inside ${target} to ${CSPICE_FLAVOR_ID}")

endfunction(add_export_size)


function(configure_platform target)

  # if Emscripten, define which size of cspice to build
  if(DEFINED EMSCRIPTEN)
    set(CSPICE_EXPORT_SIZE "FULL" CACHE STRING "For Emscripten builds, set this to which size of cspice you wish to build [FULL, MEDIUM, VLITE]")
    set_property(CACHE CSPICE_EXPORT_SIZE PROPERTY STRINGS "FULL;MEDIUM;VLITE")
    message(STATUS "Going to Build cspice version ${CSPICE_EXPORT_SIZE}")
    # parse what to do with the CSPICE_EXPORT_SIZE
    if(CSPICE_EXPORT_SIZE STREQUAL "FULL")
      set(CSPICE_INITIAL_MEMORY "128MB" CACHE STRING "Initial Memory Size for CSPICE ")
      set(CSPICE_EXPORTED_FUNCTIONS "@${CMAKE_CURRENT_SOURCE_DIR}/cspice_exports_full.json" CACHE STRING "Path to export json")
  
    elseif(CSPICE_EXPORT_SIZE STREQUAL "MEDIUM")
      set(CSPICE_INITIAL_MEMORY "64MB" CACHE STRING "Initial Memory Size for CSPICE ")
      set(CSPICE_EXPORTED_FUNCTIONS "@${CMAKE_CURRENT_SOURCE_DIR}/cspice_exports_medium.json" CACHE STRING "Path to export json")
  
    elseif(CSPICE_EXPORT_SIZE STREQUAL "VLITE")
      set(CSPICE_INITIAL_MEMORY "16MB" CACHE STRING "Initial Memory Size for CSPICE ")
      set(CSPICE_EXPORTED_FUNCTIONS "@${CMAKE_CURRENT_SOURCE_DIR}/cspice_exports_vlite.json" CACHE STRING "Path to export json")
  
    else()
      message(WARNING "Unknown CSPICE_EXPORT_SIZE choice: ${CSPICE_EXPORT_SIZE}")
    endif()
    # and add the export size
    add_export_size(${target})
  endif()
  # -----------------------------------------------------------------------------
  # Additional compile definitions, flags, or versioning.
  # -----------------------------------------------------------------------------
  target_compile_definitions(${target} PRIVATE -DNDEBUG)
  set_target_properties(${target} PROPERTIES
      C_STANDARD 90
      C_STANDARD_REQUIRED       ON
      C_EXTENSIONS              ON  
      POSITION_INDEPENDENT_CODE ON
      VERSION                   ${PROJECT_VERSION}
      # No SOVERSION: CSPICE doesn’t guarantee ABI compatibility
  )

  #-------------------------------------------------------------------------------
  # Link math library
  #-------------------------------------------------------------------------------
  if(NOT MSVC AND NOT DEFINED EMSCRIPTEN)
    target_link_libraries(${target} PRIVATE m)
  endif()


  if(DEFINED EMSCRIPTEN)
    message(STATUS "Configuring ${target} for Emscripten")
    set_target_properties(${target} PROPERTIES SUFFIX ".wasm")
    target_compile_options(${target} PRIVATE 
      -ansi 
      -Werror=implicit-function-declaration 
      -Werror=int-conversion
      -Werror=incompatible-pointer-types
      -Werror=return-type
      -Wno-shift-op-parentheses
      -Wno-deprecated-non-prototype
      -Wno-parentheses)
    # for the shared library
    if(DEFINED CSPICE_EMSCRIPTEN_SIDE_MODULE_1 OR ${target} STREQUAL "csupport")
      target_link_options(${target} PRIVATE -shared -Wl
        "-sSIDE_MODULE=1"
        "-sEXPORT_ALL=1"
        "-sSTACK_SIZE=8388608" # 8 MB
        "-sINITIAL_MEMORY=134217728"   # 128 MB
        "-sALLOW_MEMORY_GROWTH=1"
        "-sMEMORY_GROWTH_GEOMETRIC_STEP=1.15"
        "-sNO_EXIT_RUNTIME=1"
        "-sWARN_ON_UNDEFINED_SYMBOLS=1"
        "-sFORCE_FILESYSTEM=1"
        "-sRETAIN_COMPILER_SETTINGS=1"
        "-sSAFE_HEAP=1"
        "-O2"
      )
    else()
      target_link_options(${target} PRIVATE -shared -Wl
        "-sSIDE_MODULE=2"
        "-sEXPORTED_FUNCTIONS=${CSPICE_EXPORTED_FUNCTIONS}"
        "-sSTACK_SIZE=8388608" # 8 MB
        "-sINITIAL_MEMORY=${CSPICE_INITIAL_MEMORY}"
        "-sALLOW_MEMORY_GROWTH=1"
        "-sMEMORY_GROWTH_GEOMETRIC_STEP=1.15"
        "-sNO_EXIT_RUNTIME=1"
        "-sWARN_ON_UNDEFINED_SYMBOLS=1"
        "-sFORCE_FILESYSTEM=1"
        "-sRETAIN_COMPILER_SETTINGS=1"
        "-sSAFE_HEAP=1"
        "-O2"
      )
    endif()
    set_property(TARGET ${target} PROPERTY LINK_LIBRARIES "")
  elseif(APPLE)
    message(STATUS "Configuring ${target} for Apple")
    target_compile_options(${target} PRIVATE 
      -ansi
      -DVOID=void  
      -UKR_headers 
      -Wimplicit-int
      -Wimplicit-function-declaration
      -Wno-deprecated-non-prototype
      -Wno-shift-op-parentheses
      -Wno-parentheses
    )
    target_link_options(${target} PRIVATE -dynamiclib -install_name "@rpath/lib${target}.dylib")
  elseif(UNIX)
    message(STATUS "Configuring ${target} for UNIX")
    target_compile_options(${target} PRIVATE 
      -ansi
      -DVOID=void  
      -UKR_headers 
      -Wimplicit-int
      -Wimplicit-function-declaration
      -Wno-deprecated-non-prototype
      -Wno-shift-op-parentheses
      -Wno-parentheses
    )
    target_link_options(${target} PRIVATE -shared -Wl,-soname,lib${target}.so)
  elseif(MSVC)
    message(STATUS "Configuring ${target} for Windows MSVC")
    target_compile_definitions(${target} PRIVATE _COMPLEX_DEFINED MSDOS OMIT_BLANK_CC NON_ANSI_STDIO)
    target_compile_options(${target} PRIVATE /nologo)
  elseif(WIN32)
    message(STATUS "Configuring ${target} for Windows MinGW/ETC")
    target_compile_definitions(${target} PRIVATE _COMPLEX_DEFINED MSDOS OMIT_BLANK_CC NON_ANSI_STDIO)
  endif()
endfunction(configure_platform)



