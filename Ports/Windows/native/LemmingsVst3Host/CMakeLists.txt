cmake_minimum_required(VERSION 3.22)
project(LemmingsVst3Host VERSION 2.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

include(FetchContent)

if(DEFINED ENV{LEMMINGS_JUCE_DIR} AND EXISTS "$ENV{LEMMINGS_JUCE_DIR}/CMakeLists.txt")
    message(STATUS "Using JUCE from LEMMINGS_JUCE_DIR=$ENV{LEMMINGS_JUCE_DIR}")
    add_subdirectory("$ENV{LEMMINGS_JUCE_DIR}" "${CMAKE_BINARY_DIR}/JUCE")
else()
    message(STATUS "Fetching JUCE for native VST3 host. Set LEMMINGS_JUCE_DIR to use a local checkout/cache.")
    FetchContent_Declare(
        JUCE
        GIT_REPOSITORY https://github.com/juce-framework/JUCE.git
        GIT_TAG 8.0.8
        GIT_SHALLOW TRUE
    )
    FetchContent_MakeAvailable(JUCE)
endif()

juce_add_console_app(LemmingsVst3Host
    PRODUCT_NAME "LemmingsVst3Host"
    VERSION "2.0.0"
    COMPANY_NAME "MagmaVance LLC"
)

target_sources(LemmingsVst3Host PRIVATE src/Main.cpp)

target_compile_definitions(LemmingsVst3Host PRIVATE
    JUCE_PLUGINHOST_VST3=1
    JUCE_PLUGINHOST_AU=0
    JUCE_PLUGINHOST_LADSPA=0
    JUCE_PLUGINHOST_LV2=0
    JUCE_USE_CURL=0
    JUCE_WEB_BROWSER=0
    JUCE_DISPLAY_SPLASH_SCREEN=0
    JUCE_REPORT_APP_USAGE=0
    JUCE_MODAL_LOOPS_PERMITTED=1
    NOMINMAX=1
)

target_link_libraries(LemmingsVst3Host PRIVATE
    juce::juce_audio_utils
    juce::juce_audio_processors
    juce::juce_audio_devices
    juce::juce_gui_extra
    juce::juce_recommended_config_flags
    juce::juce_recommended_warning_flags
)

set_target_properties(LemmingsVst3Host PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/out"
)
