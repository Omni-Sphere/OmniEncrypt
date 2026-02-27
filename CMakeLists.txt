cmake_minimum_required(VERSION 3.16)
project(OmniEncrypt LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Configure include paths
include_directories(${CMAKE_CURRENT_SOURCE_DIR})
# Headers are in OmniUtils/Include
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/OmniUtils/Include)
# Webview headers
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/webview)

# macOS Webview Requirements
# Webview Requirements per Platform
if(APPLE)
    find_library(WEBKIT_FRAMEWORK WebKit REQUIRED)
elseif(WIN32)
    # WebView2 is typically handled by the header if not using a specific NuGet package,
    # but some setups require linking against WebView2Loader.
    # For a simple webview.h setup, it often just works with the right defines.
elseif(UNIX AND NOT APPLE)
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(GTK3 REQUIRED gtk+-3.0)
    pkg_check_modules(WEBKIT2 REQUIRED webkit2gtk-4.0)
endif()

# Transitive dependencies (OmniUtils uses Sodium and Boost)
find_library(SODIUM_LIB sodium)
find_package(Boost COMPONENTS json)

# Find Python for the asset bundling script (Cross-Platform)
find_package(Python3 REQUIRED COMPONENTS Interpreter)

# Generate html_content.h from code.html and assets
add_custom_command(
    OUTPUT ${CMAKE_CURRENT_SOURCE_DIR}/html_content.h
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/build_assets.py
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/code.html ${CMAKE_CURRENT_SOURCE_DIR}/build_assets.py 
            ${CMAKE_CURRENT_SOURCE_DIR}/assets/tailwind.min.css
            ${CMAKE_CURRENT_SOURCE_DIR}/assets/fonts/public-sans.css
            ${CMAKE_CURRENT_SOURCE_DIR}/assets/fonts/material-symbols.css
    COMMENT "Bundling HTML and Assets into C++ Header..."
)

add_executable(OmniEncrypt main.cpp ${CMAKE_CURRENT_SOURCE_DIR}/html_content.h)

# Pass the source directory so main.cpp can find code.html automatically without copying during dev
target_compile_definitions(OmniEncrypt PRIVATE SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
target_include_directories(OmniEncrypt PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

# Link OmniUtils library
# We link the .dylib directly since we don't have the source to rebuild it
target_link_libraries(OmniEncrypt PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/OmniUtils/libOmniUtils.dylib"
)

# Link platform-specific requirements
if(APPLE)
    target_link_libraries(OmniEncrypt PRIVATE "${WEBKIT_FRAMEWORK}")
elseif(WIN32)
    # On Windows, webview.h uses WebView2.
    # We might need to link against Shlwapi and others.
    target_link_libraries(OmniEncrypt PRIVATE Shlwapi)
elseif(UNIX AND NOT APPLE)
    target_link_libraries(OmniEncrypt PRIVATE ${GTK3_LIBRARIES} ${WEBKIT2_LIBRARIES})
    target_compile_options(OmniEncrypt PRIVATE ${GTK3_CFLAGS} ${WEBKIT2_CFLAGS})
endif()

# Link transitive dependencies if found
if(SODIUM_LIB)
    target_link_libraries(OmniEncrypt PRIVATE ${SODIUM_LIB})
endif()
if(Boost_FOUND)
    target_link_libraries(OmniEncrypt PRIVATE Boost::json)
endif()

add_custom_target(SyncAssets ALL
    COMMENT "Syncing runtime dependencies to build directory"
)

# Cross-platform OmniUtils sync
if(APPLE)
    add_custom_command(TARGET SyncAssets POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/OmniUtils/libOmniUtils.dylib" "$<TARGET_FILE_DIR:OmniEncrypt>"
    )
elseif(WIN32)
    add_custom_command(TARGET SyncAssets POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/OmniUtils/OmniUtils.dll" "$<TARGET_FILE_DIR:OmniEncrypt>"
        # Add WebView2Loader.dll if present
        COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/webview/build/native/x64/WebView2Loader.dll" "$<TARGET_FILE_DIR:OmniEncrypt>" || true
    )

    # Transitive Windows Dependency Resolution
    get_filename_component(SODIUM_LIB_DIR "${SODIUM_LIB}" DIRECTORY)
    find_file(SODIUM_DLL 
        NAMES "libsodium.dll" "sodium.dll" "libsodium-26.dll"
        HINTS "${SODIUM_LIB_DIR}/../bin" "${SODIUM_LIB_DIR}"
    )
    
    if(SODIUM_DLL)
        message(STATUS "Found Sodium DLL: ${SODIUM_DLL}")
        add_custom_command(TARGET SyncAssets POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different "${SODIUM_DLL}" "$<TARGET_FILE_DIR:OmniEncrypt>"
            COMMENT "Copying Sodium DLL..."
        )
    else()
        message(WARNING "Could NOT find Sodium DLL. You may need to copy it manually to $<TARGET_FILE_DIR:OmniEncrypt>")
    endif()

    set(BOOST_BIN_DIR "")
    if(DEFINED Boost_LIBRARY_DIRS)
        list(GET Boost_LIBRARY_DIRS 0 FIRST_LIB_DIR)
        set(BOOST_BIN_DIR "${FIRST_LIB_DIR}/../bin")
    elseif(DEFINED Boost_LIBRARIES)
        list(GET Boost_LIBRARIES 0 FIRST_LIB)
        if(EXISTS "${FIRST_LIB}")
            get_filename_component(FIRST_LIB_DIR "${FIRST_LIB}" DIRECTORY)
            set(BOOST_BIN_DIR "${FIRST_LIB_DIR}/../bin")
        endif()
    endif()

    if(BOOST_BIN_DIR AND EXISTS "${BOOST_BIN_DIR}")
        file(GLOB BOOST_DLLS "${BOOST_BIN_DIR}/*boost_json*.dll" "${BOOST_BIN_DIR}/*boost_container*.dll")
        foreach(DLL ${BOOST_DLLS})
            add_custom_command(TARGET SyncAssets POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy_if_different "${DLL}" "$<TARGET_FILE_DIR:OmniEncrypt>"
                COMMENT "Copying Boost DLL: ${DLL}"
            )
        endforeach()
    endif()
elseif(UNIX AND NOT APPLE)
    add_custom_command(TARGET SyncAssets POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/OmniUtils/libOmniUtils.so" "$<TARGET_FILE_DIR:OmniEncrypt>"
    )
endif()

add_dependencies(SyncAssets OmniEncrypt)
