# CMakeUnitRunner.cmake
#
# The main test runner for the CMakeUnit framework.
#
# Users should first call bootstrap_cmake_unit which will
# set up some necessary global variables. Tests are organized
# into test scripts (because CMake doesn't have the ability to
# refer to function names as variables and call them later).
#
# As a performance consideration, there are two types of tests,
# CMake tests and Build Tests.
#
# CMake tests should be added with add_cmake_test . These tests
# will only run cmake in script-execution mode on the specified
# script and check for success.
#
# Build tests are a superset of CMake tests. They will run cmake
# on the specified script, but also use cmake --build to build
# the resulting project and then run the verfication script
# specified in order to check that the build succeeded in the
# way that the user expected it to. Build tests can take
# much longer to execute and should be used sparingly.
#
# See LICENCE.md for Copyright information.

# bootstrap_cmake_unit:
#
# Defines some global variables for the CMakeUnit framework. Pass
# VARIABLES to forward those variables to tests.
include (CMakeParseArguments)
include (CMakeUnit)
include (CTest)

enable_testing ()

option (CMAKE_UNIT_LOG_COVERAGE OFF
        "Log line hits to ${CMAKE_PROJECT_NAME}.trace")
option (CMAKE_UNIT_NO_DEV_WARNINGS OFF
        "Turn off developer warnings")
option (CMAKE_UNIT_NO_UNINITIALIZED_WARNINGS OFF
        "Turn off uninitialized variable usage warnings")

if (CMAKE_UNIT_LOG_COVERAGE)

    set (CMAKE_UNIT_COVERAGE_FILE
         "${CMAKE_CURRENT_BINARY_DIR}/${CMAKE_PROJECT_NAME}.trace")

endif (CMAKE_UNIT_LOG_COVERAGE)

# bootstrap_cmake_unit
#
# Sets up the initial environment to use cmake-unit. Call this function
# before calling add_cmake_test or add_cmake_build_test.
#
# VARIABLES: A list of variables to "forward" on to the tests with the same
#            value that they have at the time of calling bootstrap_cmake_unit
# COVERAGE_FILES: A list of full absolute paths to files which should
#                 be tracked for code coverage.
function (bootstrap_cmake_unit)

    set (BOOTSTRAP_MULTIVAR_ARGS VARIABLES COVERAGE_FILES)

    cmake_parse_arguments (BOOTSTRAP
                           ""
                           ""
                           "${BOOTSTRAP_MULTIVAR_ARGS}"
                           ${ARGN})

    # Put variables we want to forward to the tests into their cache
    foreach (VAR ${BOOTSTRAP_VARIABLES})

        get_property (TYPE
                      CACHE ${VAR}
                      PROPERTY TYPE)

        if (NOT TYPE STREQUAL "STRING" OR
            NOT TYPE STREQUAL "BOOL" OR
            NOT TYPE STREQUAL "PATH" OR
            NOT TYPE STREQUAL "FILEPATH")

            # If the variable is not part of the "public" cache, then
            # we can still forward it, but we need to set a type of "STRING"
            set (TYPE STRING)

        endif (NOT TYPE STREQUAL "STRING" OR
               NOT TYPE STREQUAL "BOOL" OR
               NOT TYPE STREQUAL "PATH" OR
               NOT TYPE STREQUAL "FILEPATH")

        # This needs to be squeezed all on to one line so that we don't get
        # semicolonization from having multiple strings in the set () command
        set (ICC "${ICC}set (${VAR} \"${${VAR}}\" CACHE ${TYPE} \"\" FORCE)\n")

    endforeach ()

    # Escape semicolons
    string (REPLACE ";" "/;" ICC "${ICC}")
    set (_CMAKE_UNIT_INITIAL_CACHE_CONTENTS "${ICC}" PARENT_SCOPE)

    if (CMAKE_UNIT_LOG_COVERAGE)

        # Escape characters out of filenames that will cause problems when
        # attempting to regex match them later
        foreach (COVERAGE_FILE ${BOOTSTRAP_COVERAGE_FILES})

            cmake_unit_escape_string ("${COVERAGE_FILE}" ESCAPED_COVERAGE_FILE)
            list (APPEND ESCAPED_COVERAGE_FILES "${ESCAPED_COVERAGE_FILE}")

        endforeach ()

        set (_CMAKE_UNIT_COVERAGE_LOGGING_FILES
             ${ESCAPED_COVERAGE_FILES} PARENT_SCOPE)

        # Clobber the coverage report
        file (WRITE "${CMAKE_UNIT_COVERAGE_FILE}" "")

    endif (CMAKE_UNIT_LOG_COVERAGE)

endfunction (bootstrap_cmake_unit)

macro (_define_variables_for_test TEST_NAME)

    set (TEST_FILE "${TEST_NAME}.cmake")
    set (TEST_DIRECTORY_NAME "${CMAKE_CURRENT_BINARY_DIR}/${TEST_NAME}")
    set (TEST_WORKING_DIRECTORY_NAME "${TEST_DIRECTORY_NAME}/build")
    set (TEST_DRIVER_SCRIPT
         "${TEST_DIRECTORY_NAME}/${TEST_NAME}Driver.cmake")
    set (TEST_DRIVER_SCRIPT_CONTENTS)
    set (TEST_INITIAL_CACHE_FILE
         "${TEST_DIRECTORY_NAME}/initial_cache.cmake")

endmacro (_define_variables_for_test)

function (_bootstrap_test_driver_script TEST_NAME
                                        PARENT_DRIVER_SCRIPT_CONTENTS)

    file (MAKE_DIRECTORY "${TEST_DIRECTORY_NAME}")
    file (MAKE_DIRECTORY "${TEST_WORKING_DIRECTORY_NAME}")
    set (DRIVER_SCRIPT_CONTENTS ${${PARENT_DRIVER_SCRIPT_CONTENTS}})
    list (APPEND DRIVER_SCRIPT_CONTENTS
         "include (CMakeParseArguments)\n"
         "function (add_driver_command STEP\n"
         "                             OUTPUT_RETURN\n"
         "                             ERROR_RETURN\n"
         "                             RESULT_RETURN)\n"
         "    set (ADD_COMMAND_OPTION_ARGS ALLOW_FAIL)\n"
         "    set (ADD_COMMAND_MULTIVAR_ARGS COMMAND)\n"
         "    cmake_parse_arguments (ADD_COMMAND\n"
         "                           \"\${ADD_COMMAND_OPTION_ARGS}\"\n"
         "                           \"\"\n"
         "                           \"\${ADD_COMMAND_MULTIVAR_ARGS}\"\n"
         "                           \${ARGN})\n"
         "    string (REPLACE \"@SEMICOLON@\" \" \"\n"
         "            STRINGIFIED_COMMAND \"\${ADD_COMMAND_COMMAND}\")\n"
         "    message (STATUS \"Running \${STRINGIFIED_COMMAND}\")\n"
         "    execute_process (COMMAND \${ADD_COMMAND_COMMAND}\n"
         "                     WORKING_DIRECTORY\n"
         "                     \"${TEST_WORKING_DIRECTORY_NAME}\"\n"
         "                     RESULT_VARIABLE RESULT\n"
         "                     OUTPUT_VARIABLE OUTPUT\n"
         "                     ERROR_VARIABLE ERROR)\n"
         "    if (RESULT EQUAL 0 OR ADD_COMMAND_ALLOW_FAIL)\n"
         "        message (\"\\n\${OUTPUT}\\n\${ERROR}\")\n"
         "    else (RESULT EQUAL 0 OR ADD_COMMAND_ALLOW_FAIL)\n"
         "        message (FATAL_ERROR \n"
         "                 \"The command \${STRINGIFIED_COMMAND}\"\n"
         "                 \" failed with \${RESULT}\"\n"
         "                 \"\\n\${ERROR}\\n\${OUTPUT}\")\n"
         "    endif (RESULT EQUAL 0 OR ADD_COMMAND_ALLOW_FAIL)\n"
         "    set (OUTPUT_LOG\n"
         "         \"${TEST_WORKING_DIRECTORY_NAME}/\${STEP}.output\")\n"
         "    set (ERROR_LOG\n"
         "         \"${TEST_WORKING_DIRECTORY_NAME}/\${STEP}.error\")\n"
         "    file (WRITE\n"
         "          \"\${OUTPUT_LOG}\"\n"
         "          \"Output:\\n\"\n"
         "          \${OUTPUT})\n"
         "    file (WRITE\n"
         "          \"\${ERROR_LOG}\"\n"
         "          \"Errors:\\n\"\n"
         "          \${ERROR})\n"
         "    set (\${OUTPUT_RETURN} \"\${OUTPUT}\" PARENT_SCOPE)\n"
         "    set (\${ERROR_RETURN} \"\${ERROR}\" PARENT_SCOPE)\n"
         "    set (\${RESULT_RETURN} \"\${RESULT}\" PARENT_SCOPE)\n"
         "endfunction (add_driver_command)\n")

    set (${PARENT_DRIVER_SCRIPT_CONTENTS} ${DRIVER_SCRIPT_CONTENTS}
         PARENT_SCOPE)

endfunction (_bootstrap_test_driver_script)

function (_add_driver_step ADD_STEP_PARENT_DRIVER_SCRIPT_CONTENTS STEP)

    set (DRIVER_STEP_OPTION_ARGS ALLOW_FAIL)
    set (DRIVER_STEP_MULTIVAR_ARGS COMMAND)

    cmake_parse_arguments (ADD_DRIVER_STEP
                           "${DRIVER_STEP_OPTION_ARGS}"
                           ""
                           "${DRIVER_STEP_MULTIVAR_ARGS}"
                           ${ARGN})

    if (NOT ADD_DRIVER_STEP_COMMAND)

        message (FATAL_ERROR "A COMMAND must be provided to add_driver_step")

    endif (NOT ADD_DRIVER_STEP_COMMAND)

    if (ADD_DRIVER_STEP_ALLOW_FAIL)

        set (ALLOW_FAIL ALLOW_FAIL)

    else (ADD_DRIVER_STEP_ALLOW_FAIL)

        set (ALLOW_FAIL "")

    endif (ADD_DRIVER_STEP_ALLOW_FAIL)

    # When we pass ADD_DRIVER_STEP_COMMAND into this string, it will appear to
    # just be a space-separated string, which will have each element converted
    # into a list element. That's obviously not what we want, so we instead
    # create a string with escaped quotes for each item that we want to put
    # on the commandline and then append that to our script.
    foreach (ARGUMENT ${ADD_DRIVER_STEP_COMMAND})

        list (APPEND STRINGIFIED_ARGS "\"${ARGUMENT}\"")

    endforeach ()

    # Ensure that the list expands with spaces and not semicolons
    string (REPLACE ";" " " STRINGIFIED_ARGS "${STRINGIFIED_ARGS}")

    set (WORKING_DIRECTORY "${TEST_WORKING_DIRECTORY_NAME}")
    set (DRIVER_SCRIPT_CONTENTS ${${ADD_STEP_PARENT_DRIVER_SCRIPT_CONTENTS}})
    list (APPEND DRIVER_SCRIPT_CONTENTS
          "add_driver_command (${STEP}\n"
          "                    ${STEP}_OUTPUT\n"
          "                    ${STEP}_ERROR\n"
          "                    ${STEP}_RESULT\n"
          "                    COMMAND ${STRINGIFIED_ARGS}\n"
          "                    ${ALLOW_FAIL})\n")
    set (${ADD_STEP_PARENT_DRIVER_SCRIPT_CONTENTS} ${DRIVER_SCRIPT_CONTENTS}
         PARENT_SCOPE)

endfunction (_add_driver_step)

function (_define_test_for_driver TEST_NAME DRIVER_SCRIPT)

    set (DEFINE_TEST_FOR_DRIVER_MULTIVAR_ARGS CONTENTS)
    cmake_parse_arguments (DEFINE_TEST_FOR_DRIVER
                           ""
                           ""
                           "${DEFINE_TEST_FOR_DRIVER_MULTIVAR_ARGS}"
                           ${ARGN})

    if (NOT DEFINE_TEST_FOR_DRIVER_CONTENTS)

        message (FATAL_ERROR "Test driver script must have contents")

    endif (NOT DEFINE_TEST_FOR_DRIVER_CONTENTS)

    string (REPLACE "@SEMICOLON@" "\;" DEFINE_TEST_FOR_DRIVER_CONTENTS
            "${DEFINE_TEST_FOR_DRIVER_CONTENTS}")
    file (WRITE "${DRIVER_SCRIPT}"
          ${DEFINE_TEST_FOR_DRIVER_CONTENTS})
    file (WRITE "${TEST_INITIAL_CACHE_FILE}"
          "${_CMAKE_UNIT_INITIAL_CACHE_CONTENTS}")

    add_test (NAME ${TEST_NAME}
              COMMAND
              ${CMAKE_COMMAND} -P "${DRIVER_SCRIPT}"
              WORKING_DIRECTORY "${TEST_DIRECTORY_NAME}")

endfunction (_define_test_for_driver)

function (_append_clean_step PARENT_DRIVER_SCRIPT_CONTENTS
                             TEST_WORKING_DIRECTORY_NAME)

    set (DRIVER_SCRIPT_CONTENTS ${${PARENT_DRIVER_SCRIPT_CONTENTS}})
    list (APPEND DRIVER_SCRIPT_CONTENTS
          "file (REMOVE_RECURSE \"${TEST_WORKING_DIRECTORY_NAME}\")\n"
          "file (MAKE_DIRECTORY \"${TEST_WORKING_DIRECTORY_NAME}\")\n")
    set (${PARENT_DRIVER_SCRIPT_CONTENTS} ${DRIVER_SCRIPT_CONTENTS}
         PARENT_SCOPE)

endfunction (_append_clean_step)

function (_append_configure_step TEST_NAME
                                 PARENT_DRIVER_SCRIPT_CONTENTS
                                 CACHE_FILE
                                 TEST_DIRECTORY_NAME
                                 TEST_WORKING_DIRECTORY_NAME
                                 TEST_FILE)

    set (CONFIGURE_STEP_OPTION_ARGS ALLOW_FAIL ALLOW_WARNINGS)

    cmake_parse_arguments (CONFIGURE_STEP
                           "${CONFIGURE_STEP_OPTION_ARGS}"
                           ""
                           ""
                           ${ARGN})

    set (TEST_FILE_PATH
         ${CMAKE_CURRENT_SOURCE_DIR}/${TEST_FILE})

    if (EXISTS ${TEST_FILE_PATH})

        set (TEST_DIRECTORY_CONFIGURE_SCRIPT
             "${TEST_DIRECTORY_NAME}/CMakeLists.txt")
        set (TEST_DIRECTORY_CONFIGURE_SCRIPT_CONTENTS
             "cmake_minimum_required (VERSION 2.8 FATAL_ERROR)\n"
             "if (POLICY CMP0042)\n"
             "  cmake_policy (SET CMP0042 NEW)\n"
             "endif (POLICY CMP0042)\n"
             "if (POLICY CMP0025)\n"
             "  cmake_policy (SET CMP0025 NEW)\n"
             "endif (POLICY CMP0025)\n"
             "project (TestProject CXX C)\n"
             "include (\"${CMAKE_CURRENT_SOURCE_DIR}/${TEST_FILE}\")\n")

        file (WRITE "${TEST_DIRECTORY_CONFIGURE_SCRIPT}"
              ${TEST_DIRECTORY_CONFIGURE_SCRIPT_CONTENTS})

        set (ALLOW_FAIL_OPTION "")

        # Whether to allow failures in the configure step
        if (CONFIGURE_STEP_ALLOW_FAIL)

            set (ALLOW_FAIL_OPTION ALLOW_FAIL)

        endif (CONFIGURE_STEP_ALLOW_FAIL)

        # Set GENERATOR
        string (REPLACE " " "\\ " GENERATOR ${CMAKE_GENERATOR})

        set (TRACE_OPTION "")
        set (UNINITIALIZED_OPTION "")
        set (UNUSED_VARIABLE_OPTION "")
        set (DEVELOPER_WARNINGS_OPTION "-Wno-dev")

        # Whether coverage is being logged pass the --trace switch
        if (CMAKE_UNIT_LOG_COVERAGE)

            set (TRACE_OPTION "--trace")

        endif (CMAKE_UNIT_LOG_COVERAGE)

        if (NOT CMAKE_UNIT_NO_UNINITIALIZED_WARNINGS)

            set (UNINITIALIZED_OPTION "--warn-uninitialized")

        endif (NOT CMAKE_UNIT_NO_UNINITIALIZED_WARNINGS)

        if (NOT CMAKE_UNIT_NO_DEV_WARNINGS)

            set (DEVELOPER_WARNINGS_OPTION "-Wdev")

        endif (NOT CMAKE_UNIT_NO_DEV_WARNINGS)

        set (CONFIGURE_COMMAND
             "${CMAKE_COMMAND}"
             "${TRACE_OPTION}"
             "${UNINITIALIZED_OPTION}"
             "${UNUSED_VARIABLE_OPTION}"
             "${DEVELOPER_WARNINGS_OPTION}"
             "${TEST_DIRECTORY_NAME}"
             "-C${CACHE_FILE}"
             -DCMAKE_VERBOSE_MAKEFILE=ON
             "-G${GENERATOR}")
        set (DRIVER_SCRIPT_CONTENTS ${${PARENT_DRIVER_SCRIPT_CONTENTS}})
        _add_driver_step (DRIVER_SCRIPT_CONTENTS CONFIGURE
                          COMMAND ${CONFIGURE_COMMAND}
                          ${ALLOW_FAIL_OPTION})


        # After we've added the driver step, read back CONFIGURE.error
        # and filter through each of the lines to find "coverage" lines,
        # logging them into the main CMAKE_UNIT_COVERAGE_FILE
        list (APPEND DRIVER_SCRIPT_CONTENTS
              # Reduce IO by buffering in memory
              "set (COVERAGE_FILE_CONTENTS \"\")\n")

        if (CMAKE_UNIT_LOG_COVERAGE)

            # We need to make sure that the quotes around our coverage
            # files get passed back down to the driver script
            foreach (FILE ${_CMAKE_UNIT_COVERAGE_LOGGING_FILES})

                list (APPEND COVERAGE_FILES "\"${FILE}\"")

            endforeach ()

            # Now replace list semicolons with spaces. The result will be
            # that this is a valid list when parsed by CMake in the second
            # stage
            string (REPLACE ";" " " COVERAGE_FILES "${COVERAGE_FILES}")

            # First write out the name of this test and all the files
            # we will be covering
            list (APPEND DRIVER_SCRIPT_CONTENTS
                  "list (APPEND\n"
                  "      COVERAGE_FILE_CONTENTS\n"
                  "      \"TEST:${TEST_NAME}\\n\")\n"
                  "set (COVERAGE_FILES ${COVERAGE_FILES})\n"
                  "foreach (FILE \${COVERAGE_FILES})\n"
                  "    list (APPEND COVERAGE_FILE_CONTENTS\n"
                  "          \"FILE:\${FILE}\\n\")\n"
                  "endforeach ()\n")

        endif (CMAKE_UNIT_LOG_COVERAGE)

        list (APPEND DRIVER_SCRIPT_CONTENTS
              "set (CONFIGURE_TRACE_CONTENTS\n"
              "     \"\${CONFIGURE_ERROR}\")\n"
              # This is a tedious way to iterate through lines of a string
              # though it is more reliable than trying to make the string
              # into a list by converting \n to ;, especially since
              # there appears to be a cap on the number of elements
              # that can go into a list.
              #
              # Just keep going through through the string finding \n
              # and scan each line as we go. Save everything past the
              # found index in the same variable again.
              "set (NEXT_LINE_INDEX 0)\n"
              "while (NOT NEXT_LINE_INDEX EQUAL -1)\n"
              "    string (SUBSTRING \"\${CONFIGURE_TRACE_CONTENTS}\"\n"
              "            \${NEXT_LINE_INDEX} -1\n"
              "            CONFIGURE_TRACE_CONTENTS)\n"
              "    string (FIND \"\${CONFIGURE_TRACE_CONTENTS}\" \"\\n\"\n"
              "            NEXT_LINE_INDEX)\n"
              "    if (NOT NEXT_LINE_INDEX EQUAL -1)\n"
              # Take a substring of what we have now and test it for
              # whether it matches one of the paths in our COVERAGE_FILES
              "        string (SUBSTRING \"\${CONFIGURE_TRACE_CONTENTS}\"\n"
              "                0 \${NEXT_LINE_INDEX} LINE)\n")

        if (NOT CONFIGURE_STEP_ALLOW_WARNINGS)

            # Don't tolerate warings in the configure phase
            list (APPEND DRIVER_SCRIPT_CONTENTS
                  "        if (\"\${LINE}\"\n"
                  "            MATCHES \"^CMake Warning.*$\")\n"
                  "            message (FATAL_ERROR\n"
                  "                     \"CMake Warnings were present:\")\n"
                  "        endif (\"\${LINE}\"\n"
                  "               MATCHES \"^CMake Warning.*$\")\n")

        endif (NOT CONFIGURE_STEP_ALLOW_WARNINGS)

        if (CMAKE_UNIT_LOG_COVERAGE)

            list (APPEND DRIVER_SCRIPT_CONTENTS
                  # Ignore CMake Warning|Error and anything starting with
                  # two spaces
                  "        if (NOT \"\${LINE}\" MATCHES\n"
                  "            \"^CMake (Warning|Error).*$\" AND\n"
                  "            NOT \"\${LINE}\" MATCHES\n"
                  "            \"^  .*$\")\n"
                  "            foreach (FILE \${COVERAGE_FILES})\n"
                  "                if (\"\${LINE}\" MATCHES \"^\${FILE}.*$\")\n"
                  # Once we've found a matching line, strip out the rest of
                  # the mostly useless information. Find the first ":" after
                  # the filename and then write out the string until that
                  # semicolon is reached
                  "                    string (LENGTH \"${FILE}\" F_LEN)\n"
                  "                    string (SUBSTRING \"\${LINE}\"\n"
                  "                            \${F_LEN} -1\n"
                  "                            AFTER_FILE_STRING)\n"
                  # Match ):. This prevents drive letters on Windows causing
                  # problems
                  "                    string (FIND \"\${AFTER_FILE_STRING}\"\n"
                  "                            \"):\" DEL_IDX)\n"
                  "                    math (EXPR COLON_INDEX_IN_LINE\n"
                  "                          \"\${F_LEN} + \${DEL_IDX} + 1\")\n"
                  "                    string (SUBSTRING \"\${LINE}\"\n"
                  "                            0 \${COLON_INDEX_IN_LINE}\n"
                  "                            FILENAME_AND_LINE)\n"
                  "                    list (APPEND\n"
                  "                          COVERAGE_FILE_CONTENTS\n"
                  "                          \"\${FILENAME_AND_LINE}\\n\")\n"
                  "               endif ()\n"
                  "            endforeach ()\n"
                  "        endif ()\n")

        endif (CMAKE_UNIT_LOG_COVERAGE)

        # Increment NEXT_LINE_INDEX so that we can take a new
        # substring without the \n and check for the next one
        list (APPEND DRIVER_SCRIPT_CONTENTS
              "        math (EXPR NEXT_LINE_INDEX\n"
              "              \"\${NEXT_LINE_INDEX} + 1\")\n"
              "    endif (NOT NEXT_LINE_INDEX EQUAL -1)\n"
              "endwhile ()\n")

        if (CMAKE_UNIT_LOG_COVERAGE)

            # Append to coverage file
            list (APPEND DRIVER_SCRIPT_CONTENTS
                  "file (APPEND \"${CMAKE_UNIT_COVERAGE_FILE}\"\n"
                  "      \${COVERAGE_FILE_CONTENTS})\n")

        endif (CMAKE_UNIT_LOG_COVERAGE)

        set (${PARENT_DRIVER_SCRIPT_CONTENTS} ${DRIVER_SCRIPT_CONTENTS}
             PARENT_SCOPE)

    else (EXISTS ${TEST_FILE_PATH})

        message (SEND_ERROR "The file ${TEST_FILE_PATH} must exist"
                            " in order for the configure step to run")

    endif (EXISTS ${TEST_FILE_PATH})

endfunction (_append_configure_step)

function (_append_build_step PARENT_DRIVER_SCRIPT_CONTENTS
                             TEST_WORKING_DIRECTORY_NAME
                             TARGET)

    set (BUILD_STEP_OPTION_ARGS ALLOW_FAIL)

    cmake_parse_arguments (BUILD_STEP
                           "${BUILD_STEP_OPTION_ARGS}"
                           ""
                           ""
                           ${ARGN})

    set (ALLOW_FAIL_OPTION "")

    if (BUILD_STEP_ALLOW_FAIL)

        set (ALLOW_FAIL_OPTION ALLOW_FAIL)

    endif (BUILD_STEP_ALLOW_FAIL)

    # The "all" target is special. It means "do whatever happens by
    # default". Some build systems literally have a target called
    # "all", but others (Xcode) don't, so in that case, just don't
    # add a --target.
    if ("${TARGET}" STREQUAL "all")

        set (TARGET_OPTION "")

    else ("${TARGET}" STREQUAL "all")

        set (TARGET_OPTION --target ${TARGET})

    endif ("${TARGET}" STREQUAL "all")

    if ("${CMAKE_MAKE_PROGRAM}" MATCHES ".*ninja.*")

        set (BUILD_TOOL_VERBOSE_OPTION "-v")

    endif ("${CMAKE_MAKE_PROGRAM}" MATCHES ".*ninja.*")

    set (BUILD_COMMAND "${CMAKE_COMMAND}"
                       --build
                       "${TEST_WORKING_DIRECTORY_NAME}"
                       ${TARGET_OPTION}
                       --
                       "${BUILD_TOOL_VERBOSE_OPTION}")
    set (DRIVER_SCRIPT_CONTENTS ${${PARENT_DRIVER_SCRIPT_CONTENTS}})
    _add_driver_step (DRIVER_SCRIPT_CONTENTS BUILD
                      COMMAND ${BUILD_COMMAND}
                      ${ALLOW_FAIL_OPTION})
    set (${PARENT_DRIVER_SCRIPT_CONTENTS} ${DRIVER_SCRIPT_CONTENTS}
         PARENT_SCOPE)

endfunction (_append_build_step)

function (_append_test_step PARENT_DRIVER_SCRIPT_CONTENTS)

    set (TEST_STEP_OPTION_ARGS ALLOW_FAIL)

    cmake_parse_arguments (TEST_STEP
                           "${TEST_STEP_OPTION_ARGS}"
                           ""
                           ""
                           ${ARGN})

    set (ALLOW_FAIL_OPTION "")

    if (TEST_STEP_ALLOW_FAIL)

        set (ALLOW_FAIL_OPTION ALLOW_FAIL)

    endif (TEST_STEP_ALLOW_FAIL)

    set (TEST_COMMAND "${CMAKE_CTEST_COMMAND}"
                       -C Debug
                       -VV)
    set (DRIVER_SCRIPT_CONTENTS ${${PARENT_DRIVER_SCRIPT_CONTENTS}})
    _add_driver_step (DRIVER_SCRIPT_CONTENTS TEST
                      COMMAND ${TEST_COMMAND}
                      ${ALLOW_FAIL_OPTION})
    set (${PARENT_DRIVER_SCRIPT_CONTENTS} ${DRIVER_SCRIPT_CONTENTS}
         PARENT_SCOPE)

endfunction (_append_test_step)

function (_append_verify_step PARENT_DRIVER_SCRIPT_CONTENTS
                              CACHE_FILE
                              VERIFY)

    set (TEST_VERIFY_SCRIPT_FILE
         "${CMAKE_CURRENT_SOURCE_DIR}/${VERIFY}.cmake")

    if (EXISTS ${TEST_VERIFY_SCRIPT_FILE})

        set (VERIFY_COMMAND
             "${CMAKE_COMMAND}"
             "-C${CACHE_FILE}"
             -P "${TEST_VERIFY_SCRIPT_FILE}")
        set (DRIVER_SCRIPT_CONTENTS ${${PARENT_DRIVER_SCRIPT_CONTENTS}})
        _add_driver_step (DRIVER_SCRIPT_CONTENTS VERIFY
                          COMMAND ${VERIFY_COMMAND})
        set (${PARENT_DRIVER_SCRIPT_CONTENTS} ${DRIVER_SCRIPT_CONTENTS}
             PARENT_SCOPE)

    else (EXISTS ${TEST_VERIFY_SCRIPT_FILE})

        message (SEND_ERROR "The file ${TEST_VERIFY_SCRIPT_FILE} must exist"
                            " in order for the verify step to run")

    endif (EXISTS ${TEST_VERIFY_SCRIPT_FILE})

endfunction (_append_verify_step)

# add_cmake_test:
#
# Adds a test with just the configure step. If the test script
# exits with an error then the test fails.
function (add_cmake_test TEST_NAME)

    _define_variables_for_test (${TEST_NAME})
    _bootstrap_test_driver_script(${TEST_NAME}
                                  TEST_DRIVER_SCRIPT_CONTENTS
                                  "${TEST_INITIAL_CACHE_FILE}")
    _append_clean_step (TEST_DRIVER_SCRIPT_CONTENTS
                        "${TEST_WORKING_DIRECTORY_NAME}")
    _append_configure_step (${TEST_NAME}
                            TEST_DRIVER_SCRIPT_CONTENTS
                            "${TEST_INITIAL_CACHE_FILE}"
                            "${TEST_DIRECTORY_NAME}"
                            "${TEST_WORKING_DIRECTORY_NAME}"
                            "${TEST_FILE}")
    _define_test_for_driver (${TEST_NAME}
                             "${TEST_DRIVER_SCRIPT}"
                             CONTENTS ${TEST_DRIVER_SCRIPT_CONTENTS})

endfunction (add_cmake_test)

# add_cmake_build_test:
#
# Adds a test with three steps, a "configure", "build", "test" and "verify"
# step. This will run some checks at the configure phase, then build and test
# the configured project and then run the script specified by
# VERIFY to ensure that the project built correctly.
function (add_cmake_build_test TEST_NAME VERIFY)

    set (ADD_CMAKE_BUILD_TEST_OPTION_ARGS
         ALLOW_CONFIGURE_FAIL
         ALLOW_CONFIGURE_WARNINGS
         ALLOW_BUILD_FAIL
         ALLOW_TEST_FAIL
         NO_CLEAN)
    set (ADD_CMAKE_BUILD_TEST_SINGLEVAR_ARGS
         TARGET)
    set (ADD_CMAKE_BUILD_TEST_MULTIVAR_ARGS)

    cmake_parse_arguments (ADD_CMAKE_BUILD_TEST
                           "${ADD_CMAKE_BUILD_TEST_OPTION_ARGS}"
                           "${ADD_CMAKE_BUILD_TEST_SINGLEVAR_ARGS}"
                           "${ADD_CMAKE_BUILD_TEST_MULTIVAR_ARGS}"
                           ${ARGN})

    set (ALLOW_BUILD_FAIL_OTION "")
    set (ALLOW_CONFIGURE_FAIL_OPTION "")

    if (NOT ADD_CMAKE_BUILD_TEST_TARGET)

        set (ADD_CMAKE_BUILD_TEST_TARGET all)

    endif (NOT ADD_CMAKE_BUILD_TEST_TARGET)

    if (ADD_CMAKE_BUILD_TEST_ALLOW_CONFIGURE_WARNINGS)

        set (ALLOW_CONFIGURE_WARNINGS_OPTION ALLOW_WARNINGS)

    endif (ADD_CMAKE_BUILD_TEST_ALLOW_CONFIGURE_WARNINGS)

    if (ADD_CMAKE_BUILD_TEST_ALLOW_CONFIGURE_FAIL)

        set (ALLOW_CONFIGURE_FAIL_OPTION ALLOW_FAIL)
        set (ADD_CMAKE_BUILD_TEST_ALLOW_BUILD_FAIL ON)

    endif (ADD_CMAKE_BUILD_TEST_ALLOW_CONFIGURE_FAIL)

    if (ADD_CMAKE_BUILD_TEST_ALLOW_BUILD_FAIL)

        set (ALLOW_BUILD_FAIL_OPTION ALLOW_FAIL)
        set (ADD_CMAKE_BUILD_TEST_ENSURE_TEST_SUCCESS OFF)

    endif (ADD_CMAKE_BUILD_TEST_ALLOW_BUILD_FAIL)

    if (ADD_CMAKE_BUILD_TEST_ALLOW_TEST_FAIL)

        set (ALLOW_TEST_FAIL_OPTION ALLOW_FAIL)

    endif (ADD_CMAKE_BUILD_TEST_ALLOW_TEST_FAIL)

    _define_variables_for_test (${TEST_NAME})
    _bootstrap_test_driver_script(${TEST_NAME}
                                  TEST_DRIVER_SCRIPT_CONTENTS
                                  "${TEST_INITIAL_CACHE_FILE}")

    if (NOT ADD_CMAKE_BUILD_TEST_NO_CLEAN)

      _append_clean_step (TEST_DRIVER_SCRIPT_CONTENTS
                          "${TEST_WORKING_DIRECTORY_NAME}")

    endif (NOT ADD_CMAKE_BUILD_TEST_NO_CLEAN)

    _append_configure_step (${TEST_NAME}
                            TEST_DRIVER_SCRIPT_CONTENTS
                            "${TEST_INITIAL_CACHE_FILE}"
                            "${TEST_DIRECTORY_NAME}"
                            "${TEST_WORKING_DIRECTORY_NAME}"
                            "${TEST_FILE}"
                            ${ALLOW_CONFIGURE_FAIL_OPTION}
                            ${ALLOW_CONFIGURE_WARNINGS_OPTION})

    # Can't build if the configure step is allowed to fail
    if (NOT ADD_CMAKE_BUILD_TEST_ALLOW_CONFIGURE_FAIL)

        _append_build_step (TEST_DRIVER_SCRIPT_CONTENTS
                            "${TEST_WORKING_DIRECTORY_NAME}"
                            ${ADD_CMAKE_BUILD_TEST_TARGET}
                            ${ALLOW_BUILD_FAIL_OPTION}
                            ${NO_CLEAN_OPTION})

    endif (NOT ADD_CMAKE_BUILD_TEST_ALLOW_CONFIGURE_FAIL)

    # Can't test the project if the build step is allowed to fail
    if (NOT ADD_CMAKE_BUILD_TEST_ALLOW_BUILD_FAIL)

        _append_test_step (TEST_DRIVER_SCRIPT_CONTENTS
                           ${ALLOW_TEST_FAIL_OPTION})

    endif (NOT ADD_CMAKE_BUILD_TEST_ALLOW_BUILD_FAIL)

    _append_verify_step (TEST_DRIVER_SCRIPT_CONTENTS
                         "${TEST_INITIAL_CACHE_FILE}"
                         ${VERIFY})
    _define_test_for_driver (${TEST_NAME}
                             "${TEST_DRIVER_SCRIPT}"
                             CONTENTS ${TEST_DRIVER_SCRIPT_CONTENTS})

endfunction (add_cmake_build_test)
