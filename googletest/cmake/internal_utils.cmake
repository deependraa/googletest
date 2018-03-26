# Defines functions and macros useful for building Google Test and
# Google Mock.
#
# Note:
#
# - This file will be run twice when building Google Mock (once via
#   Google Test's CMakeLists.txt, and once via Google Mock's).
#   Therefore it shouldn't have any side effects other than defining
#   the functions and macros.
#
# - The functions/macros defined in this file may depend on Google
#   Test and Google Mock's option() definitions, and thus must be
#   called *after* the options have been defined.

# Tweaks CMake's default compiler/linker settings to suit Google Test's needs.
#
# This must be a macro(), as inside a function string() can only
# update variables in the function scope.
macro(fix_default_compiler_settings_)
  if (MSVC)
    # For MSVC, CMake sets certain flags to defaults we want to override.
    # This replacement code is taken from sample in the CMake Wiki at
    # http://www.cmake.org/Wiki/CMake_FAQ#Dynamic_Replace.
    foreach (flag_var
             CMAKE_CXX_FLAGS CMAKE_CXX_FLAGS_DEBUG CMAKE_CXX_FLAGS_RELEASE
             CMAKE_CXX_FLAGS_MINSIZEREL CMAKE_CXX_FLAGS_RELWITHDEBINFO)
      if (NOT BUILD_SHARED_LIBS AND NOT gtest_force_shared_crt)
        # When Google Test is built as a shared library, it should also use
        # shared runtime libraries.  Otherwise, it may end up with multiple
        # copies of runtime library data in different modules, resulting in
        # hard-to-find crashes. When it is built as a static library, it is
        # preferable to use CRT as static libraries, as we don't have to rely
        # on CRT DLLs being available. CMake always defaults to using shared
        # CRT libraries, so we override that default here.
        string(REPLACE "/MD" "-MT" ${flag_var} "${${flag_var}}")
      endif()

      # We prefer more strict warning checking for building Google Test.
      # Replaces /W3 with /W4 in defaults.
      string(REPLACE "/W3" "/W4" ${flag_var} "${${flag_var}}")
    endforeach()
  endif()
endmacro()

# Defines the compiler/linker flags used to build Google Test and
# Google Mock.  You can tweak these definitions to suit your need.  A
# variable's value is empty before it's explicitly assigned to.
macro(config_compiler_and_linker)
  # Note: pthreads on MinGW is not supported, even if available
  # instead, we use windows threading primitives
  unset(GTEST_HAS_PTHREAD)
  if (NOT gtest_disable_pthreads AND NOT MINGW)
    # Defines CMAKE_USE_PTHREADS_INIT and CMAKE_THREAD_LIBS_INIT.
    set(THREADS_PREFER_PTHREAD_FLAG ON)
    find_package(Threads)
    if (CMAKE_USE_PTHREADS_INIT)
      set(GTEST_HAS_PTHREAD ON)
    endif()    
  endif()
  
  unset(GTEST_HAS_LIBRT)
  find_path (LIBRT_INCLUDES time.h)
  find_library(LIBRT_LIBRARIES rt)
  if (LIBRT_INCLUDES AND LIBRT_LIBRARIES)
    set(GTEST_HAS_LIBRT ON)
  endif()

  fix_default_compiler_settings_()
  if (MSVC)
    # Newlines inside flags variables break CMake's NMake generator.
    # TODO(vladl@google.com): Add -RTCs and -RTCu to debug builds.
    set(cxx_base_flags "-GS -W4 -WX -wd4251 -wd4275 -nologo -J -Zi")
    if (MSVC_VERSION LESS 1400)  # 1400 is Visual Studio 2005
      # Suppress spurious warnings MSVC 7.1 sometimes issues.
      # Forcing value to bool.
      set(cxx_base_flags "${cxx_base_flags} -wd4800")
      # Copy constructor and assignment operator could not be generated.
      set(cxx_base_flags "${cxx_base_flags} -wd4511 -wd4512")
      # Compatibility warnings not applicable to Google Test.
      # Resolved overload was found by argument-dependent lookup.
      set(cxx_base_flags "${cxx_base_flags} -wd4675")
    endif()
    if (MSVC_VERSION LESS 1500)  # 1500 is Visual Studio 2008
      # Conditional expression is constant.
      # When compiling with /W4, we get several instances of C4127
      # (Conditional expression is constant). In our code, we disable that
      # warning on a case-by-case basis. However, on Visual Studio 2005,
      # the warning fires on std::list. Therefore on that compiler and earlier,
      # we disable the warning project-wide.
      set(cxx_base_flags "${cxx_base_flags} -wd4127")
    endif()
    if (NOT (MSVC_VERSION LESS 1700))  # 1700 is Visual Studio 2012.
      # Suppress "unreachable code" warning on VS 2012 and later.
      # http://stackoverflow.com/questions/3232669 explains the issue.
      set(cxx_base_flags "${cxx_base_flags} -wd4702")
    endif()

    set(cxx_base_flags "${cxx_base_flags} -D_UNICODE -DUNICODE -DWIN32 -D_WIN32")
    set(cxx_base_flags "${cxx_base_flags} -DSTRICT -DWIN32_LEAN_AND_MEAN")
    set(cxx_exception_flags "-EHsc -D_HAS_EXCEPTIONS=1")
    set(cxx_no_exception_flags "-EHs-c- -D_HAS_EXCEPTIONS=0")
    set(cxx_no_rtti_flags "-GR-")
  elseif (CMAKE_COMPILER_IS_GNUCXX)
    set(cxx_base_flags "-Wall -Wshadow -Werror")
    if(NOT CMAKE_CXX_COMPILER_VERSION VERSION_LESS 7.0.0)
      set(cxx_base_flags "${cxx_base_flags} -Wno-error=dangling-else")
    endif()
    set(cxx_exception_flags "-fexceptions")
    set(cxx_no_exception_flags "-fno-exceptions")
    # Until version 4.3.2, GCC doesn't define a macro to indicate
    # whether RTTI is enabled.  Therefore we define GTEST_HAS_RTTI
    # explicitly.
    set(cxx_no_rtti_flags "-fno-rtti -DGTEST_HAS_RTTI=0")
    set(cxx_strict_flags
      "-Wextra -Wno-unused-parameter -Wno-missing-field-initializers")
  elseif (CMAKE_CXX_COMPILER_ID STREQUAL "SunPro")
    set(cxx_exception_flags "-features=except")
    # Sun Pro doesn't provide macros to indicate whether exceptions and
    # RTTI are enabled, so we define GTEST_HAS_* explicitly.
    set(cxx_no_exception_flags "-features=no%except -DGTEST_HAS_EXCEPTIONS=0")
    set(cxx_no_rtti_flags "-features=no%rtti -DGTEST_HAS_RTTI=0")
  elseif (CMAKE_CXX_COMPILER_ID STREQUAL "VisualAge" OR
      CMAKE_CXX_COMPILER_ID STREQUAL "XL")
    # CMake 2.8 changes Visual Age's compiler ID to "XL".
    set(cxx_exception_flags "-qeh")
    set(cxx_no_exception_flags "-qnoeh")
    # Until version 9.0, Visual Age doesn't define a macro to indicate
    # whether RTTI is enabled.  Therefore we define GTEST_HAS_RTTI
    # explicitly.
    set(cxx_no_rtti_flags "-qnortti -DGTEST_HAS_RTTI=0")
  elseif (CMAKE_CXX_COMPILER_ID STREQUAL "HP")
    set(cxx_base_flags "-AA -mt")
    set(cxx_exception_flags "-DGTEST_HAS_EXCEPTIONS=1")
    set(cxx_no_exception_flags "+noeh -DGTEST_HAS_EXCEPTIONS=0")
    # RTTI can not be disabled in HP aCC compiler.
    set(cxx_no_rtti_flags "")
  endif()

  # The pthreads library is available and allowed?
  if (DEFINED GTEST_HAS_PTHREAD)
    set(GTEST_HAS_PTHREAD_MACRO "-DGTEST_HAS_PTHREAD=1")
  else()
    set(GTEST_HAS_PTHREAD_MACRO "-DGTEST_HAS_PTHREAD=0")
  endif()
  set(cxx_base_flags "${cxx_base_flags} ${GTEST_HAS_PTHREAD_MACRO}")

  # For building gtest's own tests and samples.
  set(cxx_exception "${CMAKE_CXX_FLAGS} ${cxx_base_flags} ${cxx_exception_flags}")
  set(cxx_no_exception
    "${CMAKE_CXX_FLAGS} ${cxx_base_flags} ${cxx_no_exception_flags}")
  set(cxx_default "${cxx_exception}")
  set(cxx_no_rtti "${cxx_default} ${cxx_no_rtti_flags}")
  set(cxx_use_own_tuple "${cxx_default} -DGTEST_USE_OWN_TR1_TUPLE=1")

  # For building the gtest libraries.
  set(cxx_strict "${cxx_default} ${cxx_strict_flags}")
endmacro()

# Defines the gtest & gtest_main libraries.  User tests should link
# with one of them.
function(cxx_library_with_type name type cxx_flags)
  # type can be either STATIC or SHARED to denote a static or shared library.
  # ARGN refers to additional arguments after 'cxx_flags'.
  add_library(${name} ${type} ${ARGN})
  set_target_properties(${name}
    PROPERTIES
    COMPILE_FLAGS "${cxx_flags}")
  # Generate debug library name with a postfix.
  set_target_properties(${name}
    PROPERTIES
    DEBUG_POSTFIX "d")
  if (BUILD_SHARED_LIBS OR type STREQUAL "SHARED")
    set_target_properties(${name}
      PROPERTIES
      COMPILE_DEFINITIONS "GTEST_CREATE_SHARED_LIBRARY=1")
  endif()
  if (DEFINED GTEST_HAS_PTHREAD)
    set_property(TARGET ${name} APPEND INTERFACE_LINK_LIBRARIES ${CMAKE_THREAD_LIBS_INIT})
  endif()
  if (DEFINED GTEST_HAS_LIBRT)
    set_property(TARGET ${name} APPEND INTERFACE_LINK_LIBRARIES ${LIBRT_LIBRARIES})
  endif()
endfunction()

########################################################################
#
# Helper functions for creating build targets.

function(cxx_shared_library name cxx_flags)
  cxx_library_with_type(${name} SHARED "${cxx_flags}" ${ARGN})
endfunction()

function(cxx_library name cxx_flags)
  cxx_library_with_type(${name} "" "${cxx_flags}" ${ARGN})
endfunction()

# cxx_executable_with_flags(name cxx_flags libs srcs...)
#
# creates a named C++ executable that depends on the given libraries and
# is built from the given source files with the given compiler flags.
function(cxx_executable_with_flags name cxx_flags libs)
  add_executable(${name} ${ARGN})
  if (MSVC AND (NOT (MSVC_VERSION LESS 1700)))  # 1700 is Visual Studio 2012.
    # BigObj required for tests.
    set(cxx_flags "${cxx_flags} -bigobj")
  endif()
  if (cxx_flags)
    set_target_properties(${name}
      PROPERTIES
      COMPILE_FLAGS "${cxx_flags}")
  endif()
  if (BUILD_SHARED_LIBS)
    set_target_properties(${name}
      PROPERTIES
      COMPILE_DEFINITIONS "GTEST_LINKED_AS_SHARED_LIBRARY=1")
  endif()
  # To support mixing linking in static and dynamic libraries, link each
  # library in with an extra call to target_link_libraries.
  foreach (lib "${libs}")
    set_property(TARGET ${name} APPEND LINK_LIBRARIES ${lib})
  endforeach()
endfunction()

# cxx_executable(name dir lib srcs...)
#
# creates a named target that depends on the given libs and is built
# from the given source files.  dir/name.cc is implicitly included in
# the source file list.
function(cxx_executable name dir libs)
  cxx_executable_with_flags(
    ${name} "${cxx_default}" "${libs}" "${dir}/${name}.cc" ${ARGN})
endfunction()

# Sets PYTHONINTERP_FOUND and PYTHON_EXECUTABLE.
find_package(PythonInterp)

# cxx_test_with_flags(name cxx_flags libs srcs...)
#
# creates a named C++ test that depends on the given libs and is built
# from the given source files with the given compiler flags.
function(cxx_test_with_flags name cxx_flags libs)
  cxx_executable_with_flags(${name} "${cxx_flags}" "${libs}" ${ARGN})
  add_test(${name} ${name})
endfunction()

# cxx_test(name libs srcs...)
#
# creates a named test target that depends on the given libs and is
# built from the given source files.  Unlike cxx_test_with_flags,
# test/name.cc is already implicitly included in the source file list.
function(cxx_test name libs)
  cxx_test_with_flags("${name}" "${cxx_default}" "${libs}"
    "test/${name}.cc" ${ARGN})
endfunction()

# py_test(name)
#
# creates a Python test with the given name whose main module is in
# test/name.py.  It does nothing if Python is not installed.
function(py_test name)
  if (PYTHONINTERP_FOUND)
    if (${CMAKE_MAJOR_VERSION}.${CMAKE_MINOR_VERSION} GREATER 3.1)
      if (CMAKE_CONFIGURATION_TYPES)
	# Multi-configuration build generators as for Visual Studio save
	# output in a subdirectory of CMAKE_CURRENT_BINARY_DIR (Debug,
	# Release etc.), so we have to provide it here.
        add_test(
          NAME ${name}
          COMMAND ${PYTHON_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/test/${name}.py
              --build_dir=${CMAKE_CURRENT_BINARY_DIR}/$<CONFIG>)
      else (CMAKE_CONFIGURATION_TYPES)
	# Single-configuration build generators like Makefile generators
	# don't have subdirs below CMAKE_CURRENT_BINARY_DIR.
        add_test(
          NAME ${name}
          COMMAND ${PYTHON_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/test/${name}.py
              --build_dir=${CMAKE_CURRENT_BINARY_DIR})
      endif (CMAKE_CONFIGURATION_TYPES)
    else (${CMAKE_MAJOR_VERSION}.${CMAKE_MINOR_VERSION} GREATER 3.1)
      # ${CMAKE_CURRENT_BINARY_DIR} is known at configuration time, so we can
      # directly bind it from cmake. ${CTEST_CONFIGURATION_TYPE} is known
      # only at ctest runtime (by calling ctest -c <Configuration>), so
      # we have to escape $ to delay variable substitution here.
      add_test(
        ${name}
        ${PYTHON_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/test/${name}.py
          --build_dir=${CMAKE_CURRENT_BINARY_DIR}/\${CTEST_CONFIGURATION_TYPE})
    endif (${CMAKE_MAJOR_VERSION}.${CMAKE_MINOR_VERSION} GREATER 3.1)
  endif(PYTHONINTERP_FOUND)
endfunction()
