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

# Prepend an explicit `int` return type to a bare K&R function definition.
# <line> is the definition line exactly as it appears (including any leading
# indentation). The match is anchored on the preceding newline so we never
# hit a longer name (e.g. `ne_d` when patching `e_d`) or an already-typed
# prototype/declaration elsewhere in the file.
function(cspice_fix_implicit_int file line)
  file(READ "${file}" _contents)
  string(STRIP "${line}" _bare)
  string(REPLACE "\n${line}" "\nint ${_bare}" _fixed "${_contents}")
  if(NOT "${_contents}" STREQUAL "${_fixed}")
    message(STATUS "Patched implicit-int (${_bare}) in ${file}")
    file(WRITE "${file}" "${_fixed}")
  else()
    message(WARNING "CSPICE implicit-int patch: not found in ${file}: ${line}")
  endif()
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
  # sprintf "fort.%ld" format strings (all platforms). ftnint is int here, so
  # "%ld" is a type mismatch (-Wformat); use "%d" with an explicit (int) cast.
  # ---------------------------------------------------------------------------
  message(STATUS "Patching CSPICE sprintf fort.* format strings.")
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

  # ---------------------------------------------------------------------------
  # fileno()/isatty() prototype fix (err.c + s_paus.c), all gcc/clang builds.
  # These POSIX functions are hidden under -ansi (__STRICT_ANSI__), producing
  # -Wimplicit-function-declaration (a hard error under C23 / GCC 14). Declare
  # them explicitly right after f2c.h; harmless where already visible. Skipped
  # on Windows (MSVC/MinGW use _fileno and don't add -ansi).
  # ---------------------------------------------------------------------------
  if(NOT WIN32)
    message(STATUS "Patching CSPICE fileno()/isatty() prototypes.")
    set(_fileno_insert
"#include \"f2c.h\"

#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#include <stdio.h>  /* FILE, fileno */
#include <unistd.h> /* isatty */
extern int fileno(FILE *);
extern int isatty(int);
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

  # ---------------------------------------------------------------------------
  # libf2c implicit-int return types (all platforms). These f2c runtime
  # routines define functions without the (int) return type. Modern compilers
  # warn (-Wimplicit-int) and C23 / GCC 14 make it a hard error. Prepend int.
  # ---------------------------------------------------------------------------
  message(STATUS "Patching CSPICE libf2c implicit-int definitions...")
  set(_cs "${root}/src/cspice")
  cspice_fix_implicit_int("${_cs}/dfe.c"    "y_rsk(Void)")
  cspice_fix_implicit_int("${_cs}/dfe.c"    "y_getc(Void)")
  cspice_fix_implicit_int("${_cs}/dfe.c"    "c_dfe(cilist *a)")
  cspice_fix_implicit_int("${_cs}/due.c"    "c_due(cilist *a)")
  cspice_fix_implicit_int("${_cs}/fmt.c"    "op_gen(int a, int b, int c, int d)")
  cspice_fix_implicit_int("${_cs}/fmt.c"    "ne_d(char *s, char **p)")
  cspice_fix_implicit_int("${_cs}/fmt.c"    "e_d(char *s, char **p)")
  cspice_fix_implicit_int("${_cs}/fmt.c"    "pars_f(char *s)")
  cspice_fix_implicit_int("${_cs}/fmt.c"    "type_f(int n)")
  cspice_fix_implicit_int("${_cs}/fmt.c"    "en_fio(Void)")
  cspice_fix_implicit_int("${_cs}/iio.c"    "z_getc(Void)")
  cspice_fix_implicit_int("${_cs}/iio.c"    "z_rnew(Void)")
  cspice_fix_implicit_int("${_cs}/iio.c"    "c_si(icilist *a)")
  cspice_fix_implicit_int("${_cs}/iio.c"    "z_wnew(Void)")
  cspice_fix_implicit_int("${_cs}/lread.c"  "t_getc(Void)")
  cspice_fix_implicit_int("${_cs}/lread.c"  "c_le(cilist *a)")
  cspice_fix_implicit_int("${_cs}/lread.c"  "l_read(ftnint *number, char *ptr, ftnlen len, ftnint type)")
  cspice_fix_implicit_int("${_cs}/lwrite.c" "l_write(ftnint *number, char *ptr, ftnlen len, ftnint type)")
  cspice_fix_implicit_int("${_cs}/open.c"   "   fk_open(int seq, int fmt, ftnint n)")
  cspice_fix_implicit_int("${_cs}/rdfmt.c"  "rd_ed(struct syl *p, char *ptr, ftnlen len)")
  cspice_fix_implicit_int("${_cs}/rdfmt.c"  "rd_ned(struct syl *p)")
  cspice_fix_implicit_int("${_cs}/rsfe.c"   "xrd_SL(Void)")
  cspice_fix_implicit_int("${_cs}/rsfe.c"   "x_getc(Void)")
  cspice_fix_implicit_int("${_cs}/rsfe.c"   "x_endp(Void)")
  cspice_fix_implicit_int("${_cs}/rsfe.c"   "x_rev(Void)")
  cspice_fix_implicit_int("${_cs}/rsne.c"   "x_rsne(cilist *a)")
  cspice_fix_implicit_int("${_cs}/sfe.c"    "c_sfe(cilist *a) /* check */")
  cspice_fix_implicit_int("${_cs}/sue.c"    "c_sue(cilist *a)")
  cspice_fix_implicit_int("${_cs}/uio.c"    "do_us(ftnint *number, char *ptr, ftnlen len)")
  cspice_fix_implicit_int("${_cs}/wref.c"   "wrt_E(ufloat *p, int w, int d, int e, ftnlen len)")
  cspice_fix_implicit_int("${_cs}/wref.c"   "wrt_F(ufloat *p, int w, int d, ftnlen len)")
  cspice_fix_implicit_int("${_cs}/wrtfmt.c" "wrt_L(Uint *n, int len, ftnlen sz)")
  cspice_fix_implicit_int("${_cs}/wrtfmt.c" "w_ed(struct syl *p, char *ptr, ftnlen len)")
  cspice_fix_implicit_int("${_cs}/wrtfmt.c" "w_ned(struct syl *p)")

  # rsne.c: a bare `extern t_getc(Void);` declaration also defaults to int.
  cspice_patch_string_in_file("${_cs}/rsne.c"
    "extern t_getc(Void);" "extern int t_getc(Void);")

  # ---------------------------------------------------------------------------
  # Remaining libf2c warnings (all platforms)
  # ---------------------------------------------------------------------------
  # backspace.c: consume fread()'s result (-Wunused-result). A plain (void)
  # cast does NOT suppress GCC's warn_unused_result, so assign it to a
  # discarded variable inside its own block (valid C89 declaration position).
  cspice_patch_string_in_file("${_cs}/backspace.c"
    "fread((char *)&n,sizeof(uiolen),1,f);"
    "{ size_t _nr = fread((char *)&n,sizeof(uiolen),1,f); (void)_nr; }")
  # signal_.c: cast the function pointer through a pointer-width integer before
  # narrowing to ftnint, silencing -Wpointer-to-int-cast on LP64 platforms.
  cspice_patch_string_in_file("${_cs}/signal_.c"
    "return (ftnint)signal(sig, proc);"
    "return (ftnint)(long)signal(sig, proc);")

  # ---------------------------------------------------------------------------
  # zzerror.c: GCC's -Wformat-overflow can't bound the %s appends into the
  # fixed msg_short buffer. Use snprintf() with the remaining space: behavior-
  # preserving within SPICE's limits and overflow-safe. snprintf is C99/POSIX
  # and hidden by glibc under -ansi (__STRICT_ANSI__), so declare it first to
  # avoid introducing an implicit-function-declaration.
  # ---------------------------------------------------------------------------
  cspice_patch_string_in_file("${_cs}/zzerror.c"
    "#include \"zzerror.h\""
    "#include \"zzerror.h\"

#if defined(__STRICT_ANSI__)
/* snprintf() is hidden by glibc under -ansi; declare it for the bounded
   msg_short appends below (-Wformat-overflow fix). */
extern int snprintf(char *, size_t, const char *, ...);
#endif")
  cspice_patch_string_in_file("${_cs}/zzerror.c"
    "sprintf( msg_short + strlen(msg_short),"
    "snprintf( msg_short + strlen(msg_short), sizeof(msg_short) - strlen(msg_short),")
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
    # SAFE_HEAP is debug-only and viral (forces the loading MAIN_MODULE to enable
    # it too); off by default so the shipped side module loads under stock pyodide.
    if(CSPICE_EMSCRIPTEN_SAFE_HEAP)
      message(STATUS "  CSPICE_EMSCRIPTEN_SAFE_HEAP=ON: linking ${target} with -sSAFE_HEAP=1")
      set(_safe_heap "-sSAFE_HEAP=1")
    else()
      set(_safe_heap "")
    endif()
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
        ${_safe_heap}
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
        ${_safe_heap}
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



