#!/bin/bash

################################################################################
# mobilityDCAT-AP Validator Script
#
# This script validates RDF metadata files against mobilityDCAT-AP SHACL shapes
# by invoking the REST API of the SHACL validator.
#
# Supports both single file and batch (directory) validation, against a single
# profile or all the profiles of a mobilityDCAT-AP version.
#
# Usage:
#   Single file:    ./validate-metadata.sh <file> <validation-type> [profile] [output-format] [validator-url] [output-directory]
#   Batch mode:     ./validate-metadata.sh <directory> <validation-type> [profile] [output-format] [validator-url] [output-directory]
#
# Arguments:
#   file/directory  Path to an RDF file or directory containing RDF files (required)
#   validation-type Version (e.g., "v1.1.0", "v3.0.0") or full validation type
#                   (e.g., "v3.0.0.core_import") (required)
#   profile         Validation profile (default: core, ignored for v1.0.0 and v1.0.1)
#                   v1.1.0: core, range, full, cv
#                   v3.0.0: core, core_import, range, range_import, full,
#                           full_import, cv, cv_import, deprecated
#                   all:    all the profiles of the version
#                   Use "" to keep the default when passing further arguments.
#   output-format   Report format (default: application/json)
#                   Options: text/turtle, application/rdf+xml, application/json, application/xml
#   validator-url   Base URL of validator (default: http://localhost:8080)
#   output-dir      Directory for reports (default: ./validation-reports)
#
# Reports are saved as <output-dir>/<file name>-<validation type>-report.<ext>
# (e.g., metadata.ttl-v3.0.0.core-report.json).
#
# Examples:
#   # Single file
#   ./validate-metadata.sh metadata.ttl v1.0.1
#   ./validate-metadata.sh metadata.ttl v1.1.0 range text/turtle
#   ./validate-metadata.sh metadata.ttl v3.0.0 all
#
#   # Batch mode
#   ./validate-metadata.sh ./metadata v1.1.0
#   ./validate-metadata.sh ./metadata v3.0.0 core_import application/json
#
################################################################################

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
DOMAIN="mobilitydcat-ap"
DEFAULT_PROFILE="core"
TEMP_DIR=$(mktemp -d)
VALIDATION_TYPES=()
PASSED_COUNT=0
FAILED_COUNT=0
ERROR_COUNT=0
REPORT_FILES=()
LAST_RESULT=""
LAST_DETAILS=""

# Cleanup temp directory on exit
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Print usage information
usage() {
    echo -e "${BLUE}mobilityDCAT-AP SHACL Validator${NC}"
    echo ""
    echo "Single file mode:"
    echo "  $0 <file> <validation-type> [profile] [output-format] [validator-url] [output-directory]"
    echo ""
    echo "Batch mode (directory):"
    echo "  $0 <directory> <validation-type> [profile] [output-format] [validator-url] [output-directory]"
    echo ""
    echo "Arguments:"
    echo "  file/directory    RDF file or directory with RDF files (required)"
    echo "  validation-type   Version (e.g., 'v1.1.0', 'v3.0.0') or full validation type"
    echo "                    (e.g., 'v3.0.0.core_import') (required)"
    echo "  profile           Validation profile (default: core, ignored for v1.0.0 and v1.0.1)"
    echo "                    v1.1.0: core, range, full, cv"
    echo "                    v3.0.0: core, core_import, range, range_import, full,"
    echo "                            full_import, cv, cv_import, deprecated"
    echo "                    all:    all the profiles of the version"
    echo "                    Use \"\" to keep the default when passing further arguments"
    echo "  output-format     Report format (default: application/json)"
    echo "                    Options: text/turtle, application/rdf+xml, application/json, application/xml"
    echo "  validator-url     Validator base URL (default: http://localhost:8080)"
    echo "  output-directory  Reports directory (default: ./validation-reports)"
    echo ""
    echo "Reports are saved as <output-directory>/<file name>-<validation type>-report.<ext>"
    echo ""
    echo "Examples:"
    echo "  # Single file"
    echo "  $0 metadata.ttl v1.0.1"
    echo "  $0 metadata.ttl v1.1.0 range text/turtle"
    echo "  $0 metadata.ttl v3.0.0 all"
    echo ""
    echo "  # Batch"
    echo "  $0 ./metadata v1.1.0"
    echo "  $0 ./metadata v3.0.0 core_import application/json"
}

# Print error message
error_exit() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Print warning message
warn() {
    echo -e "${YELLOW}Warning: $1${NC}" >&2
}

# Print info message
info() {
    echo -e "${BLUE}Info: $1${NC}"
}

# Print section header
section() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Check if required tools are available
check_requirements() {
    if ! command -v curl &> /dev/null; then
        error_exit "curl is required but not installed."
    fi
}

# Check whether a value is contained in a list
contains() {
    local value="$1"
    shift
    local item
    for item in "$@"; do
        [[ "$item" == "$value" ]] && return 0
    done
    return 1
}

# Resolve the validation type(s) to use among the ones exposed by the validator
# (configured in config.properties). Sets VALIDATION_TYPES.
resolve_validation_types() {
    local validation_type="$1"
    local profile="$2"
    local validator_url="$3"
    local info_url="${validator_url}/shacl/${DOMAIN}/api/info"

    local response
    response=$(curl -s -f "$info_url") \
        || error_exit "Cannot retrieve the validation types from $info_url (is the validator running?)"

    local available=()
    local type
    while IFS= read -r type; do
        [[ -n "$type" ]] && available+=("$type")
    done < <(echo "$response" | grep -oE '"type"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*"([^"]*)"$/\1/')

    if [[ "$profile" == "all" ]]; then
        # The version itself (if it has no profiles) or all its profiles
        for type in "${available[@]}"; do
            if [[ "$type" == "$validation_type" ]] || \
               [[ "$type" == "$validation_type."* && "${type#"$validation_type".}" != *.* ]]; then
                VALIDATION_TYPES+=("$type")
            fi
        done
    elif [[ -n "$profile" ]] && contains "$validation_type.$profile" "${available[@]}"; then
        VALIDATION_TYPES=("$validation_type.$profile")
    elif contains "$validation_type" "${available[@]}"; then
        # Version without profiles (e.g., v1.0.0) or full validation type (e.g., v3.0.0.core)
        [[ -n "$profile" ]] && warn "Ignoring profile '$profile': '$validation_type' does not support profiles"
        VALIDATION_TYPES=("$validation_type")
    elif [[ -z "$profile" ]] && contains "$validation_type.$DEFAULT_PROFILE" "${available[@]}"; then
        VALIDATION_TYPES=("$validation_type.$DEFAULT_PROFILE")
    fi

    if [[ ${#VALIDATION_TYPES[@]} -eq 0 ]]; then
        error_exit "Invalid validation type '$validation_type'${profile:+ with profile '$profile'}. Available validation types: ${available[*]}"
    fi
}

# Detect content syntax from file extension
detect_content_syntax() {
    local file="$1"
    local extension="${file##*.}"
    
    case "${extension,,}" in
        ttl)
            echo "text/turtle"
            ;;
        rdf|xml)
            echo "application/rdf+xml"
            ;;
        nt|ntriples)
            echo "application/n-triples"
            ;;
        jsonld|json)
            echo "application/ld+json"
            ;;
        *)
            echo "text/turtle"
            ;;
    esac
}

# Get the report file extension from the report syntax
report_extension() {
    case "$1" in
        text/turtle)
            echo "ttl"
            ;;
        application/rdf+xml)
            echo "rdf"
            ;;
        application/xml|text/xml)
            echo "xml"
            ;;
        *)
            echo "json"
            ;;
    esac
}

# Write the JSON payload of the validation request (file content encoded as base64)
build_payload() {
    local input_file="$1"
    local validation_type="$2"
    local report_syntax="$3"
    local payload_file="$4"
    local content_syntax
    content_syntax=$(detect_content_syntax "$input_file")

    {
        printf '{"contentToValidate":"'
        base64 < "$input_file" | tr -d '\n'
        printf '","embeddingMethod":"BASE64","contentSyntax":"%s","validationType":"%s","reportSyntax":"%s"}' \
            "$content_syntax" "$validation_type" "$report_syntax"
    } > "$payload_file"
}

# Parse validation result from a report file
parse_validation_result() {
    local report_file="$1"
    local format="$2"
    
    case "$format" in
        application/json|application/xml|text/xml)
            # TRL report - SUCCESS or WARNING (no errors), FAILURE (errors)
            if grep -qE '"result"[[:space:]]*:[[:space:]]*"(SUCCESS|WARNING)"|<result>(SUCCESS|WARNING)</result>' "$report_file"; then
                echo "PASSED"
            elif grep -qE '"result"[[:space:]]*:[[:space:]]*"FAILURE"|<result>FAILURE</result>' "$report_file"; then
                echo "FAILED"
            else
                echo "UNKNOWN"
            fi
            ;;
        *)
            # RDF formats - check for sh:conforms
            if grep -qE '>true</sh:conforms>|sh:conforms[[:space:]]+true' "$report_file"; then
                echo "PASSED"
            elif grep -qE '>false</sh:conforms>|sh:conforms[[:space:]]+false' "$report_file"; then
                echo "FAILED"
            else
                echo "UNKNOWN"
            fi
            ;;
    esac
}

# Get the number of errors, warnings and infos from a TRL report (empty for RDF reports).
# In TRL reports, nrOfAssertions holds the number of sh:Info results.
report_counters() {
    local report_file="$1"
    local format="$2"
    local errors warnings infos

    case "$format" in
        application/json|application/xml|text/xml)
            errors=$(grep -oE '"nrOfErrors"[[:space:]]*:[[:space:]]*[0-9]+|<nrOfErrors>[0-9]+<' "$report_file" | grep -oE '[0-9]+' | head -n1)
            warnings=$(grep -oE '"nrOfWarnings"[[:space:]]*:[[:space:]]*[0-9]+|<nrOfWarnings>[0-9]+<' "$report_file" | grep -oE '[0-9]+' | head -n1)
            infos=$(grep -oE '"nrOfAssertions"[[:space:]]*:[[:space:]]*[0-9]+|<nrOfAssertions>[0-9]+<' "$report_file" | grep -oE '[0-9]+' | head -n1)
            [[ -n "$errors" ]] && echo "$errors error(s), ${warnings:-0} warning(s), ${infos:-0} info(s)"
            ;;
    esac
}

# Validate a metadata file against a validation type.
# Sets LAST_RESULT (PASSED, FAILED, UNKNOWN or ERROR) and LAST_DETAILS.
validate_file() {
    local input_file="$1"
    local validation_type="$2"
    local report_syntax="$3"
    local validator_url="$4"
    local output_dir="$5"
    local payload_file="$TEMP_DIR/payload.json"
    local response_file="$TEMP_DIR/response"

    LAST_RESULT="ERROR"
    LAST_DETAILS=""
    rm -f "$response_file"

    build_payload "$input_file" "$validation_type" "$report_syntax" "$payload_file"

    # Call API
    local api_url="${validator_url}/shacl/${DOMAIN}/api/validate"
    local http_code
    http_code=$(curl -s -o "$response_file" -w "%{http_code}" -X POST "$api_url" \
        -H "Content-Type: application/json" \
        --data-binary @"$payload_file")

    if [[ "$http_code" != "200" ]]; then
        if [[ "$http_code" == "000" ]]; then
            LAST_DETAILS="Cannot connect to $api_url"
        else
            local message
            message=$(grep -oE '"message"[[:space:]]*:[[:space:]]*"[^"]*"' "$response_file" 2>/dev/null | sed -E 's/.*"([^"]*)"$/\1/')
            LAST_DETAILS="HTTP ${http_code}${message:+: $message}"
        fi
        return 1
    fi

    # Save report
    local report_file="${output_dir}/$(basename "$input_file")-${validation_type}-report.$(report_extension "$report_syntax")"
    if ! mv "$response_file" "$report_file"; then
        LAST_DETAILS="Cannot write report: $report_file"
        return 1
    fi
    REPORT_FILES+=("$report_file")

    # Parse result
    LAST_RESULT=$(parse_validation_result "$report_file" "$report_syntax")
    LAST_DETAILS=$(report_counters "$report_file" "$report_syntax")
}

# Validate each file against each resolved validation type
run_validations() {
    local report_syntax="$1"
    local validator_url="$2"
    local output_dir="$3"
    shift 3
    local files=("$@")
    local total=$(( ${#files[@]} * ${#VALIDATION_TYPES[@]} ))
    local num=0
    local file validation_type

    for file in "${files[@]}"; do
        for validation_type in "${VALIDATION_TYPES[@]}"; do
            num=$((num + 1))
            echo "[$num/$total] $(basename "$file") ($(detect_content_syntax "$file")) -> $validation_type"

            validate_file "$file" "$validation_type" "$report_syntax" "$validator_url" "$output_dir"

            case "$LAST_RESULT" in
                PASSED)
                    echo -e "  Result: ${GREEN}✓ PASSED${NC}${LAST_DETAILS:+ ($LAST_DETAILS)}"
                    PASSED_COUNT=$((PASSED_COUNT + 1))
                    ;;
                FAILED)
                    echo -e "  Result: ${RED}✗ FAILED${NC}${LAST_DETAILS:+ ($LAST_DETAILS)}"
                    FAILED_COUNT=$((FAILED_COUNT + 1))
                    ;;
                *)
                    echo -e "  Result: ${YELLOW}? ${LAST_RESULT}${NC}${LAST_DETAILS:+ ($LAST_DETAILS)}"
                    ERROR_COUNT=$((ERROR_COUNT + 1))
                    ;;
            esac
        done
    done
}

# Print the validation summary
print_summary() {
    local file_count="$1"
    local output_dir="$2"
    local total=$((PASSED_COUNT + FAILED_COUNT + ERROR_COUNT))

    section "Validation Summary"
    echo "Total validations: $total ($file_count file(s) x ${#VALIDATION_TYPES[@]} validation type(s))"
    echo -e "  ${GREEN}Passed: $PASSED_COUNT${NC}"
    echo -e "  ${RED}Failed: $FAILED_COUNT${NC}"
    echo -e "  ${YELLOW}Errors: $ERROR_COUNT${NC}"
    echo ""

    if [[ $total -gt 0 ]]; then
        echo "Success rate: $((PASSED_COUNT * 100 / total))% ($PASSED_COUNT/$total)"
        echo ""
    fi

    echo "Reports saved to: $output_dir"

    if [[ ${#REPORT_FILES[@]} -gt 0 ]]; then
        echo ""
        echo "Generated reports:"
        local report
        for report in "${REPORT_FILES[@]}"; do
            echo "  - $(basename "$report")"
        done
    fi
    echo ""
}

# Main entry point
main() {
    check_requirements
    
    # Validate arguments
    if [[ $# -lt 2 ]]; then
        usage
        error_exit "Missing required arguments"
    fi
    
    local input_path="$1"
    local validation_type="$2"
    local profile="$3"
    local report_syntax="${4:-application/json}"
    local validator_url="${5:-http://localhost:8080}"
    local output_dir="${6:-./validation-reports}"
    validator_url="${validator_url%/}"

    # Detect single file vs batch mode
    local mode
    local files=()
    if [[ -f "$input_path" ]]; then
        mode="Single file validation"
        files=("$input_path")
    elif [[ -d "$input_path" ]]; then
        mode="Batch validation"
        local file
        while IFS= read -r file; do
            files+=("$file")
        done < <(find "$input_path" -type f \( -name "*.ttl" -o -name "*.rdf" -o -name "*.xml" -o -name "*.nt" -o -name "*.jsonld" -o -name "*.json" \) 2>/dev/null | sort)

        if [[ ${#files[@]} -eq 0 ]]; then
            warn "No metadata files found in: $input_path"
            exit 1
        fi
    else
        error_exit "Input path not found (must be a file or directory): $input_path"
    fi

    # Ensure output directory exists
    mkdir -p "$output_dir" || error_exit "Cannot create output directory: $output_dir"

    resolve_validation_types "$validation_type" "$profile" "$validator_url"

    section "mobilityDCAT-AP SHACL Validator"

    info "Mode: $mode"
    info "Input: $input_path (${#files[@]} file(s))"
    info "Validation type(s): ${VALIDATION_TYPES[*]}"
    info "Format: $report_syntax"
    info "URL: $validator_url"
    info "Output: $output_dir"
    echo ""

    run_validations "$report_syntax" "$validator_url" "$output_dir" "${files[@]}"
    print_summary "${#files[@]}" "$output_dir"

    # Exit with appropriate code
    if [[ $FAILED_COUNT -gt 0 ]] || [[ $ERROR_COUNT -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

# Run main
main "$@"
