#!/bin/bash

################################################################################
# mobilityDCAT-AP Validator Script
#
# This script validates RDF metadata files against mobilityDCAT-AP SHACL shapes
# by invoking the REST API of the SHACL validator.
#
# Supports both single file and batch (directory) validation.
#
# Usage:
#   Single file:    ./validate-metadata.sh <file> <validation-type> [profile] [output-format] [validator-url] [output-directory]
#   Batch mode:     ./validate-metadata.sh <directory> <validation-type> [profile] [output-format] [validator-url] [output-directory]
#
# Arguments:
#   file/directory  Path to an RDF file or directory containing RDF files (required)
#   validation-type Version (e.g., "v1.1.0", "v3.0.0") (required)
#   profile         Validation profile (default: core)
#                   Options: core, range, full, cv
#   output-format   Report format (default: application/json)
#                   Options: text/turtle, application/rdf+xml, application/json, application/xml
#   validator-url   Base URL of validator (default: http://localhost:8080)
#   output-dir      Directory for reports (default: ./validation-reports)
#
# Examples:
#   # Single file
#   ./validate-metadata.sh metadata.ttl v1.1.0
#   ./validate-metadata.sh metadata.ttl v1.1.0 range text/turtle
#
#   # Batch mode
#   ./validate-metadata.sh ./metadata v1.1.0
#   ./validate-metadata.sh ./metadata v1.1.0 range application/json
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
TEMP_DIR=$(mktemp -d)
BATCH_MODE=false
PROFILE="core"
PASSED_COUNT=0
FAILED_COUNT=0
ERROR_COUNT=0
REPORT_FILES=()

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
    echo "  validation-type   Version (e.g., 'v1.1.0', 'v3.0.0') (required)"
    echo "  profile           Validation profile: core, range, full, cv (default: core)"
    echo "  output-format     Report format (default: application/json)"
    echo "                    Options: text/turtle, application/rdf+xml, application/json, application/xml"
    echo "  validator-url     Validator base URL (default: http://localhost:8080)"
    echo "  output-directory  Reports directory (default: ./validation-reports)"
    echo ""
    echo "Examples:"
    echo "  # Single file"
    echo "  $0 metadata.ttl v1.1.0"
    echo "  $0 metadata.ttl v1.1.0 range text/turtle"
    echo ""
    echo "  # Batch"
    echo "  $0 ./metadata v1.1.0"
    echo "  $0 ./metadata v1.1.0 range application/json"
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

# Detect content syntax from file extension
detect_content_syntax() {
    local file="$1"
    local extension="${file##*.}"
    
    case "${extension,,}" in
        ttl)
            echo "text/turtle"
            ;;
        rdf)
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

# Encode file content as base64
encode_file_base64() {
    local file="$1"
    cat "$file" | base64 | tr -d '\n'
}

# Parse validation result from report
parse_validation_result() {
    local report="$1"
    local format="$2"
    
    case "$format" in
        application/json)
            if echo "$report" | grep -q '"result":"SUCCESS"'; then
                echo "PASSED"
                return 0
            else
                echo "FAILED"
                return 1
            fi
            ;;
        *)
            # RDF formats - check for sh:conforms
            if echo "$report" | grep -q '>true</sh:conforms'; then
                echo "PASSED"
                return 0
            elif echo "$report" | grep -q '>false</sh:conforms'; then
                echo "FAILED"
                return 1
            else
                echo "UNKNOWN"
                return 2
            fi
            ;;
    esac
}

# Validate a single metadata file
validate_file() {
    local input_file="$1"
    local validation_type="$2"
    local profile="${3:-core}"
    local report_syntax="${4:-application/json}"
    local validator_url="${5:-http://localhost:8080}"
    local output_dir="${6:-.}"
    
    local content_syntax=$(detect_content_syntax "$input_file")
    local encoded_content=$(encode_file_base64 "$input_file")
    local full_validation_type="${validation_type}.${profile}"
    
    # Create payload
    local payload=$(cat <<EOF
{
  "contentToValidate": "$encoded_content",
  "embeddingMethod": "BASE64",
  "contentSyntax": "$content_syntax",
  "validationType": "$full_validation_type",
  "reportSyntax": "$report_syntax"
}
EOF
)
    
    # Call API
    local api_url="${validator_url}/shacl/${DOMAIN}/api/validate"
    local response=$(curl -s -w "\n%{http_code}" -X POST "$api_url" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>&1)
    
    # Extract HTTP code and body
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n-1)
    
    # DEBUG
    # echo "DEBUG: http_code=$http_code body=$body" >&2
    
    if [[ "$http_code" -ne 200 ]]; then
        echo "UNKNOWN" >&2
        return 2
    fi
    
    # Save report
    local filebase="${input_file%.*}"
    local report_ext="json"
    [[ "$report_syntax" == "text/turtle" ]] && report_ext="ttl"
    [[ "$report_syntax" == "application/json" ]] && report_ext="json"
    [[ "$report_syntax" == "application/rdf+xml" ]] && report_ext="rdf"
    [[ "$report_syntax" == "application/xml" ]] && report_ext="xml"
    
    local report_file="${output_dir}/${filebase##*/}-report.${report_ext}"
    echo "$body" > "$report_file" 2>/dev/null || true
    REPORT_FILES+=("$report_file")
    
    # Parse result
    parse_validation_result "$body" "$report_syntax"
}

# Single file validation mode
validate_single_file() {
    local input_file="$1"
    local validation_type="$2"
    local profile="${3:-core}"
    local report_syntax="${4:-application/json}"
    local validator_url="${5:-http://localhost:8080}"
    local output_dir="${6:-./validation-reports}"
    
    if [[ ! -f "$input_file" ]]; then
        error_exit "File not found: $input_file"
    fi
    
    # Ensure output directory exists
    mkdir -p "$output_dir" || error_exit "Cannot create output directory: $output_dir"
    
    section "mobilityDCAT-AP SHACL Validator"
    
    info "Mode: Single file validation"
    info "File: $input_file"
    info "Type: $validation_type"
    info "Profile: $profile"
    info "Format: $report_syntax"
    echo ""
    
    local content_syntax=$(detect_content_syntax "$input_file")
    info "Detected syntax: $content_syntax"
    echo ""
    
    # Call validate_file and capture both result and exit code
    local result
    result=$(validate_file "$input_file" "$validation_type" "$profile" "$report_syntax" "$validator_url" "$output_dir" 2>&1)
    local exit_code=$?
    
    # Trim whitespace and remove debug lines
    result=$(echo "$result" | grep -v "^DEBUG:" | xargs)
    
    echo -n "Result: "
    case "$result" in
        PASSED)
            echo -e "${GREEN}✓ PASSED${NC}"
            echo ""
            info "Report saved to: $output_dir"
            exit 0
            ;;
        FAILED)
            echo -e "${RED}✗ FAILED${NC}"
            echo ""
            info "Report saved to: $output_dir"
            exit 1
            ;;
        *)
            echo -e "${RED}✗ FAILED${NC}"
            echo ""
            echo "Error: $result"
            exit 1
            ;;
    esac
}

# Batch validation mode
validate_batch() {
    local metadata_dir="$1"
    local validation_type="$2"
    local profile="${3:-core}"
    local report_syntax="${4:-application/json}"
    local validator_url="${5:-http://localhost:8080}"
    local output_dir="${6:-./validation-reports}"
    
    if [[ ! -d "$metadata_dir" ]]; then
        error_exit "Directory not found: $metadata_dir"
    fi
    
    section "mobilityDCAT-AP Batch SHACL Validator"
    
    info "Configuration:"
    info "  Directory: $metadata_dir"
    info "  Type: $validation_type"
    info "  Profile: $profile"
    info "  Format: $report_syntax"
    info "  URL: $validator_url"
    info "  Output: $output_dir"
    echo ""
    
    # Create output directory
    mkdir -p "$output_dir"
    
    # Find and collect files
    local files=()
    while IFS= read -r file; do
        files+=("$file")
    done < <(find "$metadata_dir" -type f \( -name "*.ttl" -o -name "*.rdf" -o -name "*.nt" -o -name "*.jsonld" -o -name "*.json" \) 2>/dev/null | sort)
    
    local total=${#files[@]}
    if [[ $total -eq 0 ]]; then
        warn "No metadata files found in: $metadata_dir"
        exit 1
    fi
    
    section "Batch Validation"
    info "Found $total file(s)"
    echo ""
    
    # Process each file
    local file_num=0
    for file in "${files[@]}"; do
        ((file_num++))
        local filename=$(basename "$file")
        echo "[$file_num/$total] $filename"
        
        local result=$(validate_file "$file" "$validation_type" "$profile" "$report_syntax" "$validator_url" "$output_dir")
        local exit_code=$?
        
        case "$result" in
            PASSED)
                echo -e "  Result: ${GREEN}✓ PASSED${NC}"
                ((PASSED_COUNT++))
                ;;
            FAILED)
                echo -e "  Result: ${RED}✗ FAILED${NC}"
                ((FAILED_COUNT++))
                ;;
            *)
                echo -e "  Result: ${YELLOW}? ERROR${NC}"
                ((ERROR_COUNT++))
                ;;
        esac
    done
    
    # Print summary
    section "Validation Summary"
    echo "Total files: $total"
    echo -e "  ${GREEN}Passed: $PASSED_COUNT${NC}"
    echo -e "  ${RED}Failed: $FAILED_COUNT${NC}"
    echo -e "  ${YELLOW}Errors: $ERROR_COUNT${NC}"
    echo ""
    
    if [[ $total -gt 0 ]]; then
        local pass_percent=$((PASSED_COUNT * 100 / total))
        echo "Success rate: $pass_percent% ($PASSED_COUNT/$total)"
    fi
    
    echo ""
    echo "Reports saved to: $output_dir"
    
    if [[ ${#REPORT_FILES[@]} -gt 0 ]]; then
        echo ""
        echo "Generated reports:"
        for report in "${REPORT_FILES[@]}"; do
            echo "  - $(basename "$report")"
        done
    fi
    echo ""
    
    # Exit with appropriate code
    if [[ $FAILED_COUNT -gt 0 ]] || [[ $ERROR_COUNT -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
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
    shift 2
    
    # Detect single file vs batch mode
    if [[ -f "$input_path" ]]; then
        # Single file mode
        validate_single_file "$input_path" "$validation_type" "$@"
    elif [[ -d "$input_path" ]]; then
        # Batch mode
        validate_batch "$input_path" "$validation_type" "$@"
    else
        error_exit "Input path not found (must be a file or directory): $input_path"
    fi
}

# Run main
main "$@"
