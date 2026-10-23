cmake_minimum_required(VERSION 3.15)

# ------------------------------------------------------------------------------
# Reuse a verified archive; otherwise download it with up to 3 attempts. Each
# attempt is verified and a truncated or corrupt file is removed before the
# next one, so one interrupted transfer no longer breaks the build.
function(download_and_verify url sha256 locationForArchive)
  if(EXISTS "${locationForArchive}")
    file(SHA256 "${locationForArchive}" ARCHIVE_SHA256)
    if(ARCHIVE_SHA256 STREQUAL "${sha256}")
      message(STATUS "Reusing verified ${locationForArchive}.")
      return()
    endif()
    file(REMOVE "${locationForArchive}")
    message(STATUS "SHA256 mismatch. File deleted.")
  endif()

  foreach(attempt RANGE 1 3)
    message(STATUS "Downloading archive from ${url} (attempt ${attempt})...")
    file(DOWNLOAD "${url}" "${locationForArchive}" STATUS download_status)
    list(GET download_status 0 download_status_code)
    if(download_status_code EQUAL 0)
      file(SHA256 "${locationForArchive}" ARCHIVE_SHA256)
      if(ARCHIVE_SHA256 STREQUAL "${sha256}")
        message(STATUS "${locationForArchive} Verification successful.")
        return()
      endif()
      message(WARNING "${locationForArchive} SHA256 mismatch: ${ARCHIVE_SHA256}")
    else()
      list(GET download_status 1 download_status_message)
      message(WARNING "Download failed: ${download_status_message}")
    endif()
    file(REMOVE "${locationForArchive}")
  endforeach()
  message(FATAL_ERROR "${locationForArchive} Integrity check failed after 3 attempts, please try to re-build project again.")
endfunction()

function(check_directory_exists_and_not_empty dir result_var)
  # Check if the directory exists
  if(EXISTS "${dir}")
    # Check if the directory is not empty
    file(GLOB dir_contents "${dir}/*")

    if(dir_contents)
      set(${result_var} TRUE PARENT_SCOPE)
    else()
      set(${result_var} FALSE PARENT_SCOPE)
      message(STATUS "Directory ${dir} exists but is empty!")
    endif()
  else()
    set(${result_var} FALSE PARENT_SCOPE)
    message(STATUS "Directory ${dir} does not exist!")
  endif()
endfunction()

# libmpv archive containing the pre-built shared libraries.
set(LIBMPV "libmpv_aarch64.zip")

# Download URL & SHA256 hash of the libmpv archive.
set(LIBMPV_URL "https://github.com/ErBWs/libmpv-ohos-build/releases/download/20260811/${LIBMPV}")
set(LIBMPV_SHA "2bfb9844a7552c450694581b315b26cdf6202eaa57724e9f70f3facfad75163b")

# Download location of the libmpv archive.
set(LIBMPV_ARCHIVE "${CMAKE_CURRENT_SOURCE_DIR}/${LIBMPV}")
set(LIBMPV_SRC "${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/arm64-v8a/")

download_and_verify(
  ${LIBMPV_URL}
  ${LIBMPV_SHA}
  ${LIBMPV_ARCHIVE}
)

check_directory_exists_and_not_empty(${LIBMPV_SRC} LIBMPV_SRC_VALID)

# A directory extracted from a different (e.g. previously pinned) archive or
# from an interrupted extraction is stale: extract again.
set(LIBMPV_STAMP "${LIBMPV_SRC}/media_kit_libmpv_${LIBMPV_SHA}.stamp")
if(LIBMPV_SRC_VALID AND NOT EXISTS "${LIBMPV_STAMP}")
  message(STATUS "Removing stale ${LIBMPV_SRC}...")
  file(REMOVE_RECURSE "${LIBMPV_SRC}")
  set(LIBMPV_SRC_VALID FALSE)
endif()

# Extract the libmpv archive.
if(NOT LIBMPV_SRC_VALID)
  message(STATUS "Extracting ${LIBMPV}...")
  make_directory("${LIBMPV_SRC}")
  add_custom_target("LIBMPV_EXTRACT" ALL)
  add_custom_command(
    TARGET "LIBMPV_EXTRACT"
    COMMAND "${CMAKE_COMMAND}" -E tar -xf "${LIBMPV_ARCHIVE}"
    COMMAND "${CMAKE_COMMAND}" -E touch "${LIBMPV_STAMP}"
    WORKING_DIRECTORY "${LIBMPV_SRC}"
  )
endif()
# ------------------------------------------------------------------------------

project(mediakit_libs_ohos)

set(LIBS
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/arm64-v8a/libmpv.so.2)

link_libraries(DART_SHARED_LIB ${LIBS})
