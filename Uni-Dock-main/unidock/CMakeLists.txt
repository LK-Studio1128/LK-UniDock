cmake_minimum_required(VERSION 3.16)

# CMake >= 3.30 removed the legacy FindBoost module (CMP0167).
# Set policy so the project works with both old and new CMake.
if(POLICY CMP0167)
  cmake_policy(SET CMP0167 NEW)
endif()

# Declare project without CUDA first; CUDA is enabled conditionally below.
project(
  Uni-Dock
  VERSION 1.1.3
  DESCRIPTION "GPU-Accelerated Docking with 1000-fold speedup"
  HOMEPAGE_URL "https://github.com/dptech-corp/Uni-Dock"
  LANGUAGES CXX)
set(VINA_BIN_NAME unidock)

# Make sure the default is a release build
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

# >>>>>> Language Configuration Begin
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CUDA_STANDARD 17)

option(Boost_USE_STATIC_LIBS "Whether to use static libs for boost" OFF)
option(FORCE_CPU_ONLY "Disable CUDA and build CPU-only version" OFF)
if(MSVC)
  set(_DEFAULT_BUILD_PORTABLE OFF)
else()
  set(_DEFAULT_BUILD_PORTABLE ON)
endif()
option(BUILD_PORTABLE "Link Boost and OpenMP statically for a portable binary" ${_DEFAULT_BUILD_PORTABLE})
option(REQUIRE_CUDA "Fail configuration when CUDA is required but unavailable" OFF)
option(BUILD_TESTS "Build unit tests and download Catch2" OFF)

# >>>>>> CUDA Detection (optional) Begin
include(CheckLanguage)
check_language(CUDA)

if(CMAKE_CUDA_COMPILER AND NOT FORCE_CPU_ONLY)
  enable_language(CUDA)
  set(CUDA_FOUND TRUE)
  message(STATUS "[Uni-Dock] CUDA found: ${CMAKE_CUDA_COMPILER}. Building GPU-accelerated version.")

  set(CMAKE_CUDA_FLAGS_DEBUG "-g -G")

  if(BUILD_PORTABLE AND NOT APPLE)
    set(CMAKE_CUDA_RUNTIME_LIBRARY Static)
    message(STATUS "[Uni-Dock] BUILD_PORTABLE=ON: using static CUDA runtime.")
  endif()

  if(NOT DEFINED CMAKE_CUDA_ARCHITECTURES)
    # https://en.wikipedia.org/wiki/CUDA#GPUs_supported
    # Pascal (sm_60, sm_61) and Volta (sm_70) were removed in CUDA 13.0
    set(CMAKE_CUDA_ARCHITECTURES)
    if(CMAKE_CUDA_COMPILER_VERSION VERSION_LESS 13.0)
      list(APPEND CMAKE_CUDA_ARCHITECTURES
        60 # GTX 1060/1070/1080, Pascal (P100)
        61 # GTX 1050, Quadro P-series
        70 # V100 (Volta, removed in CUDA 13.0)
      )
    endif()
    list(APPEND CMAKE_CUDA_ARCHITECTURES
      75 # RTX 20, T4
      80 # A100, A800
      86 # RTX 30
      89 # RTX 40, L40
      90 # H100
    )
    if(CMAKE_CUDA_COMPILER_VERSION VERSION_GREATER_EQUAL 12.8)
      list(APPEND CMAKE_CUDA_ARCHITECTURES 100) # B100, B200, GB200
      list(APPEND CMAKE_CUDA_ARCHITECTURES 120) # RTX 50, B40
      message(STATUS "[Uni-Dock] CUDA >= 12.8 detected: enabling sm_100/sm_120 for Blackwell.")
    else()
      message(STATUS "[Uni-Dock] CUDA < 12.8: skipping sm_100/sm_120 (Blackwell requires CUDA >= 12.8).")
    endif()
    if(CMAKE_CUDA_COMPILER_VERSION VERSION_LESS 13.0)
      message(STATUS "[Uni-Dock] CUDA < 13.0: including sm_60/sm_61 (Pascal) and sm_70 (Volta).")
    else()
      message(STATUS "[Uni-Dock] CUDA >= 13.0: sm_60/sm_61/sm_70 (Pascal/Volta) removed, minimum is sm_75.")
    endif()
  endif()

  option(BUILD_FAST_MATH "Build in fast math mode" ON)
  if(BUILD_FAST_MATH)
    set(CMAKE_CUDA_FLAGS_RELEASE "${CMAKE_CUDA_FLAGS_RELEASE} --use_fast_math")
    message(STATUS "[Uni-Dock] CUDA fast math enabled.")
  endif()

  if(MSVC AND NOT (CMAKE_CUDA_COMPILER_VERSION VERSION_LESS 13.0))
    set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -Xcompiler /Zc:preprocessor")
    message(STATUS "[Uni-Dock] MSVC: enabling /Zc:preprocessor for CCCL compatibility (CUDA 13.x).")
  elseif(MSVC)
    message(STATUS "[Uni-Dock] MSVC + CUDA < 13.0: skipping /Zc:preprocessor (incompatible with MSVC STL <filesystem>).")
  endif()

  add_compile_definitions(ENABLE_CUDA)
  # Force Boost smart_ptr to use std::atomic instead of GCC __atomic_* builtins
  # (NVCC device compiler mimics GCC macros, misleading Boost auto-detection).
  add_compile_definitions(BOOST_SP_USE_STD_ATOMIC BOOST_AC_USE_STD_ATOMIC)
else()
  set(CUDA_FOUND FALSE)
  if(FORCE_CPU_ONLY)
    message(STATUS "[Uni-Dock] FORCE_CPU_ONLY=ON. Building CPU-only version.")
  elseif(REQUIRE_CUDA)
    message(FATAL_ERROR
      "[Uni-Dock] REQUIRE_CUDA=ON but CUDA compiler was not found.\n"
      "  Install CUDA Toolkit >= 11.8 on Linux/Windows, or build CPU-only with -DFORCE_CPU_ONLY=ON.")
  else()
    message(WARNING
      "[Uni-Dock] CUDA compiler not found. Building CPU-only version (no GPU acceleration).\n"
      "  On macOS (Apple Silicon): CUDA is not supported. This is expected.\n"
      "  On Linux/Windows: Install CUDA Toolkit >= 11.8 from https://developer.nvidia.com/cuda-downloads")
  endif()
endif()
# >>>>>> CUDA Detection End

add_compile_definitions(VERSION="v${PROJECT_VERSION}")

# >>>>>> Language Configuration End

# >>>>>> Platform-specific OpenMP Configuration Begin
# macOS: Apple Clang does NOT bundle OpenMP.
# Install via:  brew install libomp   OR   conda install libomp -c conda-forge
if(APPLE)
  find_package(OpenMP COMPONENTS CXX QUIET)
  if(NOT OpenMP_CXX_FOUND)
    # Try Homebrew libomp path
    execute_process(
      COMMAND brew --prefix libomp
      OUTPUT_VARIABLE _BREW_LIBOMP
      OUTPUT_STRIP_TRAILING_WHITESPACE
      ERROR_QUIET)
    if(_BREW_LIBOMP AND EXISTS "${_BREW_LIBOMP}/include")
      set(OpenMP_CXX_FLAGS "-Xpreprocessor -fopenmp -I${_BREW_LIBOMP}/include")
      set(OpenMP_CXX_LIB_NAMES "omp")
      if(BUILD_PORTABLE AND EXISTS "${_BREW_LIBOMP}/lib/libomp.a")
        set(OpenMP_omp_LIBRARY "${_BREW_LIBOMP}/lib/libomp.a")
      else()
        set(OpenMP_omp_LIBRARY "${_BREW_LIBOMP}/lib/libomp.dylib")
      endif()
      find_package(OpenMP COMPONENTS CXX QUIET)
    endif()
    # Try conda libomp (common path: $CONDA_PREFIX/lib/libomp.dylib)
    if(NOT OpenMP_CXX_FOUND AND DEFINED ENV{CONDA_PREFIX})
      set(_CONDA_OMP "$ENV{CONDA_PREFIX}")
      if(EXISTS "${_CONDA_OMP}/lib/libomp.dylib")
        set(OpenMP_CXX_FLAGS "-Xpreprocessor -fopenmp -I${_CONDA_OMP}/include")
        set(OpenMP_CXX_LIB_NAMES "omp")
        if(BUILD_PORTABLE AND EXISTS "${_CONDA_OMP}/lib/libomp.a")
          set(OpenMP_omp_LIBRARY "${_CONDA_OMP}/lib/libomp.a")
        else()
          set(OpenMP_omp_LIBRARY "${_CONDA_OMP}/lib/libomp.dylib")
        endif()
        find_package(OpenMP COMPONENTS CXX QUIET)
      endif()
    endif()
  endif()
  if(OpenMP_CXX_FOUND AND BUILD_PORTABLE)
    execute_process(
      COMMAND brew --prefix libomp
      OUTPUT_VARIABLE _BREW_LIBOMP_STATIC
      OUTPUT_STRIP_TRAILING_WHITESPACE
      ERROR_QUIET)
    if(_BREW_LIBOMP_STATIC AND EXISTS "${_BREW_LIBOMP_STATIC}/lib/libomp.a")
      set(OpenMP_omp_LIBRARY "${_BREW_LIBOMP_STATIC}/lib/libomp.a" CACHE FILEPATH "" FORCE)
      message(STATUS "[Uni-Dock] BUILD_PORTABLE: using static ${_BREW_LIBOMP_STATIC}/lib/libomp.a")
    endif()
  endif()
  if(OpenMP_CXX_FOUND)
    message(STATUS "[Uni-Dock] OpenMP found on macOS: ${OpenMP_omp_LIBRARY}")
  else()
    message(WARNING
      "[Uni-Dock] OpenMP not found on macOS. Multi-threaded docking will use single thread.\n"
      "  Install: brew install libomp  OR  conda install libomp -c conda-forge\n"
      "  Then re-run cmake.")
    # Provide a no-op OpenMP target so the rest of CMakeLists compiles cleanly
    add_library(_openmp_stub INTERFACE)
    add_library(OpenMP::OpenMP_CXX ALIAS _openmp_stub)
  endif()
elseif(WIN32)
  # MSVC ships with OpenMP support via /openmp flag (OpenMP 2.0)
  find_package(OpenMP COMPONENTS CXX)
  if(NOT OpenMP_CXX_FOUND)
    message(WARNING "[Uni-Dock] OpenMP not found on Windows. Multi-threaded docking disabled.")
    add_library(_openmp_stub INTERFACE)
    add_library(OpenMP::OpenMP_CXX ALIAS _openmp_stub)
  endif()
else()
  # Linux: GCC/Clang both support OpenMP out of the box
  find_package(OpenMP COMPONENTS CXX REQUIRED)
endif()

add_library(portable_openmp INTERFACE)
if(BUILD_PORTABLE AND UNIX AND NOT APPLE AND OpenMP_CXX_FOUND)
  execute_process(
    COMMAND ${CMAKE_CXX_COMPILER} -print-file-name=libgomp.a
    OUTPUT_VARIABLE _OPENMP_STATIC_GOMP
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET)
  if(_OPENMP_STATIC_GOMP AND EXISTS "${_OPENMP_STATIC_GOMP}" AND NOT _OPENMP_STATIC_GOMP STREQUAL "libgomp.a")
    separate_arguments(_OPENMP_CXX_FLAGS NATIVE_COMMAND "${OpenMP_CXX_FLAGS}")
    target_compile_options(portable_openmp INTERFACE ${_OPENMP_CXX_FLAGS})
    target_link_libraries(portable_openmp INTERFACE "${_OPENMP_STATIC_GOMP}")
    message(STATUS "[Uni-Dock] BUILD_PORTABLE=ON: using static OpenMP runtime ${_OPENMP_STATIC_GOMP}")
  else()
    target_link_libraries(portable_openmp INTERFACE OpenMP::OpenMP_CXX)
    message(WARNING "[Uni-Dock] BUILD_PORTABLE=ON but static libgomp.a was not found. OpenMP will remain dynamically linked.")
  endif()
elseif(TARGET OpenMP::OpenMP_CXX)
  target_link_libraries(portable_openmp INTERFACE OpenMP::OpenMP_CXX)
endif()
# >>>>>> Platform-specific OpenMP Configuration End

# >>>>>> Dependencies Begin
include(FetchContent)

# >>> CMake
option(FETCH_BOOST "Whether to use FetchContent to include boost" OFF)
# 'system' became header-only in Boost >= 1.69; do not list it as a compiled component.
set(REQUIRED_BOOST_COMPONENTS
  thread serialization
  filesystem program_options timer
)

Set(FETCHCONTENT_QUIET FALSE) # Needed to print downloading progress

if(MSVC)
  add_compile_options($<$<COMPILE_LANGUAGE:CXX>:/permissive->)
  add_compile_options($<$<COMPILE_LANGUAGE:CXX>:/utf-8>)
endif()

if(BUILD_PORTABLE)
  set(Boost_USE_STATIC_LIBS ON CACHE BOOL "" FORCE)
  if(UNIX AND NOT APPLE)
    add_link_options(-static-libstdc++ -static-libgcc)
  endif()
  if(MSVC)
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
  endif()
  message(STATUS "[Uni-Dock] BUILD_PORTABLE=ON: static Boost/OpenMP/runtime")
else()
  set(Boost_USE_STATIC_LIBS OFF CACHE BOOL "" FORCE)
endif()

if(NOT FETCH_BOOST)
  # Hint CMake to look in Homebrew prefix (macOS) and conda prefix
  if(APPLE AND EXISTS "/opt/homebrew")
    list(PREPEND CMAKE_PREFIX_PATH "/opt/homebrew")
  endif()
  if(DEFINED ENV{CONDA_PREFIX})
    list(PREPEND CMAKE_PREFIX_PATH "$ENV{CONDA_PREFIX}")
  endif()
endif()

if(FETCH_BOOST)
  set(BOOST_ENABLE_CMAKE ON)
  set(BOOST_INCLUDE_LIBRARIES ${REQUIRED_BOOST_COMPONENTS})

  # downloading a compressed release speeds up the download
  FetchContent_Declare(
    Boost
    URL https://github.com/boostorg/boost/releases/download/boost-1.84.0/boost-1.84.0.tar.gz
    USES_TERMINAL_DOWNLOAD TRUE
    GIT_PROGRESS TRUE
    DOWNLOAD_NO_EXTRACT FALSE
  )
  FetchContent_MakeAvailable(Boost)
  # Boost monorepo layout: headers live in libs/*/include/ not at the root.
  file(GLOB _boost_per_lib_includes "${boost_SOURCE_DIR}/libs/*/include")
  include_directories(${boost_SOURCE_DIR} ${_boost_per_lib_includes})
else()
  find_package(Boost 1.72 REQUIRED COMPONENTS ${REQUIRED_BOOST_COMPONENTS})
  include_directories(${Boost_INCLUDE_DIRS})
endif()

# >>> Catch2
if(BUILD_TESTS)
  FetchContent_Declare(
    Catch2
    GIT_REPOSITORY https://github.com/catchorg/Catch2.git
    GIT_TAG v3.4.0 # or a later release
  )
  FetchContent_MakeAvailable(Catch2)
  list(APPEND CMAKE_MODULE_PATH ${catch2_SOURCE_DIR}/extras)
endif()

# >>>>>> Dependencies End

# >>>>>> Libraries Definitions Begin

# Group boost dependencies
# Boost::system is header-only since Boost 1.69.
# Provide a no-op alias if the target doesn't exist (modern Boost via CMake config).
if(NOT TARGET Boost::system)
  if(TARGET Boost::headers)
    add_library(Boost::system ALIAS Boost::headers)
  else()
    add_library(_boost_system_stub INTERFACE)
    add_library(Boost::system ALIAS _boost_system_stub)
  endif()
endif()

add_library(boost_deps INTERFACE)
target_link_libraries(
  boost_deps INTERFACE Boost::system Boost::thread Boost::serialization
  Boost::filesystem Boost::program_options Boost::timer)

add_library(
  lib OBJECT
  src/lib/ad4cache.cpp
  src/lib/cache.cpp
  src/lib/non_cache.cpp
  src/lib/conf_independent.cpp
  src/lib/coords.cpp
  src/lib/grid.cpp
  src/lib/szv_grid.cpp
  src/lib/model.cpp
  src/lib/mutate.cpp
  src/lib/monte_carlo.cc
  src/lib/parallel_mc.cpp
  src/lib/parse_pdbqt.cpp
  src/lib/quasi_newton.cpp
  src/lib/quaternion.cpp
  src/lib/random.cpp
  src/lib/utils.cpp
  src/lib/vina.cpp
)
target_include_directories(lib PUBLIC src/lib src/cuda)
target_link_libraries(lib PUBLIC boost_deps)

if(CUDA_FOUND)
  add_library(cuda OBJECT src/cuda/monte_carlo.cu src/cuda/precalculate.cu)
  target_include_directories(cuda PUBLIC src/lib src/cuda)
  # NVCC 12.x cudafe1 mis-injects MSVC STL <filesystem> code into boost::filesystem
  # namespace, breaking ::__std_fs_copy_options lookup. Prevent Boost from pulling
  # in <filesystem> by telling it C++17 <filesystem> header is unavailable.
  # This only affects .cu compilation; host .cpp code still uses it normally.
  if(MSVC)
    target_compile_definitions(cuda PRIVATE
      BOOST_NO_CXX17_HDR_FILESYSTEM
      BOOST_FILESYSTEM_NO_CXX20_ATOMIC_REF)
  endif()
endif()

# >>>>>> Libraries Definitions End

# >>>>>> Binaries Definitions Begin

# >>> Main binary (unidock)
add_executable(${VINA_BIN_NAME} src/main/main.cpp)
if(CUDA_FOUND)
  target_link_libraries(${VINA_BIN_NAME} PRIVATE
    boost_deps cuda lib
    portable_openmp
  )
  target_include_directories(${VINA_BIN_NAME}
    PUBLIC ${CMAKE_CUDA_TOOLKIT_INCLUDE_DIRECTORIES})
else()
  target_link_libraries(${VINA_BIN_NAME} PRIVATE
    boost_deps lib
    portable_openmp
  )
endif()
install(TARGETS ${VINA_BIN_NAME})

# >>> split
add_executable(split src/split/split.cpp)
target_link_libraries(split PRIVATE boost_deps)
target_include_directories(split PRIVATE src/lib)

# >>>>>> Binaries Definitions End

# >>>>>> Tests Definitions Begin
if(BUILD_TESTS)
  file(GLOB_RECURSE TEST_SOURCES ${CMAKE_SOURCE_DIR}/unittest/*.cpp)
  add_executable(unit_tests ${TEST_SOURCES})
  if(CUDA_FOUND)
    target_link_libraries(unit_tests PRIVATE
      boost_deps lib cuda
      portable_openmp
      Catch2::Catch2WithMain
    )
  else()
    target_link_libraries(unit_tests PRIVATE
      boost_deps lib
      portable_openmp
      Catch2::Catch2WithMain
    )
  endif()

  include(CTest)
  include(Catch)
  catch_discover_tests(unit_tests
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
  )

  # Copy test data to build directory
  file(
    COPY ${CMAKE_SOURCE_DIR}/unittest/test_data
    DESTINATION ${CMAKE_CURRENT_BINARY_DIR}
  )
endif()

# >>>>>> Tests Definitions End

# >>>>>> Clang Format Begin

# Configure clang-format
file(
  GLOB_RECURSE
  sources
  CONFIGURE_DEPENDS
  src/*.cpp
  src/*.h
  src/*.cu
  src/*.cuh)
set(CLANG_FORMAT clang-format)
add_custom_target(
  clang-format
  COMMAND ${CLANG_FORMAT} -i ${sources}
  COMMENT "Running clang-format"
  VERBATIM)

# >>>>>> Clang Format End
