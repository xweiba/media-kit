# This file is a part of media_kit (https://github.com/media-kit/media-kit).
#
# Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
# All rights reserved.
# Use of this source code is governed by MIT license that can be found in the LICENSE file.

# The file is moded for the purpose of building application with libmpv embeded.
# Copyright © 2024 & Predidit
# All rights reserved.

cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "media_kit_video")
set(CMAKE_CXX_STANDARD 17)
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "media_kit_video_plugin")

set(CMAKE_BUILD_WITH_INSTALL_RPATH TRUE)
set(CMAKE_INSTALL_RPATH "$ORIGIN")
set(CMAKE_INSTALL_RPATH_USE_LINK_PATH TRUE)

if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|amd64|AMD64")
  set(ARCH_NAME "x86_64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64|ARM64")
  set(ARCH_NAME "aarch64")
else()
  message(FATAL_ERROR "Unsupported architecture: ${CMAKE_SYSTEM_PROCESSOR}")
endif()

message(STATUS "Detected architecture: ${ARCH_NAME}")

if(ARCH_NAME STREQUAL "x86_64")
  set(LIBMPV_ZIP_URL "https://github.com/xweiba/libmpv-linux-build/releases/download/20261023/libmpv_x86_64.zip")
  set(LIBMPV_ZIP_SHA256 "7b36d9f731eb50fd6fe37e4b65d7e9fb487ecb75c96245208f114594667c3150")
  set(LIBMPV_HEADER_ZIP_URL "https://github.com/xweiba/libmpv-linux-build/releases/download/20261023/libmpv_x86_64_header.zip")
  set(LIBMPV_HEADER_ZIP_SHA256 "219addddeff09072995303b3a6c14081f052a07919d660ac1259b6b85df806d8")
elseif(ARCH_NAME STREQUAL "aarch64")
  set(LIBMPV_ZIP_URL "https://github.com/xweiba/libmpv-linux-build/releases/download/20261023/libmpv_aarch64.zip")
  set(LIBMPV_ZIP_SHA256 "27608bf5ce88626f74518c31075cd1bd9cc573bd92fb3d6aeb2006a0931f2f1e")
  set(LIBMPV_HEADER_ZIP_URL "https://github.com/xweiba/libmpv-linux-build/releases/download/20261023/libmpv_aarch64_header.zip")
  set(LIBMPV_HEADER_ZIP_SHA256 "b92e49acd6070e44d6c948e9c2c27ccf6dac28c30579b6281ad8ddae300779a9")
endif()

set(LIBMPV_ZIP_PATH "${CMAKE_BINARY_DIR}/libmpv_${ARCH_NAME}.zip")
set(LIBMPV_UNZIP_DIR "${CMAKE_BINARY_DIR}/mpv")

make_directory("${LIBMPV_UNZIP_DIR}") 
message(STATUS "create libmpv unzip directory ${LIBMPV_UNZIP_DIR}")

# Reuse a verified archive and retry partial downloads. Re-downloading on
# every configure made local builds fail whenever one transfer was truncated.
function(media_kit_video_fetch url expected_sha256 destination)
  if(EXISTS "${destination}")
    file(SHA256 "${destination}" existing_sha256)
    if(existing_sha256 STREQUAL "${expected_sha256}")
      message(STATUS "Reusing verified ${destination}")
      return()
    endif()
    file(REMOVE "${destination}")
  endif()
  foreach(attempt RANGE 1 3)
    message(STATUS "downloading ${url} to ${destination} (attempt ${attempt})")
    file(DOWNLOAD "${url}" "${destination}" SHOW_PROGRESS
      EXPECTED_HASH SHA256=${expected_sha256}
      STATUS download_status)
    list(GET download_status 0 download_status_code)
    if(download_status_code EQUAL 0)
      message(STATUS "SHA256 checksum verification passed.")
      return()
    endif()
    list(GET download_status 1 download_status_message)
    message(WARNING "download failed: ${download_status_message}")
    file(REMOVE "${destination}")
  endforeach()
  message(FATAL_ERROR "Failed to download verified ${url}")
endfunction()

media_kit_video_fetch("${LIBMPV_ZIP_URL}" "${LIBMPV_ZIP_SHA256}" "${LIBMPV_ZIP_PATH}")

message(STATUS "unzip libmpv to ${LIBMPV_UNZIP_DIR}")
execute_process(
  COMMAND unzip -o -q ${LIBMPV_ZIP_PATH} -d ${LIBMPV_UNZIP_DIR}
  WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
  RESULT_VARIABLE unzip_result
)

if(NOT unzip_result EQUAL 0)
  message(FATAL_ERROR "unzip libmpv failed, err: ${unzip_result}")
else()
  message(STATUS "unzip libmpv success.")
endif()

set(LIBMPV_PATH "${LIBMPV_UNZIP_DIR}")

if(EXISTS "${LIBMPV_PATH}/libmpv.so.2")
  message(STATUS "libmpv.so.2 founded ${LIBMPV_PATH}/libmpv.so.2")
else()
  message(FATAL_ERROR "libmpv.so.2 not founded ${LIBMPV_PATH}")
endif()

set(LIBMPV_HEADER_ZIP_PATH "${CMAKE_BINARY_DIR}/libmpv_${ARCH_NAME}_header.zip")
set(LIBMPV_HEADER_UNZIP_DIR "${CMAKE_BINARY_DIR}/mpv/include")

media_kit_video_fetch("${LIBMPV_HEADER_ZIP_URL}" "${LIBMPV_HEADER_ZIP_SHA256}" "${LIBMPV_HEADER_ZIP_PATH}")

message(STATUS "unzip libmpv header to ${LIBMPV_HEADER_UNZIP_DIR}")
execute_process(
  COMMAND unzip -o -q ${LIBMPV_HEADER_ZIP_PATH} -d ${LIBMPV_HEADER_UNZIP_DIR}
  RESULT_VARIABLE unzip_result
)

if(NOT unzip_result EQUAL 0)
  message(FATAL_ERROR "unzip libmpv header failed, err: ${unzip_result}")
else()
  message(STATUS "unzip libmpv header success.")
endif()

if(MEDIA_KIT_LIBS_AVAILABLE)
  add_library(
    ${PLUGIN_NAME} SHARED
    "media_kit_video_plugin.cc"
    "texture_gl.cc"
    "texture_sw.cc"
    "video_output_manager.cc"
    "video_output.cc"
    "gl_render_thread.cc"
    "utils.cc"
  )

  # add runpath, shared libs of a release bundle is in lib dir, plugin must add $ORIGIN to runpath to find libmpv
  target_link_options(${PLUGIN_NAME} PRIVATE -Wl,--enable-new-dtags -Wl,-z,origin)
  set_target_properties(${PLUGIN_NAME} PROPERTIES 
  BUILD_WITH_INSTALL_RPATH TRUE
  INSTALL_RPATH "$ORIGIN:$ORIGIN/lib"
  INSTALL_RPATH_USE_LINK_PATH TRUE)

  add_library(
     libmpv SHARED IMPORTED
  )

  apply_standard_settings(${PLUGIN_NAME})

  find_package(PkgConfig REQUIRED)
  pkg_check_modules(epoxy IMPORTED_TARGET epoxy)

  set_target_properties(
    ${PLUGIN_NAME} PROPERTIES
    CXX_VISIBILITY_PRESET hidden
  )

  set_target_properties(
    libmpv PROPERTIES
    IMPORTED_LOCATION "${LIBMPV_UNZIP_DIR}/libmpv.so.2"
  )

  target_compile_definitions(
    ${PLUGIN_NAME} PRIVATE
    FLUTTER_PLUGIN_IMPL
  )

  target_compile_options(${PLUGIN_NAME} PRIVATE "${epoxy_CFLAGS_OTHER}")

  target_include_directories(
    ${PLUGIN_NAME} INTERFACE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${epoxy_INCLUDE_DIRS}"
  )

  target_include_directories(
    ${PLUGIN_NAME} PRIVATE
    "${LIBMPV_HEADER_UNZIP_DIR}"
  )

  target_link_libraries(
    ${PLUGIN_NAME} PRIVATE
    flutter
    PkgConfig::GTK
    libmpv
    PkgConfig::epoxy
  )

else()
  message(NOTICE "media_kit: WARNING: package:media_kit_libs_*** not found.")

  add_library(
    ${PLUGIN_NAME} SHARED
    "media_kit_video_plugin.cc"
  )

  # add runpath, shared libs of a release bundle is in lib dir, plugin must add $ORIGIN to runpath to find libmpv
  target_link_options(${PLUGIN_NAME} PRIVATE -Wl,--enable-new-dtags -Wl,-z,origin)
  set_target_properties(${PLUGIN_NAME} PROPERTIES 
  BUILD_WITH_INSTALL_RPATH TRUE
  INSTALL_RPATH "$ORIGIN:$ORIGIN/lib"
  INSTALL_RPATH_USE_LINK_PATH TRUE)

  apply_standard_settings(${PLUGIN_NAME})

  set_target_properties(
    ${PLUGIN_NAME} PROPERTIES
    CXX_VISIBILITY_PRESET hidden
  )

  target_compile_definitions(
    ${PLUGIN_NAME} PRIVATE
    FLUTTER_PLUGIN_IMPL
    "MEDIA_KIT_LIBS_NOT_FOUND=1"
  )

  target_include_directories(
    ${PLUGIN_NAME} INTERFACE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
  )

  target_link_libraries(
    ${PLUGIN_NAME} PRIVATE
    flutter
    PkgConfig::GTK
  )
endif()

message(STATUS "create libmpv install directory ${CMAKE_BINARY_DIR}/mpv")
file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/mpv")

# install(FILES "${LIBMPV_PATH}/libmpv.so.2" DESTINATION lib)

set(
  media_kit_video_bundled_libraries
  "${LIBMPV_PATH}/libmpv.so.2"
  PARENT_SCOPE
)
