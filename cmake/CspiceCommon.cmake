function(configure_platform target)
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
      -Wno-implicit-function-declaration 
      -Wno-shift-op-parentheses
      -Wno-deprecated-non-prototype
      -Wno-parentheses
      -Wno-int-conversion)
    # for the shared library
    if(DEFINED CSPICE_EMSCRIPTEN_SIDE_MODULE_1)
      target_link_options(${target} PRIVATE -shared -Wl
        "-sSIDE_MODULE=1"
        "-sEXPORT_ALL=1"
        "-sINITIAL_MEMORY=134217728"   # 128 MB
        "-sALLOW_MEMORY_GROWTH=1"
        "-sMEMORY_GROWTH_GEOMETRIC_STEP=1.15"
        "-sNO_EXIT_RUNTIME=1"
        "-sWARN_ON_UNDEFINED_SYMBOLS=1"
        "-sFORCE_FILESYSTEM=1"
        "-sRETAIN_COMPILER_SETTINGS=1"
        "-O2"
      )
    else()
      target_link_options(${target} PRIVATE -shared -Wl
        "-sSIDE_MODULE=2"
        "-sEXPORTED_FUNCTIONS=@${CMAKE_CURRENT_SOURCE_DIR}/cspice_exports.json"
        "-sINITIAL_MEMORY=134217728"   # 128 MB
        "-sALLOW_MEMORY_GROWTH=1"
        "-sMEMORY_GROWTH_GEOMETRIC_STEP=1.15"
        "-sNO_EXIT_RUNTIME=1"
        "-sWARN_ON_UNDEFINED_SYMBOLS=1"
        "-sFORCE_FILESYSTEM=1"
        "-sRETAIN_COMPILER_SETTINGS=1"
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
    # -----------------------------------------------------------------------------
    # Windows-specific configuration: Use a .def file for symbol exports.
    # Can replace with set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS 1)
    # -----------------------------------------------------------------------------
    message(STATUS "Configuring ${target} for Windows MSVC")
    target_compile_definitions(${target} PRIVATE _COMPLEX_DEFINED MSDOS OMIT_BLANK_CC NON_ANSI_STDIO)
    target_compile_options(${target} PRIVATE /nologo)
    set(CSPICE_DEF_FILE "${CMAKE_CURRENT_SOURCE_DIR}/cspice.def")
    if(EXISTS ${CSPICE_DEF_FILE})
      message(STATUS "Using ${target} .def file: ${CSPICE_DEF_FILE}")
      target_link_options(${target} PRIVATE "/DEF:${CSPICE_DEF_FILE}")
    else()
      message(WARNING "CSPICE .def file not found: ${CSPICE_DEF_FILE}")
    endif()
  elseif(WIN32)
    message(STATUS "Configuring ${target} for Windows MinGW/ETC")
    target_compile_definitions(${target} PRIVATE _COMPLEX_DEFINED MSDOS OMIT_BLANK_CC NON_ANSI_STDIO)
  endif()
endfunction()