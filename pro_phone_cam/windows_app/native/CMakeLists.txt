cmake_minimum_required(VERSION 3.14)
project(prophone_cam_driver LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(prophone_cam_driver SHARED
    virtual_cam.cpp
)

target_compile_definitions(prophone_cam_driver PRIVATE PROPHONE_EXPORTS)
target_link_libraries(prophone_cam_driver PRIVATE advapi32 user32)

set_target_properties(prophone_cam_driver PROPERTIES
    OUTPUT_NAME "prophone_cam_driver"
    PREFIX ""
)
