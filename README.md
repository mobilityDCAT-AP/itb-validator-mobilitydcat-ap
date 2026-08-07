# mobilityDCAT-AP SHACL Validator

A SHACL-based validator for mobilityDCAT-AP metadata, supporting validation of RDF documents against mobilityDCAT-AP SHACL constraints. 

This repo provides a configuration of the ITB SHACL Validator according to the guidelines [here](https://www.itb.ec.europa.eu/docs/guides/latest/validatingRDF), an MCP server is configured in the repo to access the related documentation via agents.

## Overview

This project provides a standalone SHACL validator for the mobilityDCAT-AP specification, allowing validation of RDF metadata against predefined SHACL shapes for different versions (v1.1.0, v3.0.0) and validation profiles.

### Supported Versions and Profiles

- **mobilityDCAT-AP v1.1.0**
  - `core`: Core Constraints
  - `range`: Range and Core Constraints
  - `full`: Controlled Vocabularies, Range and Core Constraints
  - `cv`: Controlled Vocabularies

- **mobilityDCAT-AP v3.0.0**
  - `core`: Core Constraints
  - `range`: Range and Core Constraints
  - `full`: Controlled Vocabularies, Range and Core Constraints
  - `cv`: Controlled Vocabularies

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

Navigate to `http://localhost:8080/shacl/mobilityDCAT-AP/upload` to validate RDF metadata via the web interface.

### REST API

Validate RDF content programmatically using the REST API documented at this [link](https://www.itb.ec.europa.eu/docs/guides/latest/validatingRDF/index.html#validation-via-rest-web-service-api).

### Validation Script

The unified `validate-metadata.sh` script handles both single file and batch validation. It automatically detects whether the input is a file or directory.

The script auto-detects whether the input is a file or a directory and runs in single or batch mode accordingly. Both modes share the same parameters.

```bash
./validate-metadata.sh <file|directory> <validation-type> [profile] [output-format] [validator-url] [output-directory]
```

| Argument | Required | Default | Description |
|---|---|---|---|
| `file\|directory` | yes | — | RDF file or directory of RDF files |
| `validation-type` | yes | — | Version: `v1.1.0`, `v3.0.0` |
| `profile` | no | `core` | `core`, `range`, `full`, `cv` |
| `output-format` | no | `application/json` | `application/json`, `application/rdf+xml`, `text/turtle`, `application/xml` |
| `validator-url` | no | `http://localhost:8080` | Validator base URL |
| `output-directory` | no | `./validation-reports` | Directory for report files |

**Supported file types (batch):** `.ttl`, `.rdf`, `.nt`, `.jsonld`, `.json`

**Examples:**

```bash
# Single file — core profile, JSON report
./validate-metadata.sh metadata.ttl v1.1.0

# Single file — range profile, RDF/XML report
./validate-metadata.sh metadata.ttl v1.1.0 range application/rdf+xml

# Batch — all files with range profile
./validate-metadata.sh ./metadata v1.1.0 range application/json

# Batch — v3.0.0 CV profile against a remote validator
./validate-metadata.sh ./metadata v3.0.0 cv application/json http://validator.example.com:8080 ./reports
```

## License

Please refer to the mobilityDCAT-AP specification license and ITB software license.

## Support

For issues and feature requests, please open an issue or contact the ITB support team.
