# mobilityDCAT-AP SHACL Validator

A SHACL-based validator for mobilityDCAT-AP metadata, supporting validation of RDF documents against mobilityDCAT-AP SHACL constraints. 

This repo provides a configuration of the ITB SHACL Validator according to the guidelines [here](https://www.itb.ec.europa.eu/docs/guides/latest/validatingRDF), an MCP server is configured in the repo to access the related documentation via agents.

## Overview

This project provides a standalone SHACL validator for the mobilityDCAT-AP specification, allowing validation of RDF metadata against predefined SHACL shapes for different versions (v1.0.0, v1.0.1, v1.1.0, v3.0.0) and validation profiles.

### Supported Versions and Profiles

- **mobilityDCAT-AP v1.0.0**
  - Default validation profile

- **mobilityDCAT-AP v1.0.1**
  - Default validation profile

- **mobilityDCAT-AP v1.1.0**
  - `core`: Core Constraints
  - `range`: Range and Core Constraints
  - `full`: Controlled Vocabularies, Range and Core Constraints
  - `cv`: Controlled Vocabularies

- **mobilityDCAT-AP v3.0.0**
  - `core`: Core Constraints
  - `core_import`: Core Constraints (with background knowledge)
  - `range`: Range and Core Constraints
  - `range_import`: Range and Core Constraints (with background knowledge)
  - `full`: Controlled Vocabularies, Range and Core Constraints
  - `full_import`: Controlled Vocabularies, Range and Core Constraints (with background knowledge)
  - `cv`: Controlled Vocabularies
  - `cv_import`: Controlled Vocabularies (with background knowledge)
  - `deprecated`: Deprecated Constraints

The v3.0.0 `*_import` profiles also load background knowledge together with the shapes: the ontologies of the reused vocabularies (`imports.ttl`) for `core_import`, `range_import` and `full_import`, and the EU authority tables and mobilityDCAT-AP controlled vocabularies (`mdr-imports.ttl`) for `full_import` and `cv_import`. The profiles without `_import` evaluate the input data only, so controlled-vocabulary checks (e.g., `skos:inScheme`) pass only if the input includes the vocabulary triples. The `deprecated` profile reports (as warnings) the use of properties deprecated in mobilityDCAT-AP v3.0.0.

The validation types exposed by the validator are `v1.0.0`, `v1.0.1` and `<version>.<profile>` (e.g., `v3.0.0.cv_import`), as defined in [config.properties](resources/mobilityDCAT-AP/config.properties).

## Quick Start with Docker

Navigate to the project root and run:

```bash
docker pull ghcr.io/mobilitydcat-ap/itb-validator-mobilitydcat-ap:1.0
```

Alternatively, you can build the image locally:
```bash
docker build -t ghcr.io/mobilitydcat-ap/itb-validator-mobilitydcat-ap:latest .
```

**Important:** Each domain must be a subfolder under `resources/` containing a `config.properties` file. The subfolder name becomes the domain name. The one for **mobilityDCAT-AP** is already configured.

### Run the Validator

```bash
docker run -d \
  --name mobilitydcat-validator \
  -p 8080:8080 \
  ghcr.io/mobilitydcat-ap/itb-validator-mobilitydcat-ap:1.0
```

## Usage

### Web Interface

Navigate to `http://localhost:8080/shacl/mobilitydcat-ap/upload` to validate RDF metadata via the web interface.

### REST API

Validate RDF content programmatically using the REST API documented at this [link](https://www.itb.ec.europa.eu/docs/guides/latest/validatingRDF/index.html#validation-via-rest-web-service-api).

### Validation Script

The `validate-metadata.sh` script validates a single file or all the RDF files of a directory (batch mode) through the REST API. It detects whether the input is a file or a directory, and both modes share the same parameters.

```bash
./validate-metadata.sh <file|directory> <validation-type> [profile] [output-format] [validator-url] [output-directory]
```

| Argument | Required | Default | Description |
|---|---|---|---|
| `file\|directory` | yes | — | RDF file or directory of RDF files |
| `validation-type` | yes | — | Version (`v1.0.0`, `v1.0.1`, `v1.1.0`, `v3.0.0`) or full validation type (e.g., `v3.0.0.core_import`) |
| `profile` | no | `core` | v1.1.0: `core`, `range`, `full`, `cv`<br>v3.0.0: `core`, `core_import`, `range`, `range_import`, `full`, `full_import`, `cv`, `cv_import`, `deprecated`<br>`all`: all the profiles of the version<br>Ignored for v1.0.0 and v1.0.1. Use `""` to keep the default when passing further arguments. |
| `output-format` | no | `application/json` | `application/json`, `application/xml` (TRL report), `text/turtle`, `application/rdf+xml` (SHACL report) |
| `validator-url` | no | `http://localhost:8080` | Validator base URL |
| `output-directory` | no | `./validation-reports` | Directory for report files |

**Supported file types:** `.ttl`, `.rdf`, `.xml` (RDF/XML), `.nt`, `.jsonld`, `.json`

The script reads the available validation types from `<validator-url>/shacl/mobilitydcat-ap/api/info`, so the validator must be running and reachable. Each report is saved as `<output-directory>/<file name>-<validation type>-report.<ext>` (e.g., `metadata.ttl-v3.0.0.core-report.json`). For JSON and XML reports, the number of errors, warnings and infos is printed for each validation. The script exits with code `0` if all validations pass (warnings and infos do not make a validation fail) and `1` otherwise.

In batch mode, all files are validated against the same validation type(s). The sample files in [metadata/](metadata/) are prefixed with the version they target (e.g., `v3.0.0-complete.ttl`).

**Examples:**

```bash
# Single file — v1.0.0 (no profiles), JSON report
./validate-metadata.sh metadata.ttl v1.0.0

# Single file — v1.1.0 range profile, RDF/XML report
./validate-metadata.sh metadata.ttl v1.1.0 range application/rdf+xml

# Single file — all v3.0.0 profiles
./validate-metadata.sh metadata/v3.0.0-complete.ttl v3.0.0 all

# Single file — full validation type
./validate-metadata.sh metadata.ttl v3.0.0.core_import

# Batch — all files with the v1.1.0 range profile
./validate-metadata.sh ./metadata v1.1.0 range application/json

# Batch — default profile, Turtle reports in a custom directory
./validate-metadata.sh ./metadata v3.0.0 "" text/turtle http://localhost:8080 ./reports

# Batch — v3.0.0 CV profile with background knowledge against a remote validator
./validate-metadata.sh ./metadata v3.0.0 cv_import application/json http://validator.example.com:8080 ./reports
```

## License

Please refer to the mobilityDCAT-AP specification license and ITB software license.

## Support

For issues and feature requests, please open an issue or contact the ITB support team.
